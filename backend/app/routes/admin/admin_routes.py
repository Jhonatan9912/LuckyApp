# app/routes/admin/admin_routes.py
from flask import jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from . import bp
from app.services.admin.admin_service import get_lottery_dashboard_summary

@bp.get("/dashboard/summary")
@jwt_required()
def dashboard_summary():
    # 1) Resolver rol del admin
    try:
        claims = get_jwt() or {}
        role_id = claims.get("role_id")  # ← usa la clave original del token
        if role_id is None:
            uid = int(get_jwt_identity())
            role_id = db.session.execute(
                text("SELECT role_id FROM users WHERE id = :uid"),
                {"uid": uid}
            ).scalar()
        if int(role_id) != 1:
            return jsonify({"ok": False, "error": "Solo administradores"}), 403
    except Exception as e:
        current_app.logger.exception("dashboard_summary: role check failed")
        return jsonify({"ok": False, "error": "Rol inválido"}), 403

    # 2) Devolver el MISMO shape que antes (sin envolver en ok/data)
    try:
        summary = get_lottery_dashboard_summary()
        if isinstance(summary, tuple):
            summary = summary[0]
        # Asegura dict
        if not isinstance(summary, dict):
            summary = {"value": summary}
        return jsonify(summary), 200
    except Exception:
        current_app.logger.exception("dashboard_summary: service error")
        return jsonify({"ok": False, "error": "Fallo en dashboard_summary"}), 500
