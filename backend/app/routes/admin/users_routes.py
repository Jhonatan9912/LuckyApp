# app/routes/admin/users_routes.py
from flask import jsonify, request, current_app
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
from app.subscriptions.service import expire_all_stale

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
# GET /api/admin/users/<id>/detail -> datos, referidor y personas referidas
# ---------------------------------------------------------------------
@bp.get("/users/<int:user_id>/detail")
@jwt_required()
def admin_user_detail(user_id):
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if role_id is None:
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": get_jwt_identity()},
        ).scalar()
    if int(role_id) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    u = db.session.execute(text("""
        SELECT u.id, u.name, u.phone, u.email, u.public_code, u.country_code,
               u.created_at, COALESCE(r.role_name, 'Desconocido') AS role
        FROM users u
        LEFT JOIN public.roles r ON r.id = u.role_id
        WHERE u.id = :uid
    """), {"uid": user_id}).mappings().first()
    if not u:
        return jsonify({"ok": False, "error": "Usuario no encontrado"}), 404

    referrer = db.session.execute(text("""
        SELECT ru.id, ru.name, ru.phone, ru.public_code, rf.created_at
        FROM public.referrals rf
        JOIN users ru ON ru.id = rf.referrer_user_id
        WHERE rf.referred_user_id = :uid
        ORDER BY rf.id ASC
        LIMIT 1
    """), {"uid": user_id}).mappings().first()

    referred = db.session.execute(text("""
        SELECT rf.id, ru.id AS user_id, ru.name, ru.phone, ru.public_code,
               rf.status::text AS status, rf.created_at,
               (s.is_premium IS TRUE AND s.expires_at > NOW()) AS has_active_plan
        FROM public.referrals rf
        JOIN users ru ON ru.id = rf.referred_user_id
        LEFT JOIN LATERAL (
            SELECT is_premium, expires_at
            FROM public.user_subscriptions
            WHERE user_id = ru.id
            ORDER BY COALESCE(expires_at, updated_at, created_at) DESC NULLS LAST
            LIMIT 1
        ) s ON TRUE
        WHERE rf.referrer_user_id = :uid
        ORDER BY rf.id DESC
    """), {"uid": user_id}).mappings().all()

    def _row(r):
        # fechas en ISO 8601 para que el front las pueda leer
        return {k: (v.isoformat() if hasattr(v, "isoformat") else v) for k, v in dict(r).items()}

    return jsonify({
        "ok": True,
        "user": _row(u),
        "referred_by": _row(referrer) if referrer else None,
        "referred": [_row(r) for r in referred],
    })


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

    data = request.get_json(silent=True) or {}
    try:
        new_role_id = int(data.get("role_id"))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "role_id es requerido"}), 400

    exists = db.session.execute(
        text("SELECT 1 FROM roles WHERE id=:rid"), {"rid": new_role_id}
    ).scalar()
    if not exists:
        return jsonify({"ok": False, "error": "role_id inválido"}), 400

    # Un admin no puede quitarse su propio rol (evita quedarse sin administradores)
    if str(user_id) == str(get_jwt_identity()) and new_role_id != 1:
        return jsonify({"ok": False, "error": "No puedes quitarte tu propio rol de administrador"}), 400

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


# ---------------------------------------------------------------------
# POST /api/admin/subscriptions/expire-stale
# Expira en lote todas las suscripciones cuya expires_at ya pasó.
# Llamar manualmente desde el admin cuando se detecten activas vencidas.
# ---------------------------------------------------------------------
@bp.post("/subscriptions/expire-stale")
@jwt_required()
def admin_expire_stale():
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"), {"uid": uid}
        ).scalar()
    if int(role_id) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        updated = expire_all_stale()
        return jsonify({"ok": True, "expired": updated})
    except Exception as e:
        current_app.logger.exception("admin route failed")
        return jsonify({"ok": False, "error": "Error interno del servidor"}), 500
