# backend/app/routes/games/games_routes.py
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.db.database import db
from app.subscriptions.service import get_status as get_sub_status

# Usa el guard centralizado del service (fecha + estado)
from app.services.games.games_service import _is_user_pro

# Servicios
from app.services.games import games_service
from app.services.games.games_service import (
    generate_five_available,
    commit_selection,
    commit_selection_auto,  # 👈 NUEVO
    get_current_selection,  # ← usar la selección SOLO del juego abierto
    list_user_history,
)



from app.services.notify.notifications_service import (
    create_notifications_for_game_winner,
)

# Resolver user_id unificado (session → bearer → X-USER-ID)
from app.security.auth_utils import resolve_user_id as _resolve_user_id

games_bp = Blueprint("games_bp", __name__, url_prefix="/api/games")


@games_bp.post("/generate")
@jwt_required(optional=True)
def generate():
    uid_raw = get_jwt_identity()  # puede ser None
    uid = int(uid_raw) if uid_raw is not None else None

    # 👇 Leer digits del query (?digits=3|4)
    try:
        digits = int(request.args.get("digits", "3"))
    except ValueError:
        digits = 3
    if digits not in (3, 4):
        digits = 3

    try:
        # Guard explícito: solo PRO pueden generar (como ya lo tenías)
        if not uid or not _is_user_pro(uid):
            return jsonify({
                "ok": False,
                "code": "NOT_PREMIUM",
                "message": "Necesitas la suscripción PRO para jugar."
            }), 403

        # 🆕 Consultar el plan del usuario
        sub_status = get_sub_status(uid)
        max_digits = sub_status.max_digits or 0

        # 🛡️ Blindaje: si intenta generar juego de 4 cifras sin plan 60k
        if digits == 4 and max_digits < 4:
            return jsonify({
                "ok": False,
                "code": "FOUR_DIGITS_NOT_ALLOWED",
                "message": "Tu plan actual solo permite jugar a 3 cifras."
            }), 403

        # 👇 PASAR digits al service
        gid, numbers = generate_five_available(uid, digits=digits)
        db.session.commit()


        return jsonify({
            "ok": True,
            "data": {
                "game_id": gid,
                "numbers": numbers
            }
        }), 200

    except PermissionError as e:
        db.session.rollback()
        return jsonify({"ok": False, "code": "NOT_PREMIUM", "message": str(e)}), 403
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "message": str(e)}), 500


@games_bp.post("/commit")
@jwt_required()
def commit():
    uid_raw = get_jwt_identity()
    try:
        uid = int(uid_raw)
    except (TypeError, ValueError):
        return jsonify({"error": "Token inválido"}), 401

    data = request.get_json(silent=True) or {}
    game_id = data.get("game_id")
    numbers = data.get("numbers")
    digits = data.get("digits", 3)  # 👈 nuevo campo

    if not isinstance(numbers, list):
        return jsonify({"error": "numbers debe ser una lista"}), 400

    try:
        numbers_int = [int(n) for n in numbers]
    except Exception:
        return jsonify({"error": "numbers debe contener enteros"}), 400

    try:
        digits = int(digits)
    except Exception:
        digits = 3
    if digits not in (3, 4):
        digits = 3

    # 👇 SI NO VIENE game_id → crear/usar juego automáticamente
    if game_id in (None, 0, "0"):
        res = games_service.commit_selection_auto(
            uid,
            numbers_int,
            digits=digits,
        )
    else:
        if not isinstance(game_id, int):
            return jsonify({"error": "game_id inválido"}), 400
        res = commit_selection(uid, game_id, numbers_int)

    if res.get("ok"):
        flat = {k: v for k, v in res.items() if k != "ok"}
        return jsonify({"ok": True, "data": flat}), 200

    code = res.get("code")
    if code == "NOT_PREMIUM":
        return jsonify(res), 403
    if code in ("CONFLICT", "GAME_SWITCHED"):
        return jsonify(res), 409
    return jsonify(res), 400


