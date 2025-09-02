# app/subscriptions/service.py
from dataclasses import dataclass
from typing import Optional, Dict, Any

from app.db.database import db
from app.subscriptions.models import UserSubscription
from app.subscriptions.google_play_client import build_android_publisher
import os
from googleapiclient.errors import HttpError
from sqlalchemy import or_
from datetime import datetime, timezone, timedelta
from app.services.referrals.payouts_service import register_referral_commission
import json
from flask import current_app

from app.observability.metrics import (
    SUBS_SYNC_OK, SUBS_SYNC_ERR,
    RTDN_RCVD, RTDN_ERR,
    RECONCILE_UPD, RECONCILE_ERR
)

def _log_event(event: str, **fields):
    try:
        current_app.logger.info(json.dumps({"event": event, **fields}, default=str))
    except Exception:
        # Fallback por si no hay app context
        print(json.dumps({"event": event, **fields}, default=str))

def _credit_referral_if_any(*, purchaser_user_id: int, product_id: str,
                            purchase_token: str, order_id: str | None,
                            price_amount_micros: int, price_currency_code: str,
                            event_time=None):
    """Crea UNA comisión por compra/renovación (idempotente por token+order_id)."""
    try:
        # 🚧 Normaliza event_time a datetime aware UTC
        if event_time is not None:
            if isinstance(event_time, datetime):
                if event_time.tzinfo is None:
                    event_time = event_time.replace(tzinfo=timezone.utc)
                else:
                    event_time = event_time.astimezone(timezone.utc)
            else:
                # _parse_gp_time ya convierte ms/seg/RFC3339 → datetime UTC
                event_time = _parse_gp_time(event_time)

        register_referral_commission(
            referred_user_id=purchaser_user_id,
            product_id=product_id or "unknown",
            amount_micros=price_amount_micros or 0,
            currency_code=price_currency_code or "COP",
            purchase_token=purchase_token,
            order_id=order_id,
            source="google_play",
            event_time=event_time,  # ✅ siempre datetime UTC o None
        )
    except Exception:
        db.session.rollback()
        raise

@dataclass
class SubscriptionStatus:
    user_id: Optional[int]
    entitlement: str
    is_premium: bool
    expires_at: Optional[str]
    status: str
    reason: Optional[str] = None
    since: Optional[str] = None              # inicio del periodo vigente
    auto_renewing: Optional[bool] = None     # si se renueva automáticamente
    
    def to_json(self) -> Dict[str, Any]:
        # Mantén camelCase para Flutter
        return {
            "userId": self.user_id,
            "entitlement": self.entitlement,
            "isPremium": self.is_premium,
            "expiresAt": self.expires_at,
            "status": self.status,
            "reason": self.reason,
            "since": self.since,
            "autoRenewing": self.auto_renewing,
        }


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _to_aware_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Normaliza cualquier datetime a 'aware UTC'. Si es None, devuelve None."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        # Asume que el valor guardado es UTC naive y lo marca como UTC.
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)

def _decide_status(subscription_state: str, auto_renewing: Optional[bool], expiry_dt: Optional[datetime]) -> tuple[str, bool]:
    """
    Devuelve (status_str, is_active_bool) coherente con V2:
    - Mientras no venza:
        * auto_renewing=True  -> 'active'
        * auto_renewing=False -> 'canceled' (acceso vigente hasta expiry)
    - Si ya venció -> 'expired', is_active=False
    - También soporta estados de Google como GRACE/ON_HOLD si te interesan.
    """
    now = _now_utc()
    if not expiry_dt or expiry_dt <= now:
        return "expired", False

    s = (subscription_state or "").upper()
    if s in ("IN_GRACE_PERIOD", "GRACE"):
        return "grace", True
    if s in ("ON_HOLD",):
        return "on_hold", True
    if s in ("PAUSED",):
        return "paused", True

    # Google normalmente reporta ACTIVE incluso tras cancelar, pero con autoRenewing=False
    if auto_renewing is False:
        return "canceled", True

    # Por defecto, si está vigente y auto_renewing no es False, lo tratamos como active
    return "active", True


