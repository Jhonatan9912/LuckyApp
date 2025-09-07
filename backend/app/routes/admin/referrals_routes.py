# app/routes/admin/referrals_routes.py
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db

from . import bp  # blueprint del paquete admin
from app.services.admin.referrals_service import get_referrals_summary
from app.services.payouts.payouts_service import list_commission_requests
from werkzeug.exceptions import BadRequest
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

@bp.get("/referrals/top")
@jwt_required()
def referrals_top():
    """
    Devuelve el top de referidores con más referidos activos.
    """
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    from app.services.admin.referrals_service import get_top_referrers
    top = get_top_referrers(limit=5)

    return jsonify({"ok": True, "items": top})

@bp.get("/referrals/commission-requests")
@jwt_required()
def admin_list_commission_requests():
    # ---- Guard: solo administradores (mismo patrón que summary/top) ----
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": uid},
        ).scalar()
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    # 👇 Import aquí para evitar que un error al importar en módulo
    # corte el registro de la ruta.
    from app.services.payouts.payouts_service import list_commission_requests

    status = request.args.get("status")
    limit = int(request.args.get("limit", "50"))
    offset = int(request.args.get("offset", "0"))

    try:
        items = list_commission_requests(status=status, limit=limit, offset=offset)
        return jsonify({"ok": True, "items": items}), 200
    except ValueError as ve:
        return jsonify({"ok": False, "error": str(ve)}), 400

@bp.get("/referrals/__ping__")
@jwt_required()
def admin_referrals_ping():
    return jsonify({"ok": True, "msg": "admin referrals routes loaded"}), 200
