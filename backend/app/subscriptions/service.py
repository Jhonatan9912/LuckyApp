# app/subscriptions/service.py
from dataclasses import dataclass, asdict
from typing import Optional, Dict, Any
from datetime import datetime, timezone

from app.db.database import db
from app.subscriptions.models import UserSubscription

from datetime import datetime, timezone, timedelta

@dataclass
class SubscriptionStatus:
    user_id: Optional[int]
    entitlement: str
    is_premium: bool
    expires_at: Optional[str]
    status: str
    reason: Optional[str] = None

    def to_json(self) -> Dict[str, Any]:
        # Mantén camelCase para no romper el cliente Flutter
        return {
            "userId": self.user_id,
            "entitlement": self.entitlement,
            "isPremium": self.is_premium,
            "expiresAt": self.expires_at,
            "status": self.status,
            "reason": self.reason,
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
    - Si no hay user_id: no autenticado.
    - is_premium = True cuando:
        * sub.is_active == True, o
        * sub.status == "canceled" pero la fecha de fin (current_period_end) > ahora.
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

    # Normaliza fecha de fin y calcula si el periodo sigue activo
    end_at_utc = _to_aware_utc(getattr(sub, "current_period_end", None))
    now = _now_utc()
    period_active = bool(end_at_utc and end_at_utc > now)

    # Reglas de premium:
    # - activo normal
    # - cancelado pero aún dentro del periodo pagado
    status_str = getattr(sub, "status", "none") or "none"
    is_active_flag = bool(getattr(sub, "is_active", False))
    is_premium = bool(
        is_active_flag
        or status_str == "active"
        or (status_str == "canceled" and period_active)
    )


    expires_iso = end_at_utc.isoformat() if end_at_utc else None

    return SubscriptionStatus(
        user_id=int(user_id),
        entitlement="pro",
        is_premium=is_premium,
        expires_at=expires_iso,
        status=status_str,
        reason=None,
    )


def cancel(user_id: int) -> Dict[str, Any]:
    """
    Cancela la suscripción del usuario (idempotente).
    - NO apaga is_active inmediatamente; el usuario conserva PRO hasta current_period_end.
    - Si ya está cancelada o no existe, responde ok=True igualmente.
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
    # Importante: NO tocar sub.is_active aquí.
    # Si quisieras cortar de inmediato, entonces sí pondrías is_active=False
    # o moverías current_period_end = now.

    db.session.add(sub)
    db.session.commit()
    return {"ok": True}

def sync_purchase(
    user_id: int,
    product_id: str,
    purchase_id: str,
    verification_data: str,
) -> Dict[str, Any]:
    """
    Valida/acepta la compra y activa/renueva la suscripción PRO.
    TODO: aquí deberías verificar con la Play Developer API y usar su expiry real.
    Por ahora, para DEV, damos 30 días desde ahora.
    """
    now = _now_utc()
    expiry_dt = now + timedelta(days=30)  # DEMO: reemplaza con expiry real

    sub: Optional[UserSubscription] = (
        UserSubscription.query
        .filter_by(user_id=int(user_id), entitlement="pro")
        .first()
    )
    if not sub:
        sub = UserSubscription(user_id=int(user_id), entitlement="pro")

    sub.status = "active"
    sub.is_active = True
    sub.current_period_end = expiry_dt
    sub.last_purchase_id = purchase_id or getattr(sub, "last_purchase_id", None)
    sub.last_product_id  = product_id  or getattr(sub, "last_product_id", None)

    db.session.add(sub)
    db.session.commit()

    return {
        "ok": True,
        "userId": int(user_id),
        "entitlement": "pro",
        "isPremium": True,
        "status": "active",
        "expiresAt": expiry_dt.isoformat(),
    }