# app/routes/admin/games_routes.py
from datetime import datetime
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity
from flask import Blueprint, request, jsonify, session
from app.db.database import db  # <- tu SQLAlchemy()
from app.services.admin.games_service import (
    list_games,
    list_lotteries,
    update_game,
    delete_game,
    set_winning_number,
    peek_latest_schedule_notice,   # 👈 en vez de pop
    mark_notifications_read,       # 👈 nueva
)

admin_games_bp = Blueprint("admin_games_bp", __name__, url_prefix="/api/admin/games")

me_notifications_bp = Blueprint(
    "me_notifications_bp",
    __name__,
    url_prefix="/api/me/notifications"
)

# GET /api/admin/games?q=&page=&per_page=
@admin_games_bp.get("/")

def admin_list_games():
    q = (request.args.get("q") or "").strip()
    page = int(request.args.get("page") or 1)
    per_page = int(request.args.get("per_page") or 50)

    conn = None
    try:
        conn = db.engine.raw_connection()      # ✅ conexión cruda (psycopg2)
        data = list_games(conn, q=q, page=page, per_page=per_page)
        return jsonify(data), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()                       # ✅ cerrar

# GET /api/admin/games/lotteries
@admin_games_bp.get("/lotteries")
def admin_list_lotteries():
    conn = None
    try:
        conn = db.engine.raw_connection()
        items = list_lotteries(conn)
        return jsonify({"items": items}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()
@admin_games_bp.patch("/<int:game_id>")
def admin_update_game(game_id: int):
    body = request.get_json(silent=True) or {}

    # lottery_id opcional
    lottery_id = body.get("lottery_id")
    try:
        lottery_id = int(lottery_id) if lottery_id is not None else None
    except (TypeError, ValueError):
        lottery_id = None

    # fecha/hora opcionales
    scheduled_date = (body.get("played_date") or "").strip() or None
    scheduled_time = (body.get("played_time") or "").strip() or None

    # número ganador opcional
    winning_number = body.get("winning_number")
    try:
        winning_number = int(winning_number) if winning_number is not None else None
    except (TypeError, ValueError):
        winning_number = None

    conn = None
    try:
        conn = db.engine.raw_connection()
        item = update_game(conn, game_id, lottery_id, scheduled_date, scheduled_time, winning_number)
        if not item:
            return jsonify({"error": "Game not found"}), 404
        return jsonify({"ok": True, "item": item}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()

# body: { "winning_number": 0..999 }
@admin_games_bp.post("/<int:game_id>/winner")
def admin_set_winner(game_id: int):
    # ✅ Verificación básica de permisos (ajusta según tu sistema):
    user_id = session.get("user_id") or 0

    body = request.get_json(silent=True) or {}
    if "winning_number" not in body:
        return jsonify({"error": "winning_number es requerido"}), 400

    raw = body["winning_number"]
    # Acepta tanto "007" (str) como 7 (int)
    if isinstance(raw, str):
        s = raw.strip()
        if not s.isdigit():
            return jsonify({"error": "winning_number debe contener solo dígitos"}), 400
        winning_number = int(s)
    else:
        try:
            winning_number = int(raw)
        except (TypeError, ValueError):
            return jsonify({"error": "winning_number debe ser entero 0..999"}), 400

    if winning_number < 0 or winning_number > 999:
        return jsonify({"error": "winning_number debe estar entre 0 y 999"}), 400



    conn = None
    try:
        conn = db.engine.raw_connection()
        item = set_winning_number(conn, game_id, winning_number, int(user_id))
        if not item:
            # Puede ser porque el número no pertenece al juego
            return jsonify({"error": "Número inválido para este juego o juego inexistente"}), 400
        return jsonify({"ok": True, "item": item}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()

# DELETE /api/admin/games/<id>
@admin_games_bp.delete("/<int:game_id>")
def admin_delete_game(game_id: int):
    conn = None
    try:
        conn = db.engine.raw_connection()
        deleted = delete_game(conn, game_id)
        if not deleted:
            return jsonify({"error": "Game not found"}), 404
        return ("", 204)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()
@me_notifications_bp.get("/peek-schedule")
def peek_schedule():
    uid = None

    xuid = request.headers.get("X-USER-ID")
    if xuid and xuid.isdigit():
        uid = int(xuid)

    if uid is None:
        try:
            verify_jwt_in_request(optional=True)
            ident = get_jwt_identity()
            uid = int(ident) if ident is not None else None
        except Exception:
            uid = None

    if uid is None:
        s_uid = session.get("user_id")
        uid = int(s_uid) if s_uid else None

    if uid is None:
        return jsonify({}), 200

    conn = None
    try:
        conn = db.engine.raw_connection()
        item = peek_latest_schedule_notice(conn, uid)  # no marca leído
        return jsonify(item or {}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()

@me_notifications_bp.post("/mark-read")
def mark_read():
    uid = None
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth.split(" ", 1)[1]
        try:
            # payload = decode_token(token)
            # uid = int(payload.get("user_id") or payload.get("sub"))
            pass
        except Exception:
            uid = None
    if uid is None:
        xuid = request.headers.get("X-USER-ID")
        if xuid and xuid.isdigit():
            uid = int(xuid)
    if uid is None:
        s_uid = session.get("user_id")
        uid = int(s_uid) if s_uid else None

    if uid is None:
        return jsonify({"error": "no_user"}), 401

    body = request.get_json(silent=True) or {}
    ids = body.get("ids") or []
    try:
        ids = [int(x) for x in ids]
    except Exception:
        ids = []

    conn = None
    try:
        conn = db.engine.raw_connection()
        updated = mark_notifications_read(conn, uid, ids)
        return jsonify({"ok": True, "updated": updated}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            conn.close()
