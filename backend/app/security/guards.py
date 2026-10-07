# app/security/guards.py
#
# Utilidades de seguridad compartidas por todas las rutas:
# - Identidad del usuario SOLO desde un JWT válido (firma, expiración y
#   lista de revocados verificados por flask_jwt_extended).
# - Rol leído siempre desde la base de datos (un admin degradado pierde
#   el acceso de inmediato, aunque su token diga lo contrario).
# - Limitador de intentos persistente en Postgres (sirve con varios workers).
from __future__ import annotations

import logging
from functools import wraps

from flask import jsonify, request
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request
from sqlalchemy import text

from app.db.database import db

log = logging.getLogger("security")

ADMIN_ROLE_ID = 1


# ───────────────────────── Identidad ─────────────────────────

def current_user_id(optional: bool = False) -> int | None:
    """Id del usuario autenticado por JWT de acceso, o None."""
    try:
        verify_jwt_in_request(optional=optional)
    except Exception:
        return None
    ident = get_jwt_identity()
    if isinstance(ident, dict):
        ident = ident.get("id")
    try:
        return int(ident) if ident is not None else None
    except (TypeError, ValueError):
        return None


def get_role_id(user_id: int | None) -> int | None:
    if not user_id:
        return None
    try:
        rid = db.session.execute(
            text("SELECT role_id FROM users WHERE id = :uid"), {"uid": int(user_id)}
        ).scalar()
        return int(rid) if rid is not None else None
    except Exception:
        log.exception("get_role_id failed")
        db.session.rollback()
        return None


def is_admin(user_id: int | None) -> bool:
    return get_role_id(user_id) == ADMIN_ROLE_ID


def _unauthorized():
    return jsonify({"ok": False, "code": "UNAUTHORIZED", "error": "No autorizado"}), 401


def _forbidden():
    return jsonify({"ok": False, "code": "FORBIDDEN", "error": "Solo administradores"}), 403


def check_admin():
    """Devuelve una respuesta de error si el usuario no es admin; None si lo es."""
    uid = current_user_id()
    if uid is None:
        return _unauthorized()
    if not is_admin(uid):
        log.warning("admin_denied uid=%s path=%s", uid, request.path)
        return _forbidden()
    return None


def admin_required(fn):
    """Decorador: exige JWT válido de un usuario con rol administrador."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        resp = check_admin()
        if resp is not None:
            return resp
        return fn(*args, **kwargs)
    return wrapper


def protect_blueprint_admin(bp):
    """Exige rol admin en TODAS las rutas del blueprint (excepto preflight CORS)."""
    @bp.before_request
    def _admin_guard():
        if request.method == "OPTIONS":
            return None
        return check_admin()


# ───────────────────────── Limitador de intentos ─────────────────────────

_RATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS security_rate_limits (
    key          TEXT PRIMARY KEY,
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hits         INTEGER NOT NULL DEFAULT 0
)
"""

_EPOCH_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS security_token_epochs (
    user_id    INTEGER PRIMARY KEY,
    not_before TIMESTAMPTZ NOT NULL
)
"""


def ensure_security_tables(app) -> None:
    with app.app_context():
        try:
            with db.engine.begin() as conn:
                conn.execute(text(_RATE_TABLE_SQL))
                conn.execute(text(_EPOCH_TABLE_SQL))
        except Exception:
            app.logger.exception("ensure_security_tables failed")


def client_ip() -> str:
    # ProxyFix (ver create_app) deja en remote_addr la IP real del cliente.
    return request.remote_addr or "unknown"


def rate_limited(key: str, limit: int, window_seconds: int) -> bool:
    """
    Registra un intento para `key` y devuelve True si superó `limit`
    dentro de la ventana. Si la BD falla, no bloquea (fail-open) pero lo registra.
    """
    sql = text("""
        INSERT INTO security_rate_limits AS r (key, window_start, hits)
        VALUES (:k, NOW(), 1)
        ON CONFLICT (key) DO UPDATE SET
            hits = CASE WHEN r.window_start < NOW() - make_interval(secs => :w)
                        THEN 1 ELSE r.hits + 1 END,
            window_start = CASE WHEN r.window_start < NOW() - make_interval(secs => :w)
                        THEN NOW() ELSE r.window_start END
        RETURNING hits
    """)
    try:
        with db.engine.begin() as conn:
            hits = conn.execute(sql, {"k": key[:200], "w": int(window_seconds)}).scalar()
        if hits and int(hits) > limit:
            log.warning("rate_limited key=%s hits=%s", key, hits)
            return True
        return False
    except Exception:
        log.exception("rate_limited check failed")
        return False


def reset_rate_limit(key: str) -> None:
    try:
        with db.engine.begin() as conn:
            conn.execute(text("DELETE FROM security_rate_limits WHERE key = :k"), {"k": key[:200]})
    except Exception:
        log.exception("reset_rate_limit failed")


def too_many_requests():
    return jsonify({
        "ok": False,
        "code": "TOO_MANY_REQUESTS",
        "error": "Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
        "message": "Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
    }), 429


# ───────────────────────── Revocación global de sesiones ─────────────────────────

def revoke_all_sessions(user_id: int) -> None:
    """Invalida todos los tokens emitidos antes de ahora para el usuario."""
    with db.engine.begin() as conn:
        conn.execute(text("""
            INSERT INTO security_token_epochs (user_id, not_before)
            VALUES (:uid, NOW())
            ON CONFLICT (user_id) DO UPDATE SET not_before = NOW()
        """), {"uid": int(user_id)})


def token_issued_before_epoch(user_id, iat) -> bool:
    try:
        uid = int(user_id)
        iat = int(iat)
    except (TypeError, ValueError):
        return False
    try:
        nb = db.session.execute(
            text("SELECT EXTRACT(EPOCH FROM not_before) FROM security_token_epochs WHERE user_id = :uid"),
            {"uid": uid},
        ).scalar()
    except Exception:
        db.session.rollback()
        return False
    # iat tiene resolución de segundos: un token emitido en el mismo segundo
    # que el reset se considera revocado también.
    return nb is not None and iat <= int(float(nb))
