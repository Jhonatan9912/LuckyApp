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
    claims = get_jwt() or {}
    role_id = claims.get("role_id")
    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(text("SELECT role_id FROM users WHERE id=:uid"), {"uid": uid}).scalar()
    if role_id != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    return jsonify(get_lottery_dashboard_summary())
