from flask import Blueprint, request, jsonify, session, current_app
from app.db.database import db
from app.services.notify.notifications_service import (
    list_notifications, mark_as_read, mark_all_as_read
)
import os
import jwt           # PyJWT
import logging
from app.services.notify.device_tokens_service import (
    register_device_token as svc_register,
    delete_device_token as svc_delete,
    send_test_push as svc_send_test,
)

from app.services.notify.device_tokens_service import (
    register_device_token as svc_register_token,
    delete_device_token   as svc_delete_token,
)

def _jwt_secret():
    # Usa el mismo secreto que firmó el token
    return (
        current_app.config.get("JWT_SECRET_KEY")
        or os.getenv("JWT_SECRET")                 # por si lo cargas desde .env
        or current_app.config.get("SECRET_KEY")    # último recurso
    )

ALLOW_UNVERIFIED_JWT = os.getenv("ALLOW_UNVERIFIED_JWT", "false").lower() in ("1", "true", "yes")

def _log(msg, *args):
    logging.getLogger("notifications").warning(msg, *args)

def _user_from_session() -> int | None:
    uid = session.get("user_id")
    if uid:
        _log("[AUTH] session user_id=%s", uid)
        return int(uid)
    return None

def _user_from_bearer() -> int | None:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth.split(" ", 1)[1]

    # 1) Intento con verificación de firma
    try:
        payload = jwt.decode(token, _jwt_secret(), algorithms=["HS256"])
        sub = payload.get("sub")
        _log("[AUTH] Bearer OK con firma; sub=%s", sub)
        return int(sub) if sub is not None else None
    
    except Exception as e:
        _log("[AUTH] Bearer con firma FALLÓ: %s", e)
        # Solo para depurar el payload, no aceptar:
        try:
            payload_unverified = jwt.decode(token, options={"verify_signature": False}, algorithms=["HS256"])
            _log("[AUTH] Bearer sin verif.: payload=%s", payload_unverified)
        except Exception:
            pass
        return None


def _user_from_x_user_id() -> int | None:
    xuid = request.headers.get("X-USER-ID")
    if xuid and str(xuid).isdigit():
        _log("[AUTH] X-USER-ID=%s", xuid)
        return int(xuid)
    return None

def _resolve_user_id() -> int | None:
    """Intenta: session → bearer → X-USER-ID"""
    return _user_from_session() or _user_from_bearer() or _user_from_x_user_id()

notifications_bp = Blueprint("notifications_bp", __name__, url_prefix="/api/notifications")

@notifications_bp.get("")
def get_notifications():
    uid = _resolve_user_id()
    if not uid:
        _log("[AUTH] get_notifications => 403 (no se pudo resolver user)")
        return jsonify({"error": "No autorizado"}), 403

    unread = (request.args.get("unread") == "1")
    page = int(request.args.get("page") or 1)
    per_page = int(request.args.get("per_page") or 50)

    _log("[NOTIFS] uid=%s unread=%s page=%s per_page=%s", uid, unread, page, per_page)

    conn = db.engine.raw_connection()
    try:
        data = list_notifications(conn, int(uid), unread, page, per_page)
        return jsonify(data), 200
    finally:
        conn.close()

@notifications_bp.patch("/read")
def api_mark_read():
    uid = _resolve_user_id()
    if not uid:
        _log("[AUTH] mark_read => 403")
        return jsonify({"error": "No autorizado"}), 403

    body = request.get_json(silent=True) or {}
    ids = [int(x) for x in (body.get("ids") or []) if str(x).isdigit()]

    conn = db.engine.raw_connection()
    try:
        n = mark_as_read(conn, int(uid), ids)
        _log("[NOTIFS] mark_read uid=%s updated=%s", uid, n)
        return jsonify({"ok": True, "updated": n}), 200
    finally:
        conn.close()

@notifications_bp.patch("/read-all")
def api_mark_all_read():
    uid = _resolve_user_id()
    if not uid:
        _log("[AUTH] mark_all_read => 403")
        return jsonify({"error": "No autorizado"}), 403

    conn = db.engine.raw_connection()
    try:
        n = mark_all_as_read(conn, int(uid))
        _log("[NOTIFS] mark_all_read uid=%s updated=%s", uid, n)
        return jsonify({"ok": True, "updated": n}), 200
    finally:
        conn.close()

@notifications_bp.post("/register-token")
def api_register_token():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error":"No autorizado"}), 403
    body = request.get_json(silent=True) or {}
    token = (body.get("device_token") or "").strip()
    platform = (body.get("platform") or "").strip().lower()
    if not token:
        return jsonify({"error":"device_token es requerido"}), 400
    ent = svc_register_token(user_id=int(uid), device_token=token, platform=platform)
    return jsonify({
        "ok": True,
        "id": ent.id,
        "user_id": ent.user_id,
        "platform": ent.platform,
        "last_seen_at": ent.last_seen_at.isoformat()
    }), 200

@notifications_bp.post("/delete-token")
def api_delete_token():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error":"No autorizado"}), 403
    body = request.get_json(silent=True) or {}
    token = (body.get("device_token") or "").strip()
    if not token:
        return jsonify({"error":"device_token es requerido"}), 400
    ok = svc_delete_token(user_id=int(uid), device_token=token)
    return jsonify({"ok": ok}), 200

@notifications_bp.post("/send-test")
def api_send_test():
    uid = _resolve_user_id()
    if not uid:
        _log("[AUTH] send_test => 403")
        return jsonify({"error": "No autorizado"}), 403

    body = request.get_json(silent=True) or {}
    device_token = (body.get("device_token") or "").strip()
    if not device_token:
        return jsonify({"error": "device_token es requerido"}), 400

    title = body.get("title")
    msg = body.get("body")
    extra = body.get("data") if isinstance(body.get("data"), dict) else None

    res = svc_send_test(device_token=device_token, title=title, body=msg, data=extra)
    return jsonify(res), (200 if res.get("ok") else 500)