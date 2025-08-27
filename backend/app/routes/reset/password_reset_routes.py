# backend/app/routes/reset/password_reset_routes.py
from flask import Blueprint, request, jsonify, current_app
from re import compile as re_compile

from app.services.reset.reset_service import (
    request_password_reset_by_email,
    verify_reset_code_by_email,
    set_new_password_by_token,
    ResetError,
)

EMAIL_RE = re_compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

# ========= Blueprint original (/api/reset/...) =========
password_reset_bp = Blueprint("password_reset_bp", __name__, url_prefix="/api/reset")

@password_reset_bp.post("/request")
def reset_request():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()

    if not email or not EMAIL_RE.match(email):
        return jsonify({"error": "Correo inválido"}), 400

    try:
        request_password_reset_by_email(email)
    except ResetError:
        # No revelar si existe o no el correo
        current_app.logger.info("Solicitud reset para email no encontrado: %s", email)
    except Exception:
        current_app.logger.exception("Error en /api/reset/request")
        # Respuesta neutra (evita enumeración de correos)
        return jsonify({"message": "Si el correo está registrado, recibirás un código."}), 200

    return jsonify({"message": "Si el correo está registrado, recibirás un código."}), 200


@password_reset_bp.post("/verify")
def reset_verify():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    code = (data.get("code") or "").strip()

    if not email or not code:
        return jsonify({"error": "Correo y código son requeridos"}), 400

    try:
        reset_token = verify_reset_code_by_email(email, code)
        # Mantiene snake_case en el blueprint original
        return jsonify({"reset_token": reset_token}), 200
    except ResetError as e:
        return jsonify({"error": str(e)}), 400
    except Exception:
        current_app.logger.exception("Error en /api/reset/verify")
        return jsonify({"error": "Error interno"}), 500


@password_reset_bp.post("/confirm")
def reset_confirm():
    data = request.get_json(silent=True) or {}
    # Acepta ambos formatos por conveniencia
    reset_token = (data.get("reset_token") or data.get("resetToken") or "").strip()
    new_password = (data.get("new_password") or data.get("newPassword") or "")

    if not reset_token or not new_password:
        return jsonify({"error": "Token y nueva contraseña requeridos"}), 400
    if len(new_password) < 6:
        return jsonify({"error": "La contraseña debe tener mínimo 6 caracteres"}), 400

    try:
        set_new_password_by_token(reset_token, new_password)
        return jsonify({"message": "Contraseña actualizada correctamente"}), 200
    except ResetError as e:
        return jsonify({"error": str(e)}), 400
    except Exception:
        current_app.logger.exception("Error en /api/reset/confirm")
        return jsonify({"error": "Error interno"}), 500


# ========= Blueprint alias para compatibilidad con Flutter (/api/auth/...) =========
auth_reset_alias_bp = Blueprint("auth_reset_alias_bp", __name__, url_prefix="/api/auth")

# Flutter espera: POST /api/auth/reset/email
@auth_reset_alias_bp.post("/reset/email")
def alias_request_reset_by_email():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()

    if not email or not EMAIL_RE.match(email):
        return jsonify({"error": "Correo inválido"}), 400

    try:
        request_password_reset_by_email(email)
    except ResetError:
        # No revelar si existe o no el correo
        current_app.logger.info("Solicitud reset (alias) para email no encontrado: %s", email)
    except Exception:
        current_app.logger.exception("Error en alias /api/auth/reset/email")
        return jsonify({"message": "Si el correo está registrado, recibirás un código."}), 200

    # Muchos clientes esperan 202 aquí; puedes dejar 200 si prefieres
    return jsonify({"message": "Código enviado"}), 202


# Flutter espera: POST /api/auth/reset/email/verify  -> devuelve { resetToken: "..." }
@auth_reset_alias_bp.post("/reset/email/verify")
def alias_verify_reset_code():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    code  = (data.get("code") or "").strip()

    if not email or not code:
        return jsonify({"error": "Correo y código son requeridos"}), 400

    try:
        token = verify_reset_code_by_email(email, code)
        # Devuelve camelCase porque así lo lee Flutter
        return jsonify({"resetToken": token}), 200
    except ResetError as e:
        return jsonify({"error": str(e)}), 400
    except Exception:
        current_app.logger.exception("Error en alias /api/auth/reset/email/verify")
        return jsonify({"error": "Error interno"}), 500


# (Opcional) Flutter/Nueva contraseña: POST /api/auth/reset/confirm
@auth_reset_alias_bp.post("/reset/confirm")
def alias_reset_confirm():
    data = request.get_json(silent=True) or {}

    # En alias preferimos camelCase, pero aceptamos ambos
    reset_token = (data.get("resetToken") or data.get("reset_token") or "").strip()
    new_password = (data.get("newPassword") or data.get("new_password") or "")

    if not reset_token or not new_password:
        return jsonify({"error": "Token y nueva contraseña requeridos"}), 400
    if len(new_password) < 6:
        return jsonify({"error": "La contraseña debe tener mínimo 6 caracteres"}), 400

    try:
        set_new_password_by_token(reset_token, new_password)
        return jsonify({"message": "Contraseña actualizada correctamente"}), 200
    except ResetError as e:
        return jsonify({"error": str(e)}), 400
    except Exception:
        current_app.logger.exception("Error en alias /api/auth/reset/confirm")
        return jsonify({"error": "Error interno"}), 500
