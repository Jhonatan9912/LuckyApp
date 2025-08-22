# app/routes/admin/players_routes.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from app.services.admin.players_service import (
    list_players,
    delete_player_numbers,
    update_player_numbers,
    NumbersConflict,
    GameLocked,              # 👈 NUEVO
)

admin_players_bp = Blueprint("admin_players", __name__, url_prefix="/api/admin")

def _get_role_id():
    claims = get_jwt() or {}
    role_id = claims.get("role_id")
    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"), {"uid": uid}
        ).scalar()
    return role_id

@admin_players_bp.get("/players")
@jwt_required()
def players_index():
    if _get_role_id() != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    q = (request.args.get("q") or "").strip()
    page = int(request.args.get("page") or 1)
    per_page = int(request.args.get("per_page") or 50)

    data = list_players(q=q, page=page, per_page=per_page)
    return jsonify(data)

@admin_players_bp.delete("/players/<int:user_id>/games/<int:game_id>/numbers")
@jwt_required()
def players_delete_numbers(user_id: int, game_id: int):
    if _get_role_id() != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403
    try:
        deleted = delete_player_numbers(game_id=game_id, user_id=user_id)
        return jsonify({"ok": True, "deleted": int(deleted)})
    except GameLocked:
        # 423 → juego ya pasó su fecha/hora
        return jsonify({
            "ok": False,
            "error": "El juego ya comenzó o está cerrado; no se pueden editar/eliminar balotas.",
            "locked": True,
        }), 423
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@admin_players_bp.patch("/players/<int:user_id>/games/<int:game_id>/numbers")
@jwt_required()
def players_update_numbers(user_id: int, game_id: int):
    if _get_role_id() != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    payload = request.get_json(silent=True) or {}
    numbers = payload.get("numbers") or []

    try:
        updated = update_player_numbers(game_id=game_id, user_id=user_id, numbers=numbers)
        # devolver ya formateadas a 3 dígitos
        return jsonify({"ok": True, "numbers": [f"{n:03d}" for n in updated]})
    except NumbersConflict as nc:
        # 409 → coincide con lo que parsea tu Flutter (clave 'conflict')
        return jsonify({
            "ok": False,
            "error": "Estos números ya están reservados en este juego.",
            "conflict": [f"{n:03d}" for n in nc.numbers],   # 👈 singular
        }), 409
    except GameLocked:
        # 423 Locked → juego ya alcanzó su fecha/hora
        return jsonify({
            "ok": False,
            "error": "El juego ya comenzó o está cerrado; no se pueden editar balotas.",
            "locked": True,
        }), 423
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400
