from flask import Blueprint, request, jsonify
from app.db.database import db
from app.services.notify.notifications_service import (
    list_notifications, mark_as_read, mark_all_as_read
)
from app.services.notify.device_tokens_service import (
    register_device_token as svc_register_token,
    delete_device_token as svc_delete_token,
    send_test_push as svc_send_test,
)
from app.security.guards import current_user_id, admin_required


def _resolve_user_id() -> int | None:
    # Solo JWT verificado (firma, expiración y revocación).
    return current_user_id(optional=True)


def _page_args(default_per_page: int = 50) -> tuple[int, int]:
    try:
        page = max(1, int(request.args.get("page") or 1))
        per_page = max(1, min(200, int(request.args.get("per_page") or default_per_page)))
    except (TypeError, ValueError):
        page, per_page = 1, default_per_page
    return page, per_page


notifications_bp = Blueprint("notifications_bp", __name__, url_prefix="/api/notifications")


@notifications_bp.get("")
def get_notifications():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error": "No autorizado"}), 403

    unread = (request.args.get("unread") == "1")
    page, per_page = _page_args()

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
        return jsonify({"error": "No autorizado"}), 403

    body = request.get_json(silent=True) or {}
    ids = [int(x) for x in (body.get("ids") or []) if str(x).isdigit()][:500]

    conn = db.engine.raw_connection()
    try:
        n = mark_as_read(conn, int(uid), ids)
        return jsonify({"ok": True, "updated": n}), 200
    finally:
        conn.close()


@notifications_bp.patch("/read-all")
def api_mark_all_read():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error": "No autorizado"}), 403

    conn = db.engine.raw_connection()
    try:
        n = mark_all_as_read(conn, int(uid))
        return jsonify({"ok": True, "updated": n}), 200
    finally:
        conn.close()


@notifications_bp.post("/register-token")
def api_register_token():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error": "No autorizado"}), 403
    body = request.get_json(silent=True) or {}
    token = (body.get("device_token") or "").strip()
    platform = (body.get("platform") or "").strip().lower()[:20]
    if not token or len(token) > 4096:
        return jsonify({"error": "device_token inválido"}), 400
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
        return jsonify({"error": "No autorizado"}), 403
    body = request.get_json(silent=True) or {}
    token = (body.get("device_token") or "").strip()
    if not token:
        return jsonify({"error": "device_token es requerido"}), 400
    ok = svc_delete_token(user_id=int(uid), device_token=token)
    return jsonify({"ok": ok}), 200


# Envío de prueba a un dispositivo arbitrario: solo administradores
# (antes cualquier usuario podía enviar notificaciones a cualquier token).
@notifications_bp.post("/send-test")
@admin_required
def api_send_test():
    body = request.get_json(silent=True) or {}
    device_token = (body.get("device_token") or "").strip()
    if not device_token:
        return jsonify({"error": "device_token es requerido"}), 400

    title = body.get("title")
    msg = body.get("body")
    extra = body.get("data") if isinstance(body.get("data"), dict) else None

    res = svc_send_test(device_token=device_token, title=title, body=msg, data=extra)
    return jsonify(res), (200 if res.get("ok") else 500)
