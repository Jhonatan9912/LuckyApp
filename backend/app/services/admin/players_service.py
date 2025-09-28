# app/services/admin/players_service.py
from typing import Any, Dict, List, Literal
from sqlalchemy import text
from app.db.database import db

State = Literal["active", "historical", "all"]

def list_players(q: str, page: int, per_page: int, state: State = "active") -> Dict[str, Any]:
    """
    Devuelve una fila por (player=taken_by, game_id) con:
    player_name, code, game_id, lottery_name, played_date, played_time, numbers (array).

    - state="active":    juegos SIN número ganador (g.winning_number IS NULL)
    - state="historical":juegos CON número ganador (g.winning_number IS NOT NULL)
    - state="all":       todos
    """
    page = max(page, 1)
    per_page = min(max(per_page, 1), 200)
    offset = (page - 1) * per_page

    # 👇 Usar state_id: 1 = activo, 2 = cerrado
    state_where = ""
    if state == "active":
        state_where = "AND COALESCE(g.state_id, 1) = 1"
    elif state == "historical":
        state_where = "AND COALESCE(g.state_id, 1) = 2"
    # state == "all" => sin filtro extra


    base_list_noq = text(f"""
        SELECT
          u.id                                  AS user_id,
          u.name                                AS player_name,
          u.public_code                         AS code,
          g.id                                  AS game_id,
          COALESCE(l.name, g.lottery_name)      AS lottery_name,
          to_char(g.played_at, 'YYYY-MM-DD')    AS played_date,
          to_char(g.played_at, 'HH24:MI')       AS played_time,
          ARRAY_AGG(gn.number ORDER BY gn.position) AS numbers
        FROM public.game_numbers gn
        JOIN public.games      g  ON g.id = gn.game_id
        LEFT JOIN public.lotteries l ON l.id = g.lottery_id
        JOIN public.users      u  ON u.id = gn.taken_by
        WHERE 1=1
          {state_where}
        GROUP BY
          u.id, u.name, u.public_code,
          g.id, COALESCE(l.name, g.lottery_name),
          to_char(g.played_at, 'YYYY-MM-DD'),
          to_char(g.played_at, 'HH24:MI')
        ORDER BY g.played_at DESC, g.id DESC
        LIMIT :limit OFFSET :offset
    """)

    base_count_noq = text(f"""
        SELECT COUNT(*) AS total
        FROM (
          SELECT u.id, g.id
          FROM public.game_numbers gn
          JOIN public.games g ON g.id = gn.game_id
          JOIN public.users u ON u.id = gn.taken_by
          WHERE 1=1
            {state_where}
          GROUP BY u.id, g.id
        ) t
    """)

    base_list_q = text(f"""
        SELECT
          u.id                                  AS user_id,
          u.name                                AS player_name,
          u.public_code                         AS code,
          g.id                                  AS game_id,
          COALESCE(l.name, g.lottery_name)      AS lottery_name,
          to_char(g.played_at, 'YYYY-MM-DD')    AS played_date,
          to_char(g.played_at, 'HH24:MI')       AS played_time,
          ARRAY_AGG(gn.number ORDER BY gn.position) AS numbers
        FROM public.game_numbers gn
        JOIN public.games      g  ON g.id = gn.game_id
        LEFT JOIN public.lotteries l ON l.id = g.lottery_id
        JOIN public.users      u  ON u.id = gn.taken_by
        WHERE
              ( CAST(u.id AS TEXT) ILIKE :like
             OR u.name ILIKE :like
             OR u.public_code ILIKE :like
             OR CAST(g.id AS TEXT) ILIKE :like
             OR COALESCE(l.name, g.lottery_name) ILIKE :like
             OR EXISTS (
                 SELECT 1
                 FROM public.game_numbers gn2
                 WHERE gn2.game_id = g.id
                   AND gn2.taken_by = u.id
                   AND CAST(gn2.number AS TEXT) ILIKE :like
             ))
          {state_where}
        GROUP BY
          u.id, u.name, u.public_code,
          g.id, COALESCE(l.name, g.lottery_name),
          to_char(g.played_at, 'YYYY-MM-DD'),
          to_char(g.played_at, 'HH24:MI')
        ORDER BY g.played_at DESC, g.id DESC
        LIMIT :limit OFFSET :offset
    """)

    base_count_q = text(f"""
        SELECT COUNT(*) AS total
        FROM (
          SELECT u.id, g.id
          FROM public.game_numbers gn
          JOIN public.games g ON g.id = gn.game_id
          JOIN public.users u ON u.id = gn.taken_by
          LEFT JOIN public.lotteries l ON l.id = g.lottery_id
          WHERE
                ( CAST(u.id AS TEXT) ILIKE :like
               OR u.name ILIKE :like
               OR u.public_code ILIKE :like
               OR CAST(g.id AS TEXT) ILIKE :like
               OR COALESCE(l.name, g.lottery_name) ILIKE :like
               OR EXISTS (
                   SELECT 1
                   FROM public.game_numbers gn2
                   WHERE gn2.game_id = g.id
                     AND gn2.taken_by = u.id
                     AND CAST(gn2.number AS TEXT) ILIKE :like
               ))
            {state_where}
          GROUP BY u.id, g.id
        ) t
    """)

    if q:
        params = {"like": f"%{q}%", "limit": per_page, "offset": offset}
        rows = db.session.execute(base_list_q, params).mappings().all()
        total = db.session.execute(base_count_q, params).scalar() or 0
    else:
        params = {"limit": per_page, "offset": offset}
        rows = db.session.execute(base_list_noq, params).mappings().all()
        total = db.session.execute(base_count_noq, params).scalar() or 0

    items: List[Dict[str, Any]] = []
    for r in rows:
        m = dict(r)
        nums = m.get("numbers") or []
        if isinstance(nums, list):
            nums = [int(x) if str(x).isdigit() else x for x in nums]
        items.append({
            "user_id": m["user_id"],
            "player_name": m["player_name"] or "",
            "code": m["code"] or "",
            "game_id": m["game_id"],
            "lottery_name": m["lottery_name"] or "",
            "played_date": m["played_date"] or "",
            "played_time": m["played_time"] or "",
            "numbers": nums,
        })

    return {"items": items, "page": page, "per_page": per_page, "total": int(total)}

