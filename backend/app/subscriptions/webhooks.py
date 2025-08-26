# backend/app/subscriptions/webhooks.py
from flask import Blueprint, request, jsonify
from datetime import datetime, timezone
from decimal import Decimal
from sqlalchemy import text
from app.db.database import db
from app.subscriptions.models import UserSubscription
import os, re, json, hmac, hashlib

webhooks_bp = Blueprint(
    "webhooks_subscriptions",
    __name__,
    url_prefix="/webhooks/subscriptions",
)

# 🔐 Firma (actívala en prod con VERIFY_WEBHOOK_SIGNATURE=true)
VERIFY_SIGNATURE = (os.getenv("VERIFY_WEBHOOK_SIGNATURE", "false").lower() == "true")
WEBHOOK_SECRET   = os.getenv("REVENUECAT_WEBHOOK_SECRET", "").strip()  # 👈 no uses la API key pública
APP_USER_NS      = os.getenv("APP_USER_ID_NAMESPACE", "").strip()      # ej: "cm_apuestas"

def _valid_signature(raw_body: bytes, header_sig: str) -> bool:
    if not WEBHOOK_SECRET or not header_sig:
        return False
    expected = hmac.new(WEBHOOK_SECRET.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header_sig)

def _extract_amount_currency_tx(event: dict):
    """
    Extrae (precio bruto pagado, moneda, transaction_id) de un evento de RevenueCat.
    Usamos varias llaves posibles por robustez.
    """
    # precio
    price_candidates = [
        event.get("price"),
        event.get("price_in_purchased_currency"),
        event.get("purchased_price"),
        event.get("revenue"),  # a veces viene como revenue neto
    ]
    price_val = next((p for p in price_candidates if isinstance(p, (int, float, str)) and str(p).strip() != ""), 0)

    try:
        amount = Decimal(str(price_val))
    except Exception:
        amount = Decimal("0")

    # moneda
    currency = (
        event.get("currency")
        or event.get("purchased_currency")
        or event.get("store_currency_code")
        or "COP"
    )
    currency = str(currency).upper().strip()[:3] or "COP"

    # transaction id
    tx_id = (
        event.get("transaction_id")
        or event.get("original_transaction_id")
        or event.get("id")
        or ""
    )
    tx_id = str(tx_id).strip() or None

    return amount, currency, tx_id

def _maybe_award_referral_bonus(user_id: int, event: dict, event_type: str):
    """
    Si el usuario tiene un referidor y este evento es una compra inicial,
    crea un referral_reward = 50% del precio.
    Idempotente por transaction_id (external_ref).
    """
    # Solo otorgamos en compra inicial (ajusta si quieres también en PRODUCT_CHANGE)
    if event_type not in {"INITIAL_PURCHASE"}:
        return

    amount, currency, external_ref = _extract_amount_currency_tx(event)
    # si no hay monto, no hay nada que premiar
    if amount <= 0:
        return

    commission = (amount * Decimal("0.50")).quantize(Decimal("0.01"))

    # 1) Buscar referral del usuario (el último/primero, mientras haya un vínculo)
    ref_row = db.session.execute(
        text("""
            SELECT id, referrer_user_id, status
            FROM referrals
            WHERE referred_user_id = :uid
            ORDER BY created_at ASC
            LIMIT 1
        """),
        {"uid": user_id}
    ).mappings().first()

    if not ref_row:
        return  # no tiene quien lo refirió

    referral_id = int(ref_row["id"])
    beneficiary_id = int(ref_row["referrer_user_id"])

    # 2) Idempotencia: si ya creamos reward para este transaction_id, no repetir
    if external_ref:
        dup = db.session.execute(
            text("""
                SELECT 1
                FROM referral_rewards
                WHERE external_ref = :tx
                  AND beneficiary_user_id = :bid
                LIMIT 1
            """),
            {"tx": external_ref, "bid": beneficiary_id}
        ).first()
        if dup:
            # ya existe ese reward por este pago
            pass
        else:
            db.session.execute(
                text("""
                    INSERT INTO referral_rewards
                        (referral_id, beneficiary_user_id, kind, amount, currency, status, triggered_by, external_ref, created_at)
                    VALUES
                        (:rid, :bid, 'pro_purchase', :amt, :cur, 'pending', :src, :tx, NOW())
                """),
                {
                    "rid": referral_id,
                    "bid": beneficiary_id,
                    "amt": str(commission),
                    "cur": currency,
                    "src": f"revenuecat:{event_type.lower()}",
                    "tx": external_ref,
                }
            )
    else:
        # sin transaction_id, al menos evita duplicar por referral_id+kind del mismo día (heurística)
        db.session.execute(
            text("""
                INSERT INTO referral_rewards
                    (referral_id, beneficiary_user_id, kind, amount, currency, status, triggered_by, created_at)
                VALUES
                    (:rid, :bid, 'pro_purchase', :amt, :cur, 'pending', :src, NOW())
            """),
            {
                "rid": referral_id,
                "bid": beneficiary_id,
                "amt": str(commission),
                "cur": currency,
                "src": f"revenuecat:{event_type.lower()}",
            }
        )

    # 3) Marcar referral como convertido (si no lo estaba)
    db.session.execute(
        text("""
            UPDATE referrals
            SET status = 'converted',
                converted_at = COALESCE(converted_at, NOW()),
                updated_at = NOW()
            WHERE id = :rid
              AND status <> 'converted'
        """),
        {"rid": referral_id}
    )

