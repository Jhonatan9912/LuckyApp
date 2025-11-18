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

@subscriptions_bp.post("/manual-grant")
@jwt_required()
def subscription_manual_grant():
    """
    Activación/renovación manual de PRO por un administrador (ej: pago por WhatsApp).
    """
    # Solo admin: role_id / rid == 2
    from flask_jwt_extended import get_jwt
    claims = get_jwt() or {}
    role_id = claims.get("rid") or claims.get("role_id")
    if role_id != 2:
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

    try:
        from app.subscriptions.service import manual_grant_pro
        out = manual_grant_pro(int(user_id), product_id, days=days_int)
        return jsonify(out), 200
    except ValueError as ve:
        # Por ejemplo: producto no permitido
        return jsonify({"ok": False, "code": "BAD_PRODUCT", "msg": str(ve)}), 400
    except Exception as e:
        current_app.logger.exception("manual_grant_pro_failed")
        return jsonify({"ok": False, "code": "MANUAL_GRANT_FAILED", "msg": str(e)}), 500

@subscriptions_bp.post("/reconcile")
@jwt_required(optional=True)
def subscription_reconcile():
    """
    Permite dos modos de autenticación:
    - JWT con rol admin (claim 'rid' o 'role_id' == 2)
    - Header X-Reconcile-Token que coincida con RECONCILE_TOKEN (para cron)
    """
    claims = {}
    try:
        claims = get_jwt() or {}
    except Exception:
        # optional=True: puede no venir JWT
        claims = {}

    role_id = claims.get("rid") or claims.get("role_id")

    expected = current_app.config.get("RECONCILE_TOKEN")
    provided = request.headers.get("X-Reconcile-Token")

    allowed = (role_id == 2) or (expected and provided == expected)
    if not allowed:
        return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401

    # Parámetros opcionales de lote
    try:
        body = request.get_json(silent=True) or {}
    except Exception:
        body = {}

    batch_size = int(body.get("batch_size", 100))
    days_ahead = int(body.get("days_ahead", 2))

    out = reconcile_subscriptions(batch_size=batch_size, days_ahead=days_ahead)
    return jsonify({"ok": True, "result": out}), 200

@subscriptions_bp.post("/reconcile/one")
@jwt_required()
def subscription_reconcile_one():
    """
    Reconciliar un purchaseToken específico (útil para soporte o pruebas).
    Requiere JWT admin (rid / role_id == 2).
    """
    from app.observability.metrics import RECONCILE_UPD, RECONCILE_ERR
    from flask_jwt_extended import get_jwt

    claims = get_jwt() or {}
    role_id = claims.get("rid") or claims.get("role_id")

    # En tu app, el admin es role_id == 1
    if role_id != 1:
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
        # Simbolizamos el contador OK:
        RECONCILE_UPD.inc()
        return jsonify({"ok": True}), 200
    except Exception as e:
        RECONCILE_ERR.inc()
        return jsonify({"ok": False, "code": "RECONCILE_ERR", "detail": str(e)}), 500

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
        notif_type = sn.get("notificationType") or j.get("notificationType")

    except Exception:
        # No reintentes infinito: 200 con motivo
        return jsonify({"ok": True, "reason": "UNPARSEABLE_PAYLOAD"}), 200

    if not purchase_token:
        return jsonify({"ok": True, "reason": "NO_PURCHASE_TOKEN"}), 200

    # 4) Reconsultar a Google y actualizar DB
    try:
        out = rtdn_handle(purchase_token=purchase_token, package_name=package_name, notification_type=notif_type)
        return jsonify({"ok": True, "result": out}), 200
    except Exception as e:
        # Si quieres que Pub/Sub reintente, devuelve 5xx; si no, 200 con error
        return jsonify({"ok": False, "code": "RTDN_HANDLE_ERROR", "msg": str(e)}), 200
