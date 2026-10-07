# backend/app/routes/auth/auth_routes.py
from flask import Blueprint, request, jsonify, current_app
from datetime import timedelta
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,   # <-- NUEVO
    jwt_required,
    get_jwt_identity,
    get_jwt,                # <-- NUEVO
)
from app.services.auth.auth_service import login_with_phone, AuthError, get_profile
from app.models.user import User
from app.models.token_blocklist import TokenBlocklist
from app.db.database import db
from app.security.guards import (
    client_ip, rate_limited, reset_rate_limit, too_many_requests, get_role_id,
)
import os
import re

# Límites de intentos de login (ajustables por variables de entorno)
_LOGIN_PER_ACCOUNT = int(os.getenv("LOGIN_MAX_PER_ACCOUNT", "8"))      # por celular / 15 min
_LOGIN_PER_IP = int(os.getenv("LOGIN_MAX_PER_IP", "60"))               # por IP / 15 min
_LOGIN_WINDOW = 15 * 60

auth_bp = Blueprint("auth_bp", __name__, url_prefix="/api/auth")

def _to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default

@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    phone = str(data.get("phone") or "").strip()
    password = str(data.get("password") or "")

    if not phone or not password:
        return jsonify({"ok": False, "error": "phone y password son requeridos"}), 400
    if len(phone) > 32 or len(password) > 256:
        return jsonify({"ok": False, "error": "Número de celular o contraseña inválidos"}), 401

    # Frena ataques de fuerza bruta: por cuenta (últimos 10 dígitos) y por IP.
    phone_key = re.sub(r"\D", "", phone)[-10:]
    account_key = f"login:acct:{phone_key}"
    ip_blocked = rate_limited(f"login:ip:{client_ip()}", _LOGIN_PER_IP, _LOGIN_WINDOW)
    if ip_blocked or rate_limited(account_key, _LOGIN_PER_ACCOUNT, _LOGIN_WINDOW):
        return too_many_requests()

    try:
        user = login_with_phone(phone, password)   # user incluye role_id
        reset_rate_limit(account_key)

        # === USA el role_id REAL; si viene None, default 2 (estándar) ===
        raw_rid = user.get("role_id", None)
        rid = 2 if raw_rid is None else int(raw_rid)

        # Access corto (renovable con refresh)
        access_token = create_access_token(
            identity=str(user["id"]),
            additional_claims={"rid": rid},
            expires_delta=timedelta(hours=12),
        )

        # Refresh MUY largo (revocable). Ajusta si quieres menos tiempo.
        refresh_token = create_refresh_token(
            identity=str(user["id"]),
            additional_claims={"rid": rid},
            expires_delta=timedelta(days=3650),  # ~10 años
        )

        return jsonify({
            "ok": True,
            "access_token": access_token,
            "refresh_token": refresh_token,     # <-- NUEVO
            "token_type": "Bearer",
            "user": {
                "id": int(user["id"]),
                "name": user.get("name"),
                "role_id": rid,
                "public_code": getattr(User.query.get(user["id"]), "public_code", None),  # opcional
            }
        }), 200

    except AuthError as e:
        return jsonify({"ok": False, "error": str(e)}), 401
    except Exception:
        current_app.logger.exception("Error inesperado en /api/auth/login")
        return jsonify({"ok": False, "error": "Error interno"}), 500

@auth_bp.post("/refresh")
@jwt_required(refresh=True)
def refresh():
    """
    Intercambia un refresh token válido por un nuevo access token.
    """
    uid_str = get_jwt_identity()
    # El rol se lee de la BD: si a un admin le quitan el rol, su próximo
    # token ya no lo tendrá. Si el usuario fue eliminado, no se renueva.
    rid = get_role_id(_to_int(uid_str, 0))
    if rid is None:
        return jsonify({"ok": False, "error": "Usuario no encontrado"}), 401

    new_access = create_access_token(
        identity=str(uid_str),
        additional_claims={"rid": rid},
        expires_delta=timedelta(hours=12),
    )
    return jsonify({"ok": True, "access_token": new_access, "token_type": "Bearer"}), 200

@auth_bp.post("/logout")
@jwt_required()
def logout_access():
    j = get_jwt() or {}
    jti = j.get("jti")
    uid = get_jwt_identity()

    db.session.add(TokenBlocklist(jti=jti, token_type="access", user_id=int(uid)))
    db.session.commit()

    return jsonify({"ok": True, "revoked": True, "type": "access"}), 200

@auth_bp.post("/logout/refresh")
@jwt_required(refresh=True)
def logout_refresh():
    j = get_jwt() or {}
    jti = j.get("jti")
    uid = get_jwt_identity()

    db.session.add(TokenBlocklist(jti=jti, token_type="refresh", user_id=int(uid)))
    db.session.commit()

    return jsonify({"ok": True, "revoked": True, "type": "refresh"}), 200

@auth_bp.get("/me")
@jwt_required()
def me():
    uid_str = get_jwt_identity()
    try:
        user_id = int(uid_str)
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "Token inválido"}), 401

    profile = get_profile(user_id)
    if not profile:
        return jsonify({"ok": False, "error": "Usuario no encontrado"}), 404

    return jsonify({"ok": True, **profile}), 200
