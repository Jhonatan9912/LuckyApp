from sqlalchemy import text
from app.db.database import db
from typing import Optional, Dict, Any

class UserHasActiveGames(Exception):
    """El usuario tiene juegos/balotas asociados; no se puede eliminar."""
    def __init__(self, numbers_count: int, games_count: int):
        super().__init__("user_has_active_games")
        self.numbers_count = int(numbers_count or 0)
        self.games_count = int(games_count or 0)

def list_users(q: Optional[str] = None, page: int = 1, per_page: int = 50) -> Dict[str, Any]:
    page = max(1, int(page or 1))
    per_page = max(1, min(100, int(per_page or 50)))
    offset = (page - 1) * per_page

    rows = db.session.execute(text("""
        SELECT
          u.id,
          u.name,
          u.phone,
          u.public_code,
          u.role_id,
          COALESCE(r.role_name, 'Desconocido') AS role
        FROM users u
        LEFT JOIN public.roles r ON r.id = u.role_id
        WHERE (:q IS NULL)
           OR (u.name ILIKE '%' || :q || '%'
            OR u.phone ILIKE '%' || :q || '%'
            OR u.public_code ILIKE '%' || :q || '%'
            OR r.role_name ILIKE '%' || :q || '%')
        ORDER BY u.id DESC
        OFFSET :offset
        LIMIT :limit
    """), {
        "q": q.strip() if q and q.strip() else None,
        "offset": offset,
        "limit": per_page,
    }).mappings().all()

    total = db.session.execute(text("""
        SELECT COUNT(*)
        FROM users u
        LEFT JOIN public.roles r ON r.id = u.role_id
        WHERE (:q IS NULL)
           OR (u.name ILIKE '%' || :q || '%'
            OR u.phone ILIKE '%' || :q || '%'
            OR u.public_code ILIKE '%' || :q || '%'
            OR r.role_name ILIKE '%' || :q || '%')
    """), {"q": q.strip() if q and q.strip() else None}).scalar() or 0

    items = [dict(r) for r in rows]
    return {"items": items, "page": page, "per_page": per_page, "total": int(total)}


# =========================
#  NUEVO: actualizar el rol
# =========================
def update_user_role(user_id: int, new_role_id: int) -> Dict[str, Any]:
    """
    Cambia el rol de un usuario. Valida que el rol exista y que el usuario exista.
    Devuelve un dict con los datos principales del usuario y el nombre del rol.
    Lanza ValueError con mensajes claros si algo falla (para mapear a 4xx en la ruta).
    """
    try:
        # 1) Validar que el rol exista
        role_row = db.session.execute(
            text("SELECT id, role_name FROM public.roles WHERE id = :rid"),
            {"rid": new_role_id}
        ).mappings().first()

        if role_row is None:
            raise ValueError("El rol especificado no existe.")

        # 2) Actualizar al usuario y devolver lo actualizado
        updated = db.session.execute(
            text("""
                UPDATE users
                SET role_id = :rid
                WHERE id = :uid
                RETURNING id, name, phone, public_code, role_id
            """),
            {"uid": user_id, "rid": new_role_id}
        ).mappings().first()

        if updated is None:
            # no existe el usuario
            db.session.rollback()
            raise ValueError("Usuario no encontrado.")

        db.session.commit()

        # 3) Construir payload con el nombre del rol
        return {
            "id": updated["id"],
            "name": updated["name"],
            "phone": updated["phone"],
            "public_code": updated["public_code"],
            "role_id": updated["role_id"],
            "role": role_row["role_name"] or "Desconocido",
        }

    except ValueError:
        # errores de validación se vuelven a lanzar tal cual
        raise
    except Exception as e:
        db.session.rollback()
        # re-lanzamos con mensaje genérico para no filtrar detalles internos
        raise RuntimeError(f"Error al actualizar rol: {e}") from e


# =======================
#  NUEVO: eliminar usuario
# =======================
def delete_user(user_id: int) -> bool:
    """
    Intenta eliminar al usuario.
    - Si el usuario tiene registros en game_numbers (balotas) o es dueño de juegos (games.user_id),
      lanza UserHasActiveGames y NO elimina.
    - Si no existe, devuelve False.
    - Si elimina, devuelve True.
    """
    try:
        # 1) Contar referencias
        numbers_count = db.session.execute(
            text("SELECT COUNT(*) FROM game_numbers WHERE taken_by = :uid"),
            {"uid": user_id},
        ).scalar() or 0

        games_count = db.session.execute(
            text("SELECT COUNT(*) FROM games WHERE user_id = :uid"),
            {"uid": user_id},
        ).scalar() or 0

        if numbers_count > 0 or games_count > 0:
            # No permitir eliminar si tiene “actividad”
            raise UserHasActiveGames(numbers_count, games_count)

        # 2) Eliminar usuario
        row = db.session.execute(
            text("DELETE FROM users WHERE id = :uid RETURNING id"),
            {"uid": user_id},
        ).first()

        if row is None:
            db.session.rollback()
            return False

        db.session.commit()
        return True

    except UserHasActiveGames:
        # Deja pasar la excepción específica (la manejará la ruta)
        db.session.rollback()
        raise
    except Exception as e:
        db.session.rollback()
        raise RuntimeError(f"Error al eliminar usuario: {e}") from e