def _parse_gp_time(v) -> Optional[datetime]:
    """
    Acepta:
      - int/float o str numérica en milisegundos/segundos desde epoch
      - str en RFC3339/ISO8601 (p. ej. '2025-09-01T16:38:06.465Z')
    Devuelve datetime timezone-aware en UTC o None.
    """
    if v is None:
        return None
    try:
        if isinstance(v, (int, float)):
            iv = int(v)
            # Heurística: > 1e12 => milisegundos
            return datetime.fromtimestamp(iv / 1000.0 if iv > 1_000_000_000_000 else iv, tz=timezone.utc)
        if isinstance(v, str):
            s = v.strip()
            if s.isdigit():
                iv = int(s)
                return datetime.fromtimestamp(iv / 1000.0 if iv > 1_000_000_000_000 else iv, tz=timezone.utc)
            # RFC3339 -> ISO compatible
            s = s.replace('Z', '+00:00')
            return datetime.fromisoformat(s).astimezone(timezone.utc)
    except Exception:
        return None

def _pick_line_item(line_items: list[dict]) -> dict:
    """
    Devuelve el lineItem 'vigente/reciente'.
    Regla: el de MAYOR expiryTime (ms o RFC3339). Si no hay fechas válidas, retorna el primero.
    """
    def _expiry_of(li: dict) -> Optional[datetime]:
        v = li.get("expiryTime") or li.get("expiryTimeMillis")
        return _parse_gp_time(v)

    items = [li for li in (line_items or []) if isinstance(li, dict)]
    if not items:
        return {}

    best = None
    best_exp = None
    for li in items:
        exp = _expiry_of(li)
        if exp is None:
            continue
        if best is None or exp > best_exp:
            best, best_exp = li, exp
    return best or items[0]

def _price_from_catalog(product_id: str, default_currency: str = "COP") -> tuple[int, str]:
    """
    Busca un precio de catálogo para el product_id.
    Hace match por prefijo para cubrir variantes de base plan / offers.
    Devuelve (price_micros, currency).
    """
    CATALOG = {
        "cm_suscripcion": (10_000_000, "COP"),  # 10.000 COP en micros
        # agrega otros productos si tienes...
    }
    pid = (product_id or "").strip()
    # match exacto
    if pid in CATALOG:
        return CATALOG[pid]
    # match por prefijo (ej: "cm_suscripcion:plan_mensual")
    for k, v in CATALOG.items():
        if pid.startswith(k):
            return v
    return (0, default_currency)

def get_status(user_id: Optional[int]) -> SubscriptionStatus:
    """
    Devuelve el estado de suscripción del usuario.
    is_premium = True cuando:
      - sub.is_active == True, o
      - sub.status == "active", o
      - sub.status == "canceled" pero current_period_end > ahora (aún dentro del periodo pagado).
    """
    if not user_id:
        return SubscriptionStatus(
            user_id=None,
            entitlement="pro",
            is_premium=False,
            expires_at=None,
            status="none",
            reason="not_authenticated",
        )

    sub: Optional[UserSubscription] = (
        UserSubscription.query
        .filter_by(user_id=int(user_id), entitlement="pro")
        .first()
    )

    if not sub:
        return SubscriptionStatus(
            user_id=int(user_id),
            entitlement="pro",
            is_premium=False,
            expires_at=None,
            status="none",
            reason=None,
        )

    # Fechas normalizadas a UTC
    end_at_utc = _to_aware_utc(getattr(sub, "current_period_end", None))
    start_at_utc = _to_aware_utc(getattr(sub, "current_period_start", None))
    now = _now_utc()

    period_active = bool(end_at_utc and end_at_utc > now)
    status_str = getattr(sub, "status", "none") or "none"
    auto_renewing = bool(getattr(sub, "auto_renewing", False))

    # premium si NO ha vencido y el estado permite acceso
    is_premium = bool(
        period_active and status_str in ("active", "canceled", "grace", "on_hold", "paused")
    )

    return SubscriptionStatus(
        user_id=int(user_id),
        entitlement="pro",
        is_premium=is_premium,
        expires_at=end_at_utc.isoformat() if end_at_utc else None,
        status=status_str,
        reason=None,
        since=start_at_utc.isoformat() if start_at_utc else None,
        auto_renewing=auto_renewing,
    )


