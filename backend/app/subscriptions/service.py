# app/subscriptions/service.py
from dataclasses import dataclass
from typing import Optional, Dict, Any
from datetime import datetime, timezone

from app.db.database import db
from app.subscriptions.models import UserSubscription
from app.subscriptions.google_play_client import build_android_publisher
import os
from googleapiclient.errors import HttpError
from sqlalchemy import or_


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
    is_active_flag = bool(getattr(sub, "is_active", False))
    auto_renewing = bool(getattr(sub, "auto_renewing", False))

    is_premium = bool(
        is_active_flag
        or status_str == "active"
        or (status_str == "canceled" and period_active)
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
    purchase_token = verification_data  # viene de tu app (serverVerificationData)

    # cliente Android Publisher con el service account (lee GOOGLE_CREDENTIALS_JSON)
    service = build_android_publisher()

    # Suscripciones modernas: SubscriptionsV2
    try:
        gp = service.purchases().subscriptionsv2().get(
            packageName=package_name,
            token=purchase_token,
        ).execute()
    except HttpError as e:
        raise Exception(f'Google Play API error: {getattr(e, "status_code", "HTTP")} {e}')


    # Extrae datos clave
    line_items = gp.get('lineItems', [])
    if not line_items:
        raise Exception('Google Play: respuesta sin lineItems')

    li = line_items[0]

    # Intenta tomar el inicio de línea desde Google (si viene)
    start_ms = (li.get('startTime')                  # v2 actual
                or li.get('startTimeMillis')         # variantes raras
                or gp.get('startTime'))              # fallback
    if start_ms:
        period_start = datetime.fromtimestamp(int(start_ms) / 1000.0, tz=timezone.utc)
    else:
        # Fallback: tu lógica previa
        prev_end = _to_aware_utc(getattr(sub, "current_period_end", None))
        period_start = prev_end if (prev_end and prev_end > now) else now

    # expiryTime viene en milisegundos desde epoch
    expiry_ms = li.get('expiryTime') or gp.get('latestOrder', {}).get('expiryTime')
    if not expiry_ms:
        raise Exception('Google Play: sin expiryTime en la respuesta')

    expiry_dt = datetime.fromtimestamp(int(expiry_ms) / 1000.0, tz=timezone.utc)

    # Estado y autorrenovación (Subscriptions v2)
    state_raw = (gp.get('subscriptionState') or '').upper()  # ACTIVE, CANCELED, IN_GRACE_PERIOD, ON_HOLD, PAUSED, EXPIRED
    auto_ren = bool(gp.get('autoRenewing', False))

    MAP = {
        'ACTIVE': 'active',
        'CANCELED': 'canceled',
        'IN_GRACE_PERIOD': 'grace',
        'ON_HOLD': 'on_hold',
        'PAUSED': 'paused',
        'EXPIRED': 'expired',
    }
    status_str = MAP.get(state_raw, 'active')


    sub.status = status_str
    sub.is_active = (status_str == 'active') or (status_str == 'canceled' and expiry_dt > now)
    sub.current_period_start = period_start
    sub.current_period_end = expiry_dt
    sub.auto_renewing = auto_ren


    sub.last_purchase_id = purchase_id or getattr(sub, "last_purchase_id", None)
    sub.last_product_id = product_id or getattr(sub, "last_product_id", None)

    # Guarda el token/recibo de Google para validaciones posteriores
    # Requiere columna purchase_token en el modelo
    if hasattr(sub, "purchase_token"):
        sub.purchase_token = verification_data or getattr(sub, "purchase_token", None)

    db.session.add(sub)
    db.session.commit()

    return {
        "ok": True,
        "userId": int(user_id),
        "entitlement": "pro",
        "isPremium": True,
        "status": status_str,
        "expiresAt": expiry_dt.isoformat(),
        "since": period_start.isoformat(),
        "autoRenewing": auto_ren,
    }

def rtdn_handle(purchase_token: str, package_name: str | None = None) -> Dict[str, Any]:
    """
    Maneja una notificación en tiempo real (RTDN).
    - Consulta a Google Play con el purchaseToken recibido.
    - Actualiza el estado en la DB.
    - Devuelve el mismo dict que sync_purchase().
    """
    return sync_purchase(
        user_id=0,  # aquí no siempre sabrás el user_id, lo puedes buscar luego en tu DB si lo necesitas
        product_id="",
        purchase_id="",
        verification_data=purchase_token,
        package_name=package_name
    )

def reconcile_subscriptions(batch_size: int = 100, days_ahead: int = 2) -> Dict[str, Any]:
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
                UserSubscription.status.in_(('on_hold', 'grace', 'active')),
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

            li = line_items[0]

            # start
            start_ms = (li.get('startTime') or li.get('startTimeMillis') or gp.get('startTime'))
            if start_ms:
                period_start = datetime.fromtimestamp(int(start_ms) / 1000.0, tz=timezone.utc)
            else:
                prev_end = _to_aware_utc(getattr(sub, "current_period_end", None))
                period_start = prev_end if (prev_end and prev_end > now) else now

            # end (expiry)
            expiry_ms = li.get('expiryTime') or gp.get('latestOrder', {}).get('expiryTime')
            if not expiry_ms:
                skipped += 1
                continue
            expiry_dt = datetime.fromtimestamp(int(expiry_ms) / 1000.0, tz=timezone.utc)

            # state + autorenovación
            state_raw = (gp.get('subscriptionState') or '').upper()
            auto_ren = bool(gp.get('autoRenewing', False))
            MAP = {
                'ACTIVE': 'active',
                'CANCELED': 'canceled',
                'IN_GRACE_PERIOD': 'grace',
                'ON_HOLD': 'on_hold',
                'PAUSED': 'paused',
                'EXPIRED': 'expired',
            }
            status_str = MAP.get(state_raw, 'active')

            # actualiza
            sub.status = status_str
            sub.is_active = (status_str == 'active') or (status_str == 'canceled' and expiry_dt > now)
            sub.current_period_start = period_start
            sub.current_period_end = expiry_dt
            sub.auto_renewing = auto_ren

            db.session.add(sub)
            updated += 1

        except Exception:
            errors += 1
            continue

    db.session.commit()
    return {
        "checked": checked,
        "updated": updated,
        "skipped": skipped,
        "errors": errors,
    }