@games_bp.delete("/<int:game_id>/selection")
@jwt_required(optional=True)
def release(game_id: int):
    # primero intenta con header X-USER-ID (para forzar identidad exacta)
    uid_hdr = request.headers.get("X-USER-ID")
    uid_jwt = get_jwt_identity()

    uid = uid_hdr if uid_hdr is not None else uid_jwt
    try:
        uid = int(uid) if uid is not None else None
    except Exception:
        uid = None

    if uid is None:
        return jsonify({"ok": False, "code": "UNAUTHORIZED", "message": "Sin usuario"}), 401

    res = games_service.release_selection(user_id=uid, game_id=game_id)
    if not res.get("ok"):
        return jsonify({"ok": False, "code": "RELEASE_ERROR", "message": res.get("error", "")}), 500

    if res.get("released", 0) == 0:
        return jsonify({"ok": False, "code": "NOT_FOUND", "message": "No había reserva previa"}), 404

    return jsonify({"ok": True, "released": res["released"]}), 200


@games_bp.get("/my-selection")
@jwt_required()
def my_selection():
    uid_raw = get_jwt_identity()
    try:
        uid = int(uid_raw)
    except (TypeError, ValueError):
        return jsonify({
            "ok": False,
            "code": "UNAUTHORIZED",
            "message": "Token inválido"
        }), 401

    # 👇 Leer digits del query (?digits=3|4)
    try:
        digits = int(request.args.get("digits", "3"))
    except ValueError:
        digits = 3
    if digits not in (3, 4):
        digits = 3

    # 🆕 Guard: exigir PRO y validar plan vs dígitos
    sub_status = get_sub_status(uid)

    if not sub_status.is_premium:
        return jsonify({
            "ok": False,
            "code": "NOT_PREMIUM",
            "message": "Necesitas la suscripción PRO para ver tus selecciones."
        }), 403

    if digits == 4 and (sub_status.max_digits or 0) < 4:
        return jsonify({
            "ok": False,
            "code": "FOUR_DIGITS_NOT_ALLOWED",
            "message": "Tu plan actual solo permite ver/jugar números de 3 cifras."
        }), 403

    # 👇 Pasar digits al service
    res = get_current_selection(uid, digits=digits)

    if res.get("ok"):
        return jsonify({"ok": True, "data": res["data"]}), 200
    if res.get("code") == "NOT_FOUND":
        return jsonify({
            "ok": False,
            "code": "NOT_FOUND",
            "message": "Sin selección previa"
        }), 404
    return jsonify({
        "ok": False,
        "code": "ERROR",
        "message": res.get("message", "Error")
    }), 500

@games_bp.post("/<int:game_id>/announce-winner")
@jwt_required()
def announce_winner(game_id: int):
    body = request.get_json(silent=True) or {}
    try:
        winning_number = int(body.get("winning_number"))
    except Exception:
        return jsonify({"ok": False, "message": "winning_number inválido"}), 400

    ok, msg = games_service.set_winner(game_id=game_id, winning_number=winning_number)
    if not ok:
        return jsonify({"ok": False, "message": msg or "No se pudo cerrar el juego"}), 400

    conn = db.engine.raw_connection()
    try:
        inserted = create_notifications_for_game_winner(conn, game_id, winning_number)
    finally:
        conn.close()

    return jsonify({
        "ok": True,
        "game_id": game_id,
        "winning_number": winning_number,
        "inserted_general": inserted["general"],
        "inserted_personal": inserted["personal"],
    }), 200


@games_bp.get("/history")
@jwt_required(optional=True)
def api_history():
    uid = _resolve_user_id()
    if not uid:
        return jsonify({"error": "No autorizado"}), 403

    # Mismo guard que en el service: fecha + estado
    if not _is_user_pro(int(uid)):
        return jsonify({
            "ok": False,
            "code": "NOT_PREMIUM",
            "message": "El historial es solo para usuarios PRO."
        }), 403

    page = int(request.args.get("page") or 1)
    per_page = int(request.args.get("per_page") or 20)

    conn = db.engine.raw_connection()
    try:
        data = list_user_history(conn, int(uid), page, per_page)
        return jsonify(data), 200
    finally:
        conn.close()