def cancel(user_id: int) -> Dict[str, Any]:
    """
    Cancela la suscripción del usuario (idempotente).
    - NO apaga is_active inmediatamente; el usuario conserva PRO hasta current_period_end.
    """
    sub: Optional[UserSubscription] = (
        UserSubscription.query
        .filter_by(user_id=int(user_id), entitlement="pro")
        .first()
    )

    if not sub:
        return {"ok": True, "already": True}

    # Si ya está cancelada, no hacemos nada.
    if getattr(sub, "status", None) == "canceled":
        return {"ok": True, "already": True}

    # Marca cancelado pero respeta el periodo vigente
    sub.status = "canceled"
    # Refleja que no se renovará automáticamente (si existe la columna)
    if hasattr(sub, "auto_renewing"):
        sub.auto_renewing = False

    db.session.add(sub)
    db.session.commit()
    return {"ok": True}


def sync_purchase(
    user_id: int,
    product_id: str,
    purchase_id: str,
    verification_data: str,  # purchaseToken / serverVerificationData
    package_name: str | None = None, 
) -> Dict[str, Any]:
    """
    Valida/acepta la compra y activa/renueva la suscripción PRO.

    TODO producción: verificar con Google Play Developer API (Subscriptions v2)
    y usar los tiempos reales devueltos por Google.
    Por ahora (DEV): calculamos un periodo DEMO de 30 días.
    """
    now = _now_utc()

    sub: Optional[UserSubscription] = (
        UserSubscription.query
        .filter_by(user_id=int(user_id), entitlement="pro")
        .first()
    )
    if not sub:
        sub = UserSubscription(user_id=int(user_id), entitlement="pro")

    # === VALIDACIÓN REAL CON GOOGLE (sustituye el bloque DEMO) ===
    package_name = package_name or os.environ.get('GOOGLE_PLAY_PACKAGE_NAME', 'com.tu.paquete')
    purchase_token = (verification_data or '').strip()
    if purchase_token.startswith('gp:'):
        purchase_token = purchase_token[3:]


    _log_event("subs_sync_start", user_id=user_id, product_id=product_id)
    # cliente Android Publisher con el service account (lee GOOGLE_CREDENTIALS_JSON)
    service = build_android_publisher()

    # Suscripciones modernas: SubscriptionsV2
    try:
        gp = service.purchases().subscriptionsv2().get(
            packageName=package_name,
            token=purchase_token,
        ).execute()
    except HttpError as e:
        try:
            content = e.content.decode('utf-8', 'ignore') if hasattr(e, 'content') else str(e)
        except Exception:
            content = str(e)
        _log_event("subs_sync_http_error", user_id=user_id, status=getattr(e, "status_code", None), content=content)
        SUBS_SYNC_ERR.inc()
        raise Exception(f'Google Play API error: {getattr(e, "status_code", "HTTP")} {content}')


    # Extrae datos clave
    line_items = gp.get('lineItems', [])
    if not line_items:
        _log_event("subs_sync_bad_response", user_id=user_id, reason="no_lineItems")
        SUBS_SYNC_ERR.inc()
        raise Exception('Google Play: respuesta sin lineItems')

    li = _pick_line_item(line_items)

    # Intenta tomar el inicio de línea desde Google (v2 puede venir en ms o RFC3339)
    start_raw = li.get('startTime') or li.get('startTimeMillis') or gp.get('startTime')
    period_start = _parse_gp_time(start_raw)
    if not period_start:
        prev_end = _to_aware_utc(getattr(sub, "current_period_end", None))
        period_start = prev_end if (prev_end and prev_end > now) else now

    # Expiración (ms o RFC3339)
    expiry_raw = li.get('expiryTime') or (gp.get('latestOrder') or {}).get('expiryTime')
    expiry_dt = _parse_gp_time(expiry_raw)
    if not expiry_dt:
        _log_event("subs_sync_bad_response", user_id=user_id, reason="no_expiryTime_valid", raw=expiry_raw)
        SUBS_SYNC_ERR.inc()
        raise Exception('Google Play: sin expiryTime válido en la respuesta')


    # ---- Estado + autorrenovación (V2): autoRenewing viene en el line item ----
    state_raw = (gp.get('subscriptionState') or '').upper()
    auto_ren = li.get('autoRenewing')  # True/False/None

    status_str, is_active_flag = _decide_status(state_raw, auto_ren, expiry_dt)

    # actualiza
    sub.status = status_str
    sub.is_active = is_active_flag
    sub.current_period_start = period_start
    sub.current_period_end = expiry_dt
    sub.auto_renewing = bool(auto_ren) if auto_ren is not None else False

        # === Extraer precio/ids del line item (necesario SIEMPRE) ===
    price = (li.get('price') or {})
    price_micros = int(price.get('priceMicros') or 0)
    currency      = price.get('currency') or "COP"
    product_id_gp = li.get('productId') or (gp.get('latestOrder') or {}).get('productId') or ""
    order_id      = gp.get('latestOrderId') or (gp.get('latestOrder') or {}).get('orderId')
    event_time_raw = li.get('startTime') or li.get('startTimeMillis') or gp.get('startTime')
    event_time_dt  = _parse_gp_time(event_time_raw)

      # === FORZAR PRECIO EN SANDBOX/DEV PARA PRUEBAS ===
    env = (os.getenv('ENV', '') or '').lower()
    if env in ('dev', 'sandbox', 'staging'):
        PRICE_BY_PRODUCT = {
            "cm_suscripcion": 10_000_000,  # 10.000 COP → micros
        }
        pid_for_map = (product_id_gp or product_id or "").strip()
        forced = 0
        if pid_for_map in PRICE_BY_PRODUCT:
            forced = PRICE_BY_PRODUCT[pid_for_map]
        else:
            for k, v in PRICE_BY_PRODUCT.items():
                if pid_for_map.startswith(k):
                    forced = v
                    break
        if forced > 0:
            price_micros = forced
            currency = "COP"
            _log_event("sandbox_forced_price",
                       product_id=pid_for_map, price_micros=price_micros, env=env)

    # -----------------------------------------------

    # Acredita comisión SOLO si hay usuario válido y el periodo está vigente
    if user_id and expiry_dt and expiry_dt > now:
        _credit_referral_if_any(
            purchaser_user_id=int(user_id),
            product_id=product_id_gp,
            purchase_token=purchase_token,
            order_id=order_id,
            price_amount_micros=price_micros,
            price_currency_code=currency,
            event_time=event_time_dt,  # ✅ datetime
        )



    sub.last_purchase_id = purchase_id or getattr(sub, "last_purchase_id", None)
    sub.last_product_id = product_id_gp or product_id or getattr(sub, "last_product_id", None)

    if hasattr(sub, "purchase_token"):
        sub.purchase_token = purchase_token or getattr(sub, "purchase_token", None)

    db.session.add(sub)
    db.session.commit()
    _log_event("subs_sync_ok", user_id=user_id, product_id=product_id, status=status_str, expires_at=expiry_dt.isoformat())

    try:
        from app.services.referrals.payouts_service import mature_commissions
        mature_commissions()
    except Exception as _e:
        _log_event("mature_err", err=str(_e))

    SUBS_SYNC_OK.inc()

    return {
        "ok": True,
        "userId": int(user_id),
        "entitlement": "pro",
        "isPremium": True,
        "status": status_str,
        "expiresAt": expiry_dt.isoformat(),
        "since": period_start.isoformat(),
        "autoRenewing": bool(auto_ren) if auto_ren is not None else False,
    }

