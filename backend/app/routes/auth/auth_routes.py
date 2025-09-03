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

auth_bp = Blueprint("auth_bp", __name__, url_prefix="/api/auth")

def _to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default

@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    phone = (data.get("phone") or "").strip()
    password = data.get("password") or ""

    if not phone or not password:
        return jsonify({"ok": False, "error": "phone y password son requeridos"}), 400

    try:
        user = login_with_phone(phone, password)   # user incluye role_id

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
    claims = get_jwt() or {}
    rid = _to_int(claims.get("rid"), 2)

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
