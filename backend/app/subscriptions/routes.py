# app/subscriptions/routes.py
from base64 import b64decode
from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.subscriptions.service import reconcile_subscriptions
# Verificación del token OIDC que envía Pub/Sub en push
from google.oauth2 import id_token
from google.auth.transport import requests as g_requests

from app.subscriptions.service import (
    get_status,
    cancel,
    sync_purchase,
    rtdn_handle,   # ← para procesar RTDN en el service
)

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


@subscriptions_bp.post("/sync")
@jwt_required()
def subscription_sync():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "code": "UNAUTHENTICATED"}), 401

    try:
        body = request.get_json(force=True) or {}
    except Exception:
        return jsonify({"ok": False, "code": "BAD_JSON"}), 400

    product_id = (body.get("product_id") or body.get("productId") or "").strip()
    purchase_id = (body.get("purchase_id") or body.get("purchaseId") or "").strip()
    verification_data = (body.get("verification_data") or body.get("verificationData") or "").strip()
    package_name = (body.get("package_name") or body.get("packageName") or "").strip()

    # 🔎 LOGS ÚTILES
    current_app.logger.info({
        "event": "sync_req",
        "user_id": user_id,
        "product_id": product_id,
        "purchase_id": purchase_id,
        "package_name": package_name or "ENV",
        "token_len": len(verification_data),
        "token_prefix": verification_data[:12] if verification_data else None,
    })

    if not product_id or not verification_data:
        return jsonify({"ok": False, "code": "MISSING_FIELDS"}), 400

    try:
        result = sync_purchase(
            int(user_id), product_id, purchase_id, verification_data,
            package_name=package_name or None,
        )
        return jsonify(result), 200
    except Exception as e:
        # Devuelve el error en JSON para depurar rápido desde el móvil/Postman
        current_app.logger.exception("sync_purchase_failed")
        return jsonify({"ok": False, "code": "SYNC_FAILED", "msg": str(e)}), 500

@subscriptions_bp.post("/cancel")
@jwt_required()
def subscription_cancel():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "reason": "not_authenticated"}), 401

    out = cancel(int(user_id))
    return jsonify(out)

@subscriptions_bp.post("/reconcile")
def subscription_reconcile():
    # Protección simple con un token de cabecera (opcional pero recomendado)
    expected = current_app.config.get("RECONCILE_TOKEN")
    provided = request.headers.get("X-Reconcile-Token")
    if expected and provided != expected:
        return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401

    # Parámetros opcionales
    try:
        body = request.get_json(silent=True) or {}
    except Exception:
        body = {}
    batch_size = int(body.get("batch_size", 100))
    days_ahead = int(body.get("days_ahead", 2))

    out = reconcile_subscriptions(batch_size=batch_size, days_ahead=days_ahead)
    return jsonify({"ok": True, "result": out}), 200

# ===== RTDN (Real-Time Developer Notifications) - Push endpoint =====
@subscriptions_bp.post("/rtdn")
def rtdn_push():
    """
    Endpoint push para Pub/Sub (RTDN de Google Play).
    Verifica el token OIDC (si configuraste push-auth) y procesa el mensaje.
    """
    # 1) Verificación OIDC del push (si configuraste autenticación en la suscripción)
    expected_aud = current_app.config.get("PUBSUB_PUSH_AUDIENCE")  # p.ej. https://tuapp/api/subscriptions/rtdn
    auth_hdr = request.headers.get("Authorization", "")
    if expected_aud and auth_hdr.startswith("Bearer "):
        _token = auth_hdr.split(" ", 1)[1]
        try:
            claims = id_token.verify_oauth2_token(
                _token,
                g_requests.Request(),
                audience=expected_aud,
            )
            if claims.get("iss") not in ("https://accounts.google.com", "accounts.google.com"):
                return jsonify({"ok": False, "code": "BAD_ISSUER"}), 401
        except Exception as e:
            return jsonify({"ok": False, "code": "OIDC_VERIFY_FAILED", "msg": str(e)}), 401
    # Si no configuraste OIDC, continúa, pero no es recomendado en producción.

    # 2) Decodifica el mensaje Pub/Sub
    body = request.get_json(silent=True) or {}
    msg = (body.get("message") or {})
    data_b64 = msg.get("data")
    if not data_b64:
        # Pub/Sub puede enviar mensajes de prueba sin data
        return jsonify({"ok": True, "reason": "NO_DATA"}), 200

    try:
        payload = b64decode(data_b64).decode("utf-8", errors="ignore")
    except Exception:
        return jsonify({"ok": False, "code": "BAD_BASE64"}), 400

    # 3) Extrae purchaseToken y packageName (no confíes ciegamente en el payload)
    purchase_token = None
    package_name = None
    try:
        import json
        j = json.loads(payload)
        package_name = j.get("packageName")
        sn = j.get("subscriptionNotification") or {}
        purchase_token = sn.get("purchaseToken") or j.get("purchaseToken")
    except Exception:
        # No reintentes infinito: 200 con motivo
        return jsonify({"ok": True, "reason": "UNPARSEABLE_PAYLOAD"}), 200

    if not purchase_token:
        return jsonify({"ok": True, "reason": "NO_PURCHASE_TOKEN"}), 200

    # 4) Reconsultar a Google y actualizar DB
    try:
        out = rtdn_handle(purchase_token=purchase_token, package_name=package_name)
        return jsonify({"ok": True, "result": out}), 200
    except Exception as e:
        # Si quieres que Pub/Sub reintente, devuelve 5xx; si no, 200 con error
        return jsonify({"ok": False, "code": "RTDN_HANDLE_ERROR", "msg": str(e)}), 200
