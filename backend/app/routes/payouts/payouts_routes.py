# app/routes/payouts/payouts_routes.py
from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.db.database import db
from app.services.payouts.payouts_service import (
    create_payout_request,
    ALLOWED_TYPES,
    ALLOWED_BANK_KINDS,
)

# Alineado con el cliente móvil:
# ReferralsApi -> /api/me/referrals/payouts/requests
payouts_bp = Blueprint("payouts", __name__, url_prefix="/api/me/referrals/payouts")


@payouts_bp.post("/requests")
@jwt_required()
def create_request():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)

    data = request.get_json(silent=True) or {}
    flat = data
    inner = data.get("data") if isinstance(data.get("data"), dict) else {}

    account_type   = (flat.get("account_type") or "").strip().lower()
    account_number = (inner.get("account_number") or flat.get("account_number") or "").strip()

    account_kind = inner.get("account_kind") or flat.get("account_kind") or None
    if isinstance(account_kind, str):
        account_kind = account_kind.strip().lower()

    bank_code = inner.get("bank_code") or flat.get("bank_code") or None
    if isinstance(bank_code, str):
        bank_code = bank_code.strip().upper()

    observations = (inner.get("observations") or flat.get("observations") or "").strip() or None

    if account_type not in ALLOWED_TYPES:
        return jsonify({"ok": False, "error": "account_type inválido"}), 400
    if not account_number:
        return jsonify({"ok": False, "error": "account_number requerido"}), 400
    if account_type == "bank":
        if not bank_code:
            return jsonify({"ok": False, "error": "bank_code requerido para cuenta bancaria"}), 400
        if not account_kind or account_kind not in ALLOWED_BANK_KINDS:
            return jsonify({"ok": False, "error": "account_kind debe ser 'savings' o 'checking'"}), 400
    if observations and len(observations) > 500:
        return jsonify({"ok": False, "error": "observations demasiado largas (máx 500)"}), 400

    try:
        out = create_payout_request(
            user_id=user_id,
            account_type=account_type,
            account_number=account_number,
            account_kind=account_kind,
            bank_code=bank_code,
            observations=observations,
        )
        db.session.commit()  # 👈 COMMIT REAL DEL REQUEST HTTP
        return jsonify({"ok": True, "item": out}), 201
    except ValueError as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("create_payout_request failed")
        return jsonify({"ok": False, "error": f"server_error: {e}"}), 500