def rtdn_handle(purchase_token: str, package_name: str | None = None, notification_type: int | str | None = None) -> Dict[str, Any]:
    """Maneja una notificación en tiempo real (RTDN)."""
    RTDN_RCVD.inc()
    _log_event("rtdn_received", purchase_token=purchase_token, package_name=package_name, notification_type=notification_type)

    # ✅ Si Google avisa REVOKED (12), rechaza comisiones y termina
    try:
        code = int(str(notification_type)) if notification_type is not None else None
    except Exception:
        code = None

    if code == 12:  # REVOKED / Refund
        try:
            from app.services.referrals.payouts_service import reject_commissions_for_token
            rejected = reject_commissions_for_token(purchase_token)
            _log_event("rtdn_refund_rejected", purchase_token=purchase_token, rejected=rejected)
            return {"ok": True, "refund": True, "rejected": rejected}
        except Exception as e:
            RTDN_ERR.inc()
            _log_event("rtdn_refund_err", purchase_token=purchase_token, err=str(e))
            # devolvemos 200 desde routes para que Pub/Sub no reintente infinito
            return {"ok": False, "refund": True, "err": str(e)}

    # 🔁 Para cualquier otro tipo, seguimos con la reconciliación normal
    try:
        result = sync_purchase(
            user_id=0,  # si luego mapeas token->usuario, aquí lo puedes poner
            product_id="",
            purchase_id="",
            verification_data=purchase_token,
            package_name=package_name,
        )
        _log_event("rtdn_processed", purchase_token=purchase_token)
        return result
    except Exception as e:
        RTDN_ERR.inc()
        _log_event("rtdn_handle_err", purchase_token=purchase_token, err=str(e))
        return {"ok": False, "err": str(e)}

