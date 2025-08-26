# app/subscriptions/routes.py
from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.subscriptions.service import get_status, cancel

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


@subscriptions_bp.route("/cancel", methods=["POST"])
@jwt_required()
def subscription_cancel():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "reason": "not_authenticated"}), 401

    out = cancel(int(user_id))
    return jsonify(out)
