# app/routes/admin/users_routes.py
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from . import bp

from app.services.admin.users_service import (
    list_users,
    update_user_role,
    delete_user,
    UserHasActiveGames,
)

# ---------------------------------------------------------------------
# GET /api/admin/users  -> lista paginada + búsqueda
# ---------------------------------------------------------------------
@bp.get("/users")
@jwt_required()
def admin_users():
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if role_id is None:
        user_id = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": user_id},
        ).scalar()

    if int(role_id) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    q = request.args.get("q")
    page = request.args.get("page", type=int, default=1)
    per_page = request.args.get("per_page", type=int, default=50)

    data = list_users(q=q, page=page, per_page=per_page)

    # ⬇️ DEVUELVE TODOS LOS CAMPOS (incluidos subscription*)
    return jsonify({"ok": True, **data})

# ---------------------------------------------------------------------
# PUT /api/admin/users/<user_id>/role  -> actualizar rol del usuario
# Body: { "role_id": 1|2|3 }
# ---------------------------------------------------------------------
# app/routes/admin/users_routes.py
@bp.patch("/users/<int:user_id>/role")
@jwt_required()
def update_user_role(user_id):
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if role_id is None:
        # fallback: leer desde BD usando el identity del token
        user_id_token = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": user_id_token}
        ).scalar()

    if int(role_id) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    data = request.get_json()
    new_role_id = data.get("role_id")

    if not new_role_id:
        return jsonify({"ok": False, "error": "role_id es requerido"}), 400

    db.session.execute(
        text("UPDATE users SET role_id=:rid WHERE id=:uid"),
        {"rid": new_role_id, "uid": user_id}
    )
    db.session.commit()

    return jsonify({"ok": True, "message": "Rol actualizado correctamente"})

# ---------------------------------------------------------------------
# DELETE /api/admin/users/<user_id>  -> eliminar usuario
# ---------------------------------------------------------------------
@bp.delete("/users/<int:user_id>")
@jwt_required()
def admin_users_delete(user_id: int):
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": uid},
        ).scalar()

    if int(role_id) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        ok = delete_user(user_id)
        if not ok:
            return jsonify({"ok": False, "error": "Usuario no encontrado"}), 404

        return jsonify({"ok": True, "deleted_id": user_id})

    except UserHasActiveGames as e:
        # 409: conflicto lógico de negocio (tiene juegos/balotas asociados)
        return jsonify({
            "ok": False,
            "error": "El usuario tiene juegos o balotas asociados y no puede eliminarse.",
            "details": {
                "game_numbers": e.numbers_count,
                "games": e.games_count,
            }
        }), 409

    except Exception:
        return jsonify({"ok": False, "error": "Error interno al eliminar"}), 500
