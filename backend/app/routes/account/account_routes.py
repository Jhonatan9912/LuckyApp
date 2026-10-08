# backend/app/routes/account/account_routes.py
#
# Endpoints de la cuenta propia (Habeas Data): eliminación de cuenta y datos.
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.services.account.account_service import (
    AccountDeletionBlocked,
    AccountDeletionError,
    delete_account,
)

account_bp = Blueprint("account_bp", __name__, url_prefix="/api/me")


@account_bp.delete("/account")
@jwt_required()
def delete_my_account():
    """Elimina (anonimiza) la cuenta del usuario autenticado.

    Body JSON: { "password": "<contraseña actual>" }
    """
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401

    data = request.get_json(silent=True) or {}
    password = str(data.get("password") or "")

    try:
        result = delete_account(int(user_id), password)
        return jsonify(result), 200
    except AccountDeletionBlocked as e:
        # 409: el usuario debe resolver algo antes (contraseña, pagos, suscripción)
        status = 401 if e.code == "BAD_PASSWORD" else 409
        return jsonify({"ok": False, "code": e.code, "error": e.message, "message": e.message}), status
    except AccountDeletionError as e:
        return jsonify({"ok": False, "code": "NOT_FOUND", "error": str(e)}), 404
    except Exception:
        from flask import current_app
        current_app.logger.exception("delete_my_account failed")
        return jsonify({"ok": False, "code": "INTERNAL", "error": "Error interno"}), 500
