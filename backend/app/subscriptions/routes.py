# app/subscriptions/routes.py
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.subscriptions.service import get_status, cancel, sync_purchase  # ← añade sync_purchase

subscriptions_bp = Blueprint(
    "subscriptions",
    __name__,
    url_prefix="/api/subscriptions",
)

@subscriptions_bp.get("/ping")
def ping():
    return jsonify({"ok": True, "module": "subscriptions"})


@subscriptions_bp.get("/status")
@jwt_required(optional=True)  # hazlo obligatorio si lo prefieres
def subscription_status():
    user_id = get_jwt_identity()
    status = get_status(user_id)
    return jsonify(status.to_json())


@subscriptions_bp.post("/sync")  # ← NUEVO
@jwt_required()
def subscription_sync():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "code": "UNAUTHENTICATED"}), 401

    try:
        body = request.get_json(force=True) or {}
    except Exception:
        return jsonify({"ok": False, "code": "BAD_JSON"}), 400

    product_id = (body.get("product_id") or "").strip()
    purchase_id = (body.get("purchase_id") or "").strip()
    verification_data = (body.get("verification_data") or "").strip()

    if not product_id or not verification_data:
        return jsonify({"ok": False, "code": "MISSING_FIELDS"}), 400

    result = sync_purchase(
        int(user_id), product_id, purchase_id, verification_data
    )
    # result ya debe traer ok, isPremium, status, expiresAt...
    return jsonify(result), 200


@subscriptions_bp.post("/cancel")
@jwt_required()
def subscription_cancel():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "reason": "not_authenticated"}), 401

    out = cancel(int(user_id))
    return jsonify(out)
