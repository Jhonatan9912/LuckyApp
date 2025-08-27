from flask import Blueprint, request, jsonify
from datetime import datetime, timezone
from app.services.referrals.referral_service import register_referral_commission

dev_bp = Blueprint("dev_mock", __name__)

@dev_bp.post("/dev/mock-subscription-payment")
def mock_subscription_payment():
    body = request.get_json(force=True)
    ok = register_referral_commission(
        referred_user_id = int(body["referred_user_id"]),   # usuario referido (quien compró)
        product_id       = body["product_id"],
        amount_micros    = int(body["amount_micros"]),      # precio en micros
        currency_code    = body.get("currency_code","COP"),
        purchase_token   = body.get("purchase_token","mock-token"),
        order_id         = body.get("order_id"),
        source           = body.get("source","google_play"),
        event_time       = datetime.now(timezone.utc),
    )
    return jsonify({"ok": ok}), 200
