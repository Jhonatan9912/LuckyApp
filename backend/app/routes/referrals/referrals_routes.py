# app/routes/referrals/referrals_routes.py
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.services.referrals.referral_service import (
    get_summary_for_user,
    get_referrals_for_user,
)
from app.services.referrals.payouts_service import get_payout_totals

# Blueprint del usuario actual: /api/me/referrals
referrals_bp = Blueprint(
    "referrals",
    __name__,
    url_prefix="/api/me/referrals",
)

@referrals_bp.get("/ping")
def ping():
    return jsonify({"ok": True, "module": "referrals"}), 200

# GET /api/me/referrals/summary
# Producción: ventana fija de 3 días para "retenida" -> "disponible"
@referrals_bp.get("/summary")
@jwt_required()
def my_referrals_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    data = get_summary_for_user(user_id, hold_days=3)
    return jsonify(data), 200

# GET /api/me/referrals/?limit=&offset=

@referrals_bp.get("/")
@jwt_required()
def my_referrals_list():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    try:
        limit = int(request.args.get("limit", 50))
        offset = int(request.args.get("offset", 0))
        limit = max(1, min(limit, 200))
        offset = max(0, offset)
    except Exception:
        limit, offset = 50, 0

    items = get_referrals_for_user(user_id, limit=limit, offset=offset)
    return jsonify(items), 200

# GET /api/me/referrals/payouts/summary?currency=COP
@referrals_bp.get("/payouts/summary")
@jwt_required()
def my_referrals_payouts_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    currency = (request.args.get("currency") or "COP").upper()
    data = get_payout_totals(user_id, currency=currency)
    return jsonify(data), 200

@referrals_bp.post("/referrals/dev/mature")
@jwt_required()
def dev_mature_referral_commissions():
    """
    DEV ONLY: promueve comisiones pending -> available usando minutos o días.
    Ej: POST /api/referrals/dev/mature?minutes=1
    """
    minutes = request.args.get("minutes", type=int)
    days = request.args.get("days", type=int)

    # (opcional) valida rol/admin si quieres reforzar seguridad
    # user_id = int(get_jwt_identity())

    from app.services.referrals.payouts_service import mature_commissions
    updated = mature_commissions(days=days, minutes=minutes)
    return {"updated": updated, "minutes": minutes, "days": days}, 200