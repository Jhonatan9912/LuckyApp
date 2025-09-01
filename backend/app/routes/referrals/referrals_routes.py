from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.services.referrals.referral_service import get_summary_for_user, get_referrals_for_user
from app.services.referrals.payouts_service import get_payout_totals

referrals_bp = Blueprint(
    "referrals",
    __name__,
    url_prefix="/api/me/referrals"
)

@referrals_bp.get("/ping")
def ping():
    return jsonify({"ok": True, "module": "referrals"}), 200

# --- DEBUG: ver qué módulo se importó realmente ---
@referrals_bp.get("/debug/imports")
def debug_imports():
    import app.services.referrals.referral_service as rs
    import app.services.referrals.payouts_service as ps
    return jsonify({
        "referral_service_file": getattr(rs, "__file__", None),
        "payouts_service_file": getattr(ps, "__file__", None),
        "referral_service_exports": sorted([n for n in dir(rs) if n.startswith("get_")]),
        "payouts_service_exports": sorted([n for n in dir(ps) if n.startswith("get_") or n.startswith("register_")]),
    }), 200

# --- DEBUG: forzar un "stamp" en summary ---
@referrals_bp.get("/debug/summary_raw")
@jwt_required()
def debug_summary_raw():
    from app.services.referrals.referral_service import get_summary_for_user
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    data = get_summary_for_user(user_id)
    data["__debug_stamp"] = "summary_v2_should_include_commissions"
    return jsonify(data), 200

@referrals_bp.get("/summary")
@jwt_required()
def my_referrals_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    data = get_summary_for_user(user_id)
    return jsonify(data), 200

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

@referrals_bp.get("/payouts/summary")
@jwt_required()
def my_referrals_payouts_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    currency = (request.args.get("currency") or "COP").upper()
    data = get_payout_totals(user_id, currency=currency)
    return jsonify(data), 200