def reconcile_subscriptions(batch_size: int = 100, days_ahead: int = 2) -> Dict[str, Any]:
    _log_event("reconcile_start", batch_size=batch_size, days_ahead=days_ahead)
    """
    Recorre suscripciones cercanas a expirar o en estados inestables y las revalida contra Google.
    - Selecciona: status en ('on_hold','grace','active') o expirando en <= days_ahead días.
    - Usa purchase_token para reconsultar SubscriptionsV2 y actualiza la DB.
    Devuelve un pequeño resumen.
    """
    now = _now_utc()
    pkg = os.environ.get('GOOGLE_PLAY_PACKAGE_NAME', '')
    service = build_android_publisher()

    q = (
        UserSubscription.query
        .filter(
            or_(
                UserSubscription.status.in_(('on_hold', 'grace', 'active', 'canceled')),
                UserSubscription.current_period_end <= (now + timedelta(days=days_ahead))
            )
        )
        .order_by(UserSubscription.current_period_end.asc().nullslast())
        .limit(batch_size)
    )


    checked = 0
    updated = 0
    skipped = 0
    errors = 0

    for sub in q.all():
        checked += 1

        token = getattr(sub, "purchase_token", None)
        if not token:
            skipped += 1
            continue

        package_name = pkg or 'com.tu.paquete'  # fallback

        try:
            gp = service.purchases().subscriptionsv2().get(
                packageName=package_name,
                token=token,
            ).execute()

            line_items = gp.get('lineItems', [])
            if not line_items:
                skipped += 1
                continue

            li = _pick_line_item(line_items)

            # start
            start_raw = li.get('startTime') or li.get('startTimeMillis') or gp.get('startTime')
            period_start = _parse_gp_time(start_raw)
            if not period_start:
                prev_end = _to_aware_utc(getattr(sub, "current_period_end", None))
                period_start = prev_end if (prev_end and prev_end > now) else now

            expiry_raw = li.get('expiryTime') or (gp.get('latestOrder') or {}).get('expiryTime')
            expiry_dt = _parse_gp_time(expiry_raw)
            if not expiry_dt:
                skipped += 1
                continue

            # ---- state + autorenovación (V2) ----
            state_raw = (gp.get('subscriptionState') or '').upper()
            auto_ren = li.get('autoRenewing')  # True/False/None

            status_str, is_active_flag = _decide_status(state_raw, auto_ren, expiry_dt)

            # actualiza
            sub.status = status_str
            sub.is_active = is_active_flag
            sub.current_period_start = period_start
            sub.current_period_end = expiry_dt
            sub.auto_renewing = bool(auto_ren) if auto_ren is not None else False

                     # === CREDITO DE COMISIÓN EN RECONCILIACIÓN (PEGAR DEBAJO DE sub.auto_renewing = ...) ===
            price = (li.get('price') or {})
            price_micros = int(price.get('priceMicros') or 0)
            currency      = price.get('currency') or "COP"
            product_id_gp = li.get('productId') or (gp.get('latestOrder') or {}).get('productId') or ""
            order_id      = gp.get('latestOrderId') or (gp.get('latestOrder') or {}).get('orderId')
            event_time_raw = li.get('startTime') or li.get('startTimeMillis') or gp.get('startTime')
            event_time_dt = _parse_gp_time(event_time_raw)
            
                        # --- Fallback de precio SOLO para sandbox/test ---
            is_test = bool(gp.get('testPurchase', False))
            if (is_test or os.getenv('ENV', '').lower() in ('dev', 'sandbox', 'staging')) and price_micros == 0:
                PRICE_BY_PRODUCT = {
                    "cm_suscripcion": 10_000_000,  # 10.000 COP → micros
                }
                price_micros = PRICE_BY_PRODUCT.get(product_id_gp, 0)
                _log_event("reconcile_price_fallback",
                        user_id=sub.user_id, product_id=product_id_gp,
                        price_micros=price_micros, reason="sandbox_price_zero")
            # -----------------------------------------------

            if sub.user_id and expiry_dt and expiry_dt > now:
                _credit_referral_if_any(
                    purchaser_user_id=int(sub.user_id),
                    product_id=product_id_gp,
                    purchase_token=token,
                    order_id=order_id,
                    price_amount_micros=price_micros,
                    price_currency_code=currency,
                    event_time=event_time_dt,  # ✅ datetime
                )



            db.session.add(sub)
            updated += 1
            RECONCILE_UPD.inc()
        except Exception:
            RECONCILE_ERR.inc()
            errors += 1
            continue

    db.session.commit()
    _log_event("reconcile_done", checked=checked, updated=updated, skipped=skipped, errors=errors)
    
    try:
        from app.services.referrals.payouts_service import mature_commissions
        mature_commissions()
    except Exception as _e:
        _log_event("mature_err", err=str(_e))

    return {
        "checked": checked,
        "updated": updated,
        "skipped": skipped,
        "errors": errors,
    }