def delete_player_numbers(game_id: int, user_id: int) -> int:
    """
    Elimina todas las balotas (rows) del jugador 'user_id' en el juego 'game_id'.
    Bloquea si el juego ya alcanzó su fecha/hora (played_at <= NOW()).
    Retorna la cantidad eliminada.
    """
    # 🔒 Bloqueo por fecha/hora del juego
    is_locked = db.session.execute(
        text("SELECT (played_at <= NOW()) FROM games WHERE id = :gid"),
        {"gid": game_id},
    ).scalar()
    if is_locked is None:
        raise ValueError("Juego no existe.")
    if is_locked:
        raise GameLocked()

    try:
        res = db.session.execute(
            text("""
                DELETE FROM game_numbers
                WHERE game_id = :gid
                  AND taken_by = :uid
            """),
            {"gid": game_id, "uid": user_id},
        )
        db.session.commit()
        return res.rowcount or 0
    except Exception:
        db.session.rollback()
        raise


class NumbersConflict(Exception):
    def __init__(self, numbers: List[int]):
        super().__init__("numbers_conflict")
        self.numbers = numbers

class GameLocked(Exception):
    """El juego ya alcanzó su fecha/hora; no se permiten cambios."""
    pass

def update_player_numbers(game_id: int, user_id: int, numbers: List[str]) -> List[int]:
    """
    Actualiza las balotas del jugador (user_id) en el juego (game_id).
    - Valida formato (000–999).
    - Valida duplicados en el payload.
    - Valida que no estén tomadas por OTRO jugador.
    - Bloquea si el juego ya llegó a su fecha/hora (played_at <= NOW()).
    - Reemplaza (delete + insert) de forma transaccional.
    Retorna la lista final (int) guardada.
    """
    # --- Normaliza + valida rango/duplicados ---
    ints: List[int] = []
    for n in numbers or []:
        s = str(n).strip()
        if not s.isdigit() or len(s) > 3:
            raise ValueError("Cada balota debe ser numérica de 3 dígitos (000–999).")
        v = int(s)
        if v < 0 or v > 999:
            raise ValueError("Cada balota debe estar entre 000 y 999.")
        ints.append(v)
    if not ints:
        raise ValueError("Debes enviar al menos una balota.")
    if len(set(ints)) != len(ints):
        raise ValueError("No puedes repetir balotas en la edición.")

    # --- 🔒 Bloqueo por fecha/hora del juego ---
    is_locked = db.session.execute(
        text("SELECT (played_at <= NOW()) FROM games WHERE id = :gid"),
        {"gid": game_id},
    ).scalar()
    if is_locked is None:
        raise ValueError("Juego no existe.")
    if is_locked:
        raise GameLocked()

    # --- ¿Alguna balota ya está tomada por otro jugador? ---
    taken = db.session.execute(
        text("""
            SELECT number
            FROM game_numbers
            WHERE game_id = :gid
              AND taken_by <> :uid
              AND number = ANY(:nums)
        """),
        {"gid": game_id, "uid": user_id, "nums": ints},
    ).scalars().all()
    if taken:
        raise NumbersConflict(list(map(int, taken)))

    # --- Reemplazo atómico ---
    try:
        db.session.execute(
            text("DELETE FROM game_numbers WHERE game_id = :gid AND taken_by = :uid"),
            {"gid": game_id, "uid": user_id},
        )
        for pos, num in enumerate(ints, start=1):
            db.session.execute(
                text("""
                    INSERT INTO game_numbers (game_id, taken_by, position, number, taken_at)
                    VALUES (:gid, :uid, :pos, :num, NOW())
                """),
                {"gid": game_id, "uid": user_id, "pos": pos, "num": num},
            )
        db.session.commit()
        return ints
    except Exception:
        db.session.rollback()
        raise