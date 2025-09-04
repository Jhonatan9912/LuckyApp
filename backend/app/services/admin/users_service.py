# app/services/admin/users_service.py
from typing import Optional, Dict, Any
from sqlalchemy import text, bindparam, Integer, String
from app.db.database import db

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
    q_norm = q.strip() if q and q.strip() else None

    def _query_with_subs(where_sql: str = "", params: Dict[str, Any] = {}):
        sql = f"""
                SELECT
                u.id,
                u.name,
                u.phone,
                u.public_code,
                u.role_id,
                COALESCE(r.role_name, 'Desconocido') AS role,

                -- datos crudos de suscripción (última fila por usuario)
                sub.entitlement                     AS subscription_entitlement,
                UPPER(COALESCE(sub.status,'NONE'))  AS subscription_status,
                COALESCE(sub.is_premium, FALSE)     AS subscription_is_active,
                sub.expires_at                      AS subscription_expires_at,

                -- etiqueta amigable que espera el front (campo "subscription")
                CASE
                    WHEN sub.entitlement IS NULL THEN 'Sin suscripción'  -- o 'Sin suscripción'
                    WHEN sub.is_premium THEN
                    'PRO (vence ' || TO_CHAR(sub.expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') || ')'
                    ELSE
                    UPPER(COALESCE(sub.status,'NONE'))
                    || COALESCE(' (vence ' || TO_CHAR(sub.expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') || ')','')
                END AS subscription

                FROM users u
                LEFT JOIN public.roles r ON r.id = u.role_id
                LEFT JOIN LATERAL (
                SELECT s.entitlement, s.status, s.is_premium, s.expires_at
                FROM public.user_subscriptions s
                WHERE s.user_id = u.id
                ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at) DESC NULLS LAST
                LIMIT 1
                ) sub ON TRUE
        {where_sql}
        ORDER BY u.id DESC
        OFFSET :offset
        LIMIT :limit
        """
        stmt = text(sql).bindparams(
            *( [bindparam("q_like", type_=String)] if ":q_like" in sql else [] ),
            bindparam("offset", type_=Integer),
            bindparam("limit", type_=Integer),
        )
        rows = db.session.execute(
            stmt, {**params, "offset": (page - 1) * per_page, "limit": per_page}
        ).mappings().all()

        total_sql = """
        SELECT COUNT(*)::bigint
        FROM users u
        LEFT JOIN public.roles r ON r.id = u.role_id
        {where_sql}
        """.format(where_sql=where_sql.replace(
            "OFFSET :offset\n          LIMIT :limit", ""))

        total_stmt = text(total_sql).bindparams(
            *( [bindparam("q_like", type_=String)] if ":q_like" in where_sql else [] )
        )
        total = db.session.execute(total_stmt, params).scalar() or 0

        return rows, total

    # --- Fallback si (en otro entorno) la tabla no existe ---
    def _query_without_subs(where_sql: str = "", params: Dict[str, Any] = {}):
        sql = f"""
          SELECT
            u.id,
            u.name,
            u.phone,
            u.public_code,
            u.role_id,
            COALESCE(r.role_name, 'Desconocido') AS role,

            NULL::text        AS subscription_entitlement,
            'NONE'::text      AS subscription_status,
            FALSE::boolean    AS subscription_is_active,
            NULL::timestamptz AS subscription_expires_at,
            'FREE'::text      AS subscription_label

          FROM users u
          LEFT JOIN public.roles r ON r.id = u.role_id
          {where_sql}
          ORDER BY u.id DESC
          OFFSET :offset
          LIMIT :limit
        """
        stmt = text(sql).bindparams(
            *( [bindparam("q_like", type_=String)] if ":q_like" in sql else [] ),
            bindparam("offset", type_=Integer),
            bindparam("limit", type_=Integer),
        )
        rows = db.session.execute(
            stmt, {**params, "offset": (page - 1) * per_page, "limit": per_page}
        ).mappings().all()
        total = db.session.execute(text("""
          SELECT COUNT(*)::bigint
          FROM users u
          LEFT JOIN public.roles r ON r.id = u.role_id
          {where_sql}
        """.format(where_sql=where_sql.replace(
            "OFFSET :offset\n          LIMIT :limit", ""))).bindparams(
            *( [bindparam("q_like", type_=String)] if ":q_like" in where_sql else [] )
        ), params).scalar() or 0
        return rows, total

    # WHERE
    if not q_norm:
        where_sql, params = "", {}
    else:
        where_sql, params = """
          WHERE (u.name ILIKE :q_like
             OR  u.phone ILIKE :q_like
             OR  u.public_code ILIKE :q_like
             OR  r.role_name ILIKE :q_like)
        """, {"q_like": f"%{q_norm}%"}

    # Ejecuta con JOIN real; si falla por UndefinedTable, cae al fallback
    try:
        rows, total = _query_with_subs(where_sql, params)
    except Exception as e:
        if "UndefinedTable" in str(type(e)) or "relation" in str(e).lower():
            rows, total = _query_without_subs(where_sql, params)
        else:
            raise

    items = [dict(r) for r in rows]
    return {"items": items, "page": page, "per_page": per_page, "total": int(total)}

def update_user_role(user_id: int, new_role_id: int) -> Dict[str, Any]:
    try:
        role_row = db.session.execute(
            text("SELECT id, role_name FROM public.roles WHERE id = :rid")
            .bindparams(bindparam("rid", type_=Integer)),
            {"rid": new_role_id}
        ).mappings().first()
        if role_row is None:
            raise ValueError("El rol especificado no existe.")

        updated = db.session.execute(
            text("""
                UPDATE users
                   SET role_id = :rid
                 WHERE id = :uid
             RETURNING id, name, phone, public_code, role_id
            """).bindparams(
                bindparam("rid", type_=Integer),
                bindparam("uid", type_=Integer),
            ),
            {"uid": user_id, "rid": new_role_id}
        ).mappings().first()

        if updated is None:
            db.session.rollback()
            raise ValueError("Usuario no encontrado.")

        db.session.commit()
        return {
            "id": updated["id"],
            "name": updated["name"],
            "phone": updated["phone"],
            "public_code": updated["public_code"],
            "role_id": updated["role_id"],
            "role": role_row["role_name"] or "Desconocido",
        }
    except ValueError:
        raise
    except Exception as e:
        db.session.rollback()
        raise RuntimeError(f"Error al actualizar rol: {e}") from e

def delete_user(user_id: int) -> bool:
    try:
        numbers_count = db.session.execute(
            text("SELECT COUNT(*) FROM game_numbers WHERE taken_by = :uid")
            .bindparams(bindparam("uid", type_=Integer)),
            {"uid": user_id},
        ).scalar() or 0

        games_count = db.session.execute(
            text("SELECT COUNT(*) FROM games WHERE user_id = :uid")
            .bindparams(bindparam("uid", type_=Integer)),
            {"uid": user_id},
        ).scalar() or 0

        if numbers_count > 0 or games_count > 0:
            raise UserHasActiveGames(numbers_count, games_count)

        row = db.session.execute(
            text("DELETE FROM users WHERE id = :uid RETURNING id")
            .bindparams(bindparam("uid", type_=Integer)),
            {"uid": user_id},
        ).first()

        if row is None:
            db.session.rollback()
            return False

        db.session.commit()
        return True
    except UserHasActiveGames:
        db.session.rollback()
        raise
    except Exception as e:
        db.session.rollback()
        raise RuntimeError(f"Error al eliminar usuario: {e}") from e