def backfill_commissions(limit: int = 1000) -> Dict[str, Any]:
    """
    BACKFILL OFFLINE (sin Google):
    Recorre suscripciones existentes y crea comisiones faltantes en referral_commissions.
    Idempotente por (referred_user_id, product_id, purchase_token, order_id).

    Solo paga si el usuario tiene relación en 'referrals' (no basta con registrarse).
    Esto es SOLO para histórico; las compras nuevas se acreditan con datos reales
    desde sync_purchase/reconcile_subscriptions.
    """
    from app.subscriptions.models import UserSubscription

    # ====== PRECIOS PARA BACKFILL ======
    # 10.000 COP => 10_000_000 micros
    DEFAULT_PRICE_MICROS = 10_000_000

    # Tu producto real:
    PRICE_BY_PRODUCT = {
        "cm_suscripcion": 10_000_000,
    }
    # ===================================

    checked = 0
    credited = 0
    skipped = 0
    errors = 0

    q = (
        UserSubscription.query
        .order_by(UserSubscription.id.asc())
        .limit(limit)
    )

    for sub in q.all():
        checked += 1
        try:
            user_id = int(getattr(sub, "user_id", 0) or 0)
            if not user_id:
                skipped += 1
                continue

            product_id = getattr(sub, "last_product_id", None) or ""
            if not product_id:
                skipped += 1
                continue

            # Si tu modelo ya guarda el monto en micros, úsalo; si no, usa el mapa/DEFAULT
            amount_micros = getattr(sub, "amount_micros", None)
            if amount_micros is None:
                amount_micros = PRICE_BY_PRODUCT.get(product_id, DEFAULT_PRICE_MICROS)

            if not isinstance(amount_micros, int) or amount_micros <= 0:
                skipped += 1
                continue

            currency = "COP"
            token = getattr(sub, "purchase_token", None) or f"local-{sub.id}"
            order_id = getattr(sub, "last_purchase_id", None) or f"backfill-{sub.id}"
            event_time = getattr(sub, "current_period_start", None)
            event_time = _to_aware_utc(event_time)

            ok = register_referral_commission(
                referred_user_id=user_id,
                product_id=product_id,
                amount_micros=int(amount_micros),
                currency_code=currency,
                purchase_token=token,
                order_id=order_id,
                source="backfill_local",
                event_time=event_time,
            )
            if ok:
                credited += 1
            else:
                # ya existía o el usuario no tiene referrer
                skipped += 1

        except Exception:
            errors += 1
            continue

    db.session.commit()
    return {
        "processed": checked,
        "credited": credited,
        "skipped": skipped,
        "errors": errors,
    }