@webhooks_bp.post("/revenuecat")
def revenuecat_webhook():
    raw_bytes = request.get_data(cache=False)
    raw_text  = raw_bytes.decode("utf-8", errors="ignore")

    # (Prod) Verificar firma
    if VERIFY_SIGNATURE:
        header_sig = request.headers.get("X-RevenueCat-Signature", "")
        if not _valid_signature(raw_bytes, header_sig):
            return jsonify({"ok": False, "error": "invalid_signature"}), 401

    # Parse tolerante
    try:
        payload = json.loads(raw_text) if raw_text else {}
    except Exception:
        payload = request.get_json(silent=True) or {}

    event = (payload.get("event") or {})
    event_type = str(event.get("type", "")).upper()  # RC: INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, etc.

    # App user id (ej: "cm_apuestas:22")
    subscriber_id = (
        event.get("app_user_id")
        or payload.get("app_user_id")
        or payload.get("subscriber_id")
        or (payload.get("subscriber") or {}).get("app_user_id")
    )
    subscriber_id_str = str(subscriber_id or "")

    # user_id desde namespace o últimos dígitos
    if APP_USER_NS and subscriber_id_str.startswith(f"{APP_USER_NS}:"):
        candidate = subscriber_id_str.split(":", 1)[1].strip()
    else:
        m = re.search(r"(\d+)$", subscriber_id_str)
        candidate = m.group(1) if m else ""
    try:
        user_id = int(candidate)
    except ValueError:
        user_id = None

    if not user_id:
        return jsonify({
            "ok": False,
            "error": "user_id_not_found_in_subscriber_id",
            "debug": {
                "namespace_env": APP_USER_NS,
                "subscriber_id_received": subscriber_id_str,
                "payload_top_level_keys": list(payload.keys()),
                "event_keys": list(event.keys()),
            }
        }), 400

    # Entitlements (puede venir como lista); si no, default 'pro'
    entitlements = event.get("entitlement_ids") or []
    if not entitlements and "entitlement_id" in event:
        entitlements = [event.get("entitlement_id")]
    if not entitlements:
        entitlements = ["pro"]

    # Fechas
    expiration_ms = event.get("expiration_at_ms") or event.get("expires_at_ms")
    expires_at = None
    if isinstance(expiration_ms, (int, float)):
        try:
            expires_at = datetime.fromtimestamp(expiration_ms / 1000, tz=timezone.utc)
        except Exception:
            expires_at = None

    now = datetime.now(timezone.utc)

    # Mapear estado según tipo de evento + expiración
    def compute_state(ev_type: str, dt_exp):
        if ev_type in {"INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"}:
            return True, "active"
        if ev_type in {"CANCELLATION"}:
            # sigue activo hasta que llegue la fecha de expiración
            if dt_exp and dt_exp > now:
                return True, "canceled"
            return False, "expired"
        if ev_type in {"EXPIRATION"}:
            return False, "expired"
        if ev_type in {"BILLING_ISSUE"}:
            # muchos comercios mantienen acceso hasta expirar
            if dt_exp and dt_exp > now:
                return True, "billing_issue"
            return False, "expired"
        # Default conservador: activo si no ha expirado
        if dt_exp and dt_exp > now:
            return True, "active"
        return False, "expired"

    is_active_flag, status_str = compute_state(event_type, expires_at)

    # Para cada entitlement relevante (normalmente 1: 'pro')
    updated = []
    for ent in entitlements:
        ent_id = str(ent or "pro")
        sub = UserSubscription.query.filter_by(user_id=user_id, entitlement=ent_id).first()

        if not sub:
            sub = UserSubscription(
                user_id=user_id,
                entitlement=ent_id,
                is_active=is_active_flag,
                status=status_str,
                current_period_end=expires_at,
                original_app_user_id=subscriber_id_str,
            )
            db.session.add(sub)
        else:
            sub.is_active = is_active_flag
            sub.status = status_str
            sub.current_period_end = expires_at
            sub.original_app_user_id = subscriber_id_str

        updated.append(ent_id)

    # 🎯 Crear recompensa de referido en compra inicial (si aplica)
    _maybe_award_referral_bonus(user_id, event, event_type)

    db.session.commit()

    return jsonify({
        "ok": True,
        "event_type": event_type,
        "user_id": user_id,
        "entitlements": updated,
        "is_active": is_active_flag,
        "status": status_str,
        "expires_at": expires_at.isoformat() if expires_at else None,
    }), 200
