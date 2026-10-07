# app/routes/admin/games_routes.py
from datetime import datetime
import logging
from flask import Blueprint, request, jsonify
from app.security.guards import current_user_id, protect_blueprint_admin
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
# Todas las rutas de este blueprint exigen rol administrador.
protect_blueprint_admin(admin_games_bp)

log = logging.getLogger("admin_games")


def _server_error(where: str):
    log.exception("admin_games %s failed", where)
    return jsonify({"error": "Error interno del servidor"}), 500

me_notifications_bp = Blueprint(
    "me_notifications_bp",
    __name__,
    url_prefix="/api/me/notifications"
)

# GET /api/admin/games?q=&page=&per_page=
@admin_games_bp.get("/")

def admin_list_games():
    q = (request.args.get("q") or "").strip()[:100]
    try:
        page = max(1, int(request.args.get("page") or 1))
        per_page = max(1, min(500, int(request.args.get("per_page") or 50)))
    except ValueError:
        return jsonify({"error": "Parámetros de paginación inválidos"}), 400

    conn = None
    try:
        conn = db.engine.raw_connection()      # ✅ conexión cruda (psycopg2)
        data = list_games(conn, q=q, page=page, per_page=per_page)
        return jsonify(data), 200
    except Exception:
        return _server_error(request.endpoint or "")
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
    except Exception:
        return _server_error(request.endpoint or "")
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

    # nombre personalizado (anula lottery_id cuando viene relleno)
    lottery_name = (body.get("lottery_name") or "").strip() or None

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
        item = update_game(conn, game_id, lottery_id, scheduled_date, scheduled_time, winning_number, lottery_name=lottery_name)
        if not item:
            return jsonify({"error": "Game not found"}), 404
        return jsonify({"ok": True, "item": item}), 200
    except ValueError as e:
        if str(e) == "GAME_LOCKED":
            return jsonify({"error": "GAME_LOCKED"}), 409
        return _server_error(request.endpoint or "")
    except Exception:
        return _server_error(request.endpoint or "")
    finally:
        if conn:
            conn.close()

# body: { "winning_number": 0..999 }
@admin_games_bp.post("/<int:game_id>/winner")
def admin_set_winner(game_id: int):
    user_id = current_user_id() or 0

    body = request.get_json(silent=True) or {}
    if "winning_number" not in body:
        return jsonify({"error": "winning_number es requerido"}), 400

    raw = body["winning_number"]
    # Acepta "007" o 7
    if isinstance(raw, str):
        s = raw.strip()
        if not s.isdigit():
            return jsonify({"error": "winning_number debe contener solo dígitos"}), 400
        winning_number = int(s)
    else:
        try:
            winning_number = int(raw)
        except (TypeError, ValueError):
            return jsonify({"error": "winning_number debe ser entero"}), 400



    conn = None
    try:
        conn = db.engine.raw_connection()
        item = set_winning_number(conn, game_id, winning_number, int(user_id))
        if not item:
            # Puede ser porque el número no pertenece al juego
            return jsonify({"error": "Número inválido para este juego o juego inexistente"}), 400
        return jsonify({"ok": True, "item": item}), 200
    except Exception:
        return _server_error(request.endpoint or "")
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
    except Exception:
        return _server_error(request.endpoint or "")
    finally:
        if conn:
            conn.close()
@me_notifications_bp.get("/peek-schedule")
def peek_schedule():
    uid = current_user_id(optional=True)
    if uid is None:
        return jsonify({}), 200

    conn = None
    try:
        conn = db.engine.raw_connection()
        item = peek_latest_schedule_notice(conn, uid)  # no marca leído
        return jsonify(item or {}), 200
    except Exception:
        return _server_error(request.endpoint or "")
    finally:
        if conn:
            conn.close()

@me_notifications_bp.post("/mark-read")
def mark_read():
    uid = current_user_id(optional=True)
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
    except Exception:
        return _server_error(request.endpoint or "")
    finally:
        if conn:
            conn.close()
