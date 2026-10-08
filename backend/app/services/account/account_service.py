# backend/app/services/account/account_service.py
#
# Eliminación de cuenta / supresión de datos personales (Habeas Data, Ley 1581/2012).
#
# Política aplicada (coincide con assets/legal/data_policy_es.md):
#   - Se ANONIMIZAN los datos personales del usuario (nombre, documento,
#     teléfono, correo, fecha de nacimiento) y se cierra el acceso.
#   - Se CONSERVAN, ya anonimizados, los registros de pagos y comisiones por
#     el deber legal de conservación fiscal (hasta 10 años).
#   - Se BLOQUEA el borrado si hay comisiones pendientes por cobrar o una
#     suscripción de pago activa (el usuario debe resolverlas primero).
from __future__ import annotations

import logging
from datetime import datetime

from sqlalchemy import text
from werkzeug.security import check_password_hash, generate_password_hash

from app.db.database import db
from app.models.user import User
from app.security.guards import revoke_all_sessions

log = logging.getLogger("account")


class AccountDeletionError(Exception):
    """Error genérico de borrado de cuenta."""


class AccountDeletionBlocked(AccountDeletionError):
    """El borrado no puede continuar por obligaciones pendientes."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def ensure_account_schema(app) -> None:
    """Agrega la columna deleted_at si falta (mismo patrón que las demás tablas)."""
    with app.app_context():
        try:
            with db.engine.begin() as conn:
                conn.execute(text(
                    "ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ"
                ))
        except Exception:
            app.logger.exception("ensure_account_schema failed")


def _has_pending_commissions(user_id: int) -> bool:
    """True si el usuario tiene comisiones cobrables o pendientes de liquidar."""
    try:
        row = db.session.execute(text("""
            SELECT 1
              FROM public.referral_commissions rc
             WHERE rc.referrer_user_id = :uid
               AND rc.status IN ('available', 'pending')
             LIMIT 1
        """), {"uid": int(user_id)}).first()
        return row is not None
    except Exception:
        # Ante un fallo de consulta, NO bloqueamos el derecho de supresión,
        # pero lo registramos para revisarlo.
        log.exception("pending-commissions check failed uid=%s", user_id)
        db.session.rollback()
        return False


def _has_active_paid_subscription(user_id: int) -> bool:
    """True solo si hay una suscripción de PAGO activa (no una prueba gratuita)."""
    try:
        from app.subscriptions.service import get_status
        st = get_status(user_id)
        return bool(getattr(st, "is_premium", False) and not getattr(st, "is_trial", False))
    except Exception:
        log.exception("subscription check failed uid=%s", user_id)
        db.session.rollback()
        return False


def delete_account(user_id: int, password: str) -> dict:
    """
    Elimina (anonimiza) la cuenta del usuario autenticado.

    Requiere la contraseña actual como confirmación. Lanza
    AccountDeletionBlocked si hay obligaciones pendientes.
    """
    user: User | None = db.session.get(User, int(user_id))
    if user is None or getattr(user, "deleted_at", None) is not None:
        raise AccountDeletionError("Cuenta no encontrada")

    # 1) Confirmación por contraseña (evita borrados accidentales o por sesión robada)
    if not password or not check_password_hash(user.password_hash, password):
        raise AccountDeletionBlocked("BAD_PASSWORD", "La contraseña no es correcta.")

    # 2) Bloqueos por obligaciones pendientes
    if _has_pending_commissions(user_id):
        raise AccountDeletionBlocked(
            "PENDING_COMMISSIONS",
            "Tienes comisiones pendientes por cobrar. Cóbralas o espera a que se "
            "resuelvan antes de eliminar tu cuenta.",
        )
    if _has_active_paid_subscription(user_id):
        raise AccountDeletionBlocked(
            "ACTIVE_SUBSCRIPTION",
            "Tienes una suscripción de pago activa. Cancélala desde Google Play "
            "antes de eliminar tu cuenta.",
        )

    # 3) Anonimización de datos personales. Los campos son UNIQUE/NOT NULL, así
    #    que se reemplazan por marcadores únicos que no identifican a nadie.
    uid = int(user_id)
    marker = f"DEL-{uid}"
    user.name = "Usuario eliminado"
    user.identification_number = marker[:20]
    user.phone = marker[:20]
    user.email = f"deleted+{uid}@deleted.invalid"[:255]
    user.public_code = f"DEL{uid}"[:20]
    user.birthdate = datetime(1900, 1, 1).date()
    user.country_code = None
    # Contraseña inservible: hash aleatorio imposible de adivinar o reutilizar.
    user.password_hash = generate_password_hash(f"deleted::{uid}::{datetime.utcnow().timestamp()}")
    user.deleted_at = datetime.utcnow()

    # 4) Limpieza de datos técnicos vinculados (no fiscales)
    try:
        db.session.execute(text("DELETE FROM device_tokens WHERE user_id = :uid"), {"uid": uid})
    except Exception:
        log.exception("device_tokens cleanup failed uid=%s", uid)
    try:
        db.session.execute(text("DELETE FROM reset_tokens WHERE user_id = :uid"), {"uid": uid})
    except Exception:
        log.exception("reset_tokens cleanup failed uid=%s", uid)

    db.session.commit()

    # 5) Cierra TODAS las sesiones del usuario (su token deja de servir)
    try:
        revoke_all_sessions(uid)
    except Exception:
        log.exception("revoke_all_sessions failed uid=%s", uid)

    log.info("account_deleted uid=%s", uid)
    return {"ok": True, "message": "Tu cuenta y tus datos personales fueron eliminados."}
