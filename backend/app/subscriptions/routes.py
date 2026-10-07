# app/subscriptions/routes.py
from base64 import b64decode
from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from flask_jwt_extended import get_jwt
from app.subscriptions.service import reconcile_subscriptions
# Verificación del token OIDC que envía Pub/Sub en push
from google.oauth2 import id_token
from google.auth.transport import requests as g_requests

from app.subscriptions.service import (
    get_status,
    cancel,
    sync_purchase,
    rtdn_handle,   # ← para procesar RTDN en el service
    PurchaseOwnedByOtherUser,
)
from app.security.guards import current_user_id, is_admin

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
    status = get_status(user_id)  # ← tu objeto/DTO actual

    # --- AJUSTE DE SEMÁNTICA isPremium / entitlement ---
    # Si 'status' viene "active" y aún no llegó expiresAt → isPremium debe ser True.
    try:
        from datetime import datetime, timezone
        expires_at_str = getattr(status, "expires_at", None) or getattr(status, "expiresAt", None)
        st = getattr(status, "status", None)
        now = datetime.now(timezone.utc)

        expires_dt = None
        if expires_at_str:
            # Soporta "2025-09-01T20:09:51.007000+00:00"
            expires_dt = datetime.fromisoformat(expires_at_str.replace("Z", "+00:00"))

        is_premium = bool(st == "active" and expires_dt and expires_dt > now)

        # Refleja en la respuesta final
        if hasattr(status, "is_premium"):
            status.is_premium = is_premium
        if hasattr(status, "isPremium"):
            status.isPremium = is_premium

        # entitlement coherente
        ent = "pro" if is_premium else "free"
        if hasattr(status, "entitlement"):
            status.entitlement = ent

    except Exception:
        # Si algo falla, no rompas /status (deja lo que ya tenías)
        pass

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
        "package_name": package_name or "ENV",
        "token_len": len(verification_data),
    })

    if not product_id or not verification_data:
        return jsonify({"ok": False, "code": "MISSING_FIELDS"}), 400

    if len(verification_data) > 4096 or len(product_id) > 200 or len(purchase_id) > 200:
        return jsonify({"ok": False, "code": "BAD_REQUEST"}), 400

    try:
        result = sync_purchase(
            int(user_id), product_id, purchase_id, verification_data,
            package_name=package_name or None,
        )
        return jsonify(result), 200
    except PurchaseOwnedByOtherUser:
        return jsonify({
            "ok": False,
            "code": "PURCHASE_LINKED_TO_OTHER_ACCOUNT",
            "msg": "Esta compra ya está vinculada a otra cuenta.",
        }), 409
    except Exception:
        current_app.logger.exception("sync_purchase_failed")
        return jsonify({"ok": False, "code": "SYNC_FAILED", "msg": "No se pudo validar la compra"}), 500

@subscriptions_bp.post("/cancel")
@jwt_required()
def subscription_cancel():
    user_id = get_jwt_identity()
    if not user_id:
        return jsonify({"ok": False, "reason": "not_authenticated"}), 401

    out = cancel(int(user_id))
    return jsonify(out)

@subscriptions_bp.post("/manual-grant")
@jwt_required()
def subscription_manual_grant():
    """
    Activación/renovación manual de PRO por un administrador (ej: pago por WhatsApp).
    """
    # Rol validado contra la BD (no contra el token)
    if not is_admin(current_user_id()):
        return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401

    # Body JSON: { user_id / userId, product_id / productId, days? }
    try:
        body = request.get_json(force=True) or {}
    except Exception:
        return jsonify({"ok": False, "code": "BAD_JSON"}), 400

    user_id = body.get("user_id") or body.get("userId")
    product_id = (body.get("product_id") or body.get("productId") or "").strip()
    days = body.get("days", 30)

    if not user_id or not product_id:
        return jsonify({"ok": False, "code": "MISSING_FIELDS"}), 400

    try:
        days_int = int(days)
        if days_int <= 0:
            days_int = 30
    except Exception:
        days_int = 30
    days_int = min(days_int, 3660)

    try:
        from app.subscriptions.service import manual_grant_pro
        out = manual_grant_pro(int(user_id), product_id, days=days_int)
        return jsonify(out), 200
    except ValueError as ve:
        # Por ejemplo: producto no permitido
        return jsonify({"ok": False, "code": "BAD_PRODUCT", "msg": str(ve)}), 400
    except Exception:
        current_app.logger.exception("manual_grant_pro_failed")
        return jsonify({"ok": False, "code": "MANUAL_GRANT_FAILED", "msg": "Error interno"}), 500

