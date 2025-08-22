# backend/app/routes/auth/auth_routes.py
from flask import Blueprint, request, jsonify, current_app
from datetime import timedelta
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity
from app.services.auth.auth_service import login_with_phone, AuthError, get_profile
from app.models.user import User

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

        access_token = create_access_token(
            identity=str(user["id"]),
            additional_claims={"rid": rid},   # <- IMPORTANTÍSIMO
            expires_delta=timedelta(hours=12),
        )

        return jsonify({
            "ok": True,
            "access_token": access_token,
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
