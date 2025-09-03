# app/routes/admin/admin_routes.py
from flask import jsonify
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from . import bp
from app.services.admin.admin_service import get_lottery_dashboard_summary

@bp.get("/dashboard/summary")
@jwt_required()
def dashboard_summary():
    # Tomamos el claim correcto (rid). Si no viene, lo buscamos en DB.
    claims = get_jwt() or {}
    rid = claims.get("rid")

    if rid is None:
        uid = get_jwt_identity()
        role_id_db = db.session.execute(
            text("SELECT role_id FROM users WHERE id = :uid"),
            {"uid": int(uid)}
        ).scalar()
        rid = role_id_db

    # Solo admin (role_id/rid == 1)
    try:
        if int(rid) != 1:
            return jsonify({"ok": False, "error": "Solo administradores"}), 403
    except Exception:
        return jsonify({"ok": False, "error": "Rol inválido"}), 403

    # Entregamos la forma que espera el frontend: { ok: true, data: ... }
    try:
        summary = get_lottery_dashboard_summary()
        return jsonify({"ok": True, "data": summary}), 200
    except Exception as e:
        # (opcional) podrías loggear el error con current_app.logger.exception(...)
        return jsonify({"ok": False, "error": "Fallo en dashboard", "detail": str(e)}), 500