@subscriptions_bp.post("/reconcile/one")
@jwt_required()
def subscription_reconcile_one():
    """
    Reconciliar un purchaseToken específico (útil para soporte o pruebas).
    Requiere JWT admin (rid / role_id == 1).
    """
    from app.observability.metrics import RECONCILE_UPD, RECONCILE_ERR

    if not is_admin(current_user_id()):
        return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401

    try:
        body = request.get_json(force=True) or {}
    except Exception:
        return jsonify({"ok": False, "code": "BAD_JSON"}), 400

    purchase_token = (body.get("purchaseToken") or "").strip()
    sub_id = (body.get("subscriptionId") or "").strip()
    if not purchase_token or not sub_id:
        return jsonify({"ok": False, "code": "BAD_REQUEST"}), 400

    try:
        # Aquí llama a tu servicio Google y actualiza DB (status, is_premium, expires_at, auto_renewing)
        # Ej: out = reconcile_one(purchase_token, sub_id)
        RECONCILE_UPD.inc()
        return jsonify({"ok": True}), 200
    except Exception:
        RECONCILE_ERR.inc()
        current_app.logger.exception("reconcile_one failed")
        return jsonify({"ok": False, "code": "RECONCILE_ERR"}), 500


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
    verified = False
    if expected_aud:
        # Con audiencia configurada el token OIDC es OBLIGATORIO
        # (antes bastaba con no enviar la cabecera para saltarse la verificación).
        if not auth_hdr.startswith("Bearer "):
            return jsonify({"ok": False, "code": "MISSING_OIDC"}), 401
        _token = auth_hdr.split(" ", 1)[1]
        try:
            claims = id_token.verify_oauth2_token(
                _token,
                g_requests.Request(),
                audience=expected_aud,
            )
            if claims.get("iss") not in ("https://accounts.google.com", "accounts.google.com"):
                return jsonify({"ok": False, "code": "BAD_ISSUER"}), 401
            verified = True
        except Exception:
            return jsonify({"ok": False, "code": "OIDC_VERIFY_FAILED"}), 401
    # Sin OIDC solo se acepta lo que Google confirme al reconsultar la compra
    # (rtdn_handle ignora los "reembolsos" no verificados).
    if not verified:
        current_app.logger.warning("RTDN sin verificación OIDC (configura PUBSUB_PUSH_AUDIENCE)")

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
        notif_type = sn.get("notificationType") or j.get("notificationType")

    except Exception:
        # No reintentes infinito: 200 con motivo
        return jsonify({"ok": True, "reason": "UNPARSEABLE_PAYLOAD"}), 200

    if not purchase_token:
        return jsonify({"ok": True, "reason": "NO_PURCHASE_TOKEN"}), 200

    # 4) Reconsultar a Google y actualizar DB
    try:
        out = rtdn_handle(
            purchase_token=purchase_token,
            package_name=package_name,
            notification_type=notif_type,
            trusted=verified,
        )
        return jsonify({"ok": bool(out.get("ok", True))}), 200
    except Exception:
        current_app.logger.exception("rtdn_handle failed")
        # 200 para que Pub/Sub no reintente infinito
        return jsonify({"ok": False, "code": "RTDN_HANDLE_ERROR"}), 200
