# app/routes/admin/referrals_routes.py
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db

from . import bp  # blueprint del paquete admin
from app.services.admin.referrals_service import get_referrals_summary


# ---------------------------------------------------------------------
# GET /api/admin/referrals/summary  -> resumen global (o por referrer_id)
# ---------------------------------------------------------------------
@bp.get("/referrals/summary")
@jwt_required()
def referrals_summary():
    """
    Devuelve:
      { ok: true, total: N, active: M, inactive: K }

    Opcional:
      ?referrer_id=<id>  filtra por el promotor (si lo necesitas)
    """
    # ---- Guard: solo administradores ----
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if role_id is None:
        # fallback: leer desde BD usando el identity del token
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": uid},
        ).scalar()

    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    # ---- Parámetro opcional ----
    referrer_id = request.args.get("referrer_id", type=int)

    # ---- Lógica de negocio ----
    summary = get_referrals_summary(referrer_id=referrer_id)

    return jsonify({"ok": True, **summary})
