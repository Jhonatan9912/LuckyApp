# app/services/admin/games_service.py
from typing import Any, Dict, List, Optional
from app.services.notify.push_sender import send_bulk_push

# ---------- helpers ----------
def _fetch_all_dicts(cur) -> List[dict]:
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]

def _fetch_one_dict(cur) -> Optional[dict]:
    row = cur.fetchone()
    if not row:
        return None
    cols = [c[0] for c in cur.description]
    return dict(zip(cols, row))

_SQL_ONE_GAME = """
SELECT
  g.id                                                     AS id,
  COALESCE(l.name, g.lottery_name)                         AS lottery_name,
  COALESCE(to_char(g.scheduled_date, 'YYYY-MM-DD'), '')    AS played_date,
  COALESCE(to_char(g.scheduled_time, 'HH24:MI'), '')       AS played_time,
  (SELECT COUNT(DISTINCT gn.taken_by)
   FROM public.game_numbers gn
   WHERE gn.game_id = g.id)                                AS players_count,
  g.winning_number                                         AS winning_number,
  g.state_id                                               AS state_id,
  g.digits                                               AS digits
FROM public.games g
LEFT JOIN public.lotteries l ON l.id = g.lottery_id
WHERE g.id = %(id)s
"""

_SQL_LOCKED_BY_TIME_AND_WINNER = """
SELECT
  (g.winning_number IS NOT NULL) AND
  (
    COALESCE(
      g.scheduled_date::timestamp + COALESCE(g.scheduled_time, '00:00'::time),
      g.played_at
    ) < NOW()
  ) AS locked
FROM public.games g
WHERE g.id = %(id)s
FOR UPDATE
"""

# ---------- listados ----------
SQL_LIST_NOQ = """
SELECT
  g.id                                                     AS id,
  COALESCE(l.name, g.lottery_name)                         AS lottery_name,
  COALESCE(to_char(g.scheduled_date, 'YYYY-MM-DD'), '')    AS played_date,
  COALESCE(to_char(g.scheduled_time, 'HH24:MI'), '')       AS played_time,
  COUNT(DISTINCT gn.taken_by)                              AS players_count,
  MAX(g.winning_number)                                    AS winning_number,
  MAX(g.state_id)                                          AS state_id
  MAX(g.digits)                                            AS digits

FROM public.games g
LEFT JOIN public.lotteries     l  ON l.id = g.lottery_id
LEFT JOIN public.game_numbers  gn ON gn.game_id = g.id
GROUP BY
  g.id,
  COALESCE(l.name, g.lottery_name),
  g.scheduled_date,
  g.scheduled_time
ORDER BY COALESCE(
           g.scheduled_date::timestamp
           + COALESCE(g.scheduled_time, '00:00'::time),
           g.played_at
         ) DESC
LIMIT %(limit)s OFFSET %(offset)s
"""

SQL_COUNT_NOQ = """
SELECT COUNT(*) AS total
FROM (
  SELECT g.id
  FROM public.games g
  GROUP BY g.id
) t
"""

SQL_LIST_Q = """
SELECT
  g.id                                                     AS id,
  COALESCE(l.name, g.lottery_name)                         AS lottery_name,
  COALESCE(to_char(g.scheduled_date, 'YYYY-MM-DD'), '')    AS played_date,
  COALESCE(to_char(g.scheduled_time, 'HH24:MI'), '')       AS played_time,
  COUNT(DISTINCT gn.taken_by)                              AS players_count,
  MAX(g.winning_number)                                    AS winning_number,
  MAX(g.state_id)                                          AS state_id
  MAX(g.digits)                                            AS digits

FROM public.games g
LEFT JOIN public.lotteries     l  ON l.id = g.lottery_id
LEFT JOIN public.game_numbers  gn ON gn.game_id = g.id
WHERE CAST(g.id AS TEXT) ILIKE %(like)s
   OR COALESCE(l.name, g.lottery_name) ILIKE %(like)s
   OR EXISTS (
       SELECT 1
       FROM public.game_numbers gn2
       WHERE gn2.game_id = g.id
         AND CAST(gn2.number AS TEXT) ILIKE %(like)s
   )
GROUP BY
  g.id,
  COALESCE(l.name, g.lottery_name),
  g.scheduled_date,
  g.scheduled_time
ORDER BY COALESCE(
           g.scheduled_date::timestamp
           + COALESCE(g.scheduled_time, '00:00'::time),
           g.played_at
         ) DESC
LIMIT %(limit)s OFFSET %(offset)s
"""

SQL_COUNT_Q = """
SELECT COUNT(*) AS total
FROM (
  SELECT g.id
  FROM public.games g
  LEFT JOIN public.lotteries l ON l.id = g.lottery_id
  WHERE CAST(g.id AS TEXT) ILIKE %(like)s
     OR COALESCE(l.name, g.lottery_name) ILIKE %(like)s
     OR EXISTS (
         SELECT 1
         FROM public.game_numbers gn2
         WHERE gn2.game_id = g.id
           AND CAST(gn2.number AS TEXT) ILIKE %(like)s
     )
  GROUP BY g.id
) t
"""

def list_games(conn, q: str, page: int, per_page: int) -> Dict[str, Any]:
    """Lista juegos con cantidad de jugadores por juego."""
    page = max(page, 1)
    per_page = min(max(per_page, 1), 200)
    offset = (page - 1) * per_page

    with conn.cursor() as cur:
        if q:
            params = {"like": f"%{q}%", "limit": per_page, "offset": offset}
            cur.execute(SQL_LIST_Q, params)
            items = _fetch_all_dicts(cur)

            cur.execute(SQL_COUNT_Q, params)
            total = cur.fetchone()[0]
        else:
            params = {"limit": per_page, "offset": offset}
            cur.execute(SQL_LIST_NOQ, params)
            items = _fetch_all_dicts(cur)

            cur.execute(SQL_COUNT_NOQ)
            total = cur.fetchone()[0]

    return {
        "items": items,
        "page": page,
        "per_page": per_page,
        "total": int(total or 0),
    }

# ---------- loterías para el select ----------
def list_lotteries(conn) -> List[Dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id, name
            FROM public.lotteries
            ORDER BY name ASC
        """)
        return _fetch_all_dicts(cur)

def update_game(conn, game_id: int,
                lottery_id: Optional[int],
                scheduled_date: Optional[str],
                scheduled_time: Optional[str],
                winning_number: Optional[int] = None) -> Optional[Dict[str, Any]]:
    
        # --- variables temporales para push post-commit ---
    tokens_to_push = []
    push_title = None
    push_body = None
    push_data = None

    with conn.cursor() as cur:
        # 1) Leer y BLOQUEAR solo la fila de games (sin LEFT JOIN)
        cur.execute("""
            SELECT id, lottery_id, scheduled_date, scheduled_time, winning_number
            FROM public.games
            WHERE id = %(id)s
            FOR UPDATE
        """, {"id": game_id})
        row = cur.fetchone()
        if not row:
            conn.rollback()
            return None

        old_lottery_id = row[1]
        old_date       = row[2]
        old_time       = row[3]
        old_winner     = row[4]

        # 2) Chequear bloqueo por (ganador ya fijado) + (fecha/hora pasada)
        cur.execute(_SQL_LOCKED_BY_TIME_AND_WINNER, {"id": game_id})
        locked = bool(cur.fetchone()[0])
        if locked:
            conn.rollback()
            raise ValueError("GAME_LOCKED")

        # 3) Nuevos valores efectivos (si no mandan, conservar)
        new_lottery_id = lottery_id     if lottery_id     is not None else old_lottery_id
        new_date       = scheduled_date if scheduled_date is not None else old_date
        new_time       = scheduled_time if scheduled_time is not None else old_time
        new_winner     = winning_number if winning_number is not None else old_winner

        # 4) Actualizar
        cur.execute("""
            UPDATE public.games
            SET lottery_id     = %(lottery_id)s,
                scheduled_date = %(scheduled_date)s,
                scheduled_time = %(scheduled_time)s,
                winning_number = %(winning_number)s
            WHERE id = %(id)s
        """, {
            "lottery_id": new_lottery_id,
            "scheduled_date": new_date,
            "scheduled_time": new_time,
            "winning_number": new_winner,
            "id": game_id,
        })

        # 5) Si cambió Lotería/Fecha/Hora y hay fecha+hora -> notificar jugadores
        schedule_changed = (
            new_lottery_id != old_lottery_id or
            new_date != old_date or
            new_time != old_time
        )
        if schedule_changed and new_date is not None and new_time is not None:
            cur.execute("""
                INSERT INTO public.notifications (user_id, title, body, data)
                SELECT DISTINCT
                       gn.taken_by AS user_id,
                       CONCAT('Juego #', g.id, ' programado') AS title,
                       CONCAT(
                           'El administrador ha indicado que se jugará con la lotería ',
                           COALESCE(l.name, g.lottery_name),
                           ' el ', to_char(%(d)s::date, 'YYYY-MM-DD'),
                           ' a las ', to_char(%(t)s::time, 'HH24:MI')
                       ) AS body,
                       jsonb_build_object(
                           'type', 'schedule_set',
                           'game_id', g.id,
                           'lottery', COALESCE(l.name, g.lottery_name),
                           'date', to_char(%(d)s::date, 'YYYY-MM-DD'),
                           'time', to_char(%(t)s::time, 'HH24:MI')
                       ) AS data
                FROM public.games g
                LEFT JOIN public.lotteries l ON l.id = g.lottery_id
                JOIN public.game_numbers gn ON gn.game_id = g.id
                WHERE g.id = %(id)s
                  AND gn.taken_by IS NOT NULL
            """, {"id": game_id, "d": new_date, "t": new_time})

            # --- construir FCM push: tokens + payload (no enviar aún) ---
            # 1) nombre de lotería (resuelto como en el INSERT)
            cur.execute("""
                SELECT COALESCE(l.name, g.lottery_name) AS lottery_name
                FROM public.games g
                LEFT JOIN public.lotteries l ON l.id = g.lottery_id
                WHERE g.id = %(id)s
            """, {"id": game_id})
            row_ln = cur.fetchone()
            lottery_name = row_ln[0] if row_ln else ""

            # 2) user_ids destinatarios (quienes jugaron este game_id)
            cur.execute("""
                SELECT DISTINCT gn.taken_by
                FROM public.game_numbers gn
                WHERE gn.game_id = %(id)s AND gn.taken_by IS NOT NULL
            """, {"id": game_id})
            urows = cur.fetchall()
            user_ids = [int(r[0]) for r in urows] if urows else []

            # 3) tokens
            tokens_to_push = []
            if user_ids:
                cur.execute("""
                    SELECT device_token
                    FROM device_tokens
                    WHERE user_id = ANY(%(uids)s) AND COALESCE(revoked, FALSE) = FALSE
                """, {"uids": user_ids})
                trows = cur.fetchall()
                tokens_to_push = [str(r[0]) for r in trows if r and r[0]]

            # 4) payload del push (title/body/data)
            push_title = f"Juego #{game_id} programado"
            push_body = f"{lottery_name} · {new_date} {new_time}"
            push_data = {
                "type": "schedule_set",
                "screen": "game_detail",     # ajusta si tu app espera otro nombre
                "game_id": game_id,
                "lottery": lottery_name or "",
                "date": new_date,
                "time": new_time,
            }

        # 6) Devolver el juego actualizado
        cur.execute(_SQL_ONE_GAME, {"id": game_id})
        item = _fetch_one_dict(cur)

    conn.commit()

    # --- envío FCM fuera de la transacción ---
    try:
        if tokens_to_push and push_title and push_body:
            send_bulk_push(tokens_to_push, push_title, push_body, data=push_data)
    except Exception:
        # no romper la respuesta si FCM falla
        pass

    return item


# ---------- fijar número ganador + notificar jugadores ----------
def set_winning_number(conn, game_id: int, winning_number: int, admin_user_id: int) -> Optional[Dict[str, Any]]:
    """
    Fija el número ganador del juego y notifica a los jugadores.
    - Valida rango 0..999 (no valida si el número existe en game_numbers).
    - Si ya hay ganador, devuelve error.
    - Actualiza games.winning_number y state_id=2 (Finalizado).
    - Inserta notificaciones a todos los taken_by del juego.
    - Devuelve el juego actualizado para el frontend.
    """
    if winning_number < 0 or winning_number > 999:
        return None

    with conn.cursor() as cur:
        # Tomar lock de la fila; permitimos sobrescribir el ganador si ya existía
        cur.execute("SELECT id FROM public.games WHERE id = %(gid)s FOR UPDATE", {"gid": game_id})
        r = cur.fetchone()
        if not r:
            conn.rollback()
            return None


        # ⚠️ Ya NO comprobamos que el número exista en game_numbers

        # Guardar ganador
        cur.execute("""
            UPDATE public.games
            SET winning_number = %(num)s,
                state_id = 2          -- 2 = Finalizado
            WHERE id = %(gid)s
        """, {"gid": game_id, "num": winning_number})

                # Asegurar que exista un juego abierto y sin ganador
        cur.execute("""
            WITH existing AS (
                SELECT id
                FROM public.games
                WHERE state_id = 1
                  AND winning_number IS NULL
                ORDER BY id DESC
                LIMIT 1
            )
            INSERT INTO public.games (state_id, played_at)
            SELECT 1, NOW()
            WHERE NOT EXISTS (SELECT 1 FROM existing)
        """)

        if cur.rowcount == 0:
            conn.rollback()
            return None

        # Notificar a todos los jugadores de ese juego (aunque nadie haya jugado ese número)
        cur.execute("""
            INSERT INTO public.notifications (user_id, title, body, data)
            SELECT DISTINCT
                   gn.taken_by AS user_id,
                   CONCAT('Resultado del juego #', g.id) AS title,
                   CONCAT('El número ganador es ', %(num)s) AS body,
                   jsonb_build_object(
                       'type', 'winner_announced',
                       'game_id', g.id,
                       'winning_number', %(num)s,
                       'played_at', to_char(
                            COALESCE(
                                g.scheduled_date::timestamp
                                + COALESCE(g.scheduled_time, '00:00'::time),
                                g.played_at
                            ),
                            'YYYY-MM-DD"T"HH24:MI:SSOF'
                            )
                   ) AS data
            FROM public.game_numbers gn
            JOIN public.games g ON g.id = gn.game_id
            WHERE gn.game_id = %(gid)s
              AND gn.taken_by IS NOT NULL
        """, {"gid": game_id, "num": winning_number})

        # Devolver el juego actualizado
        cur.execute(_SQL_ONE_GAME, {"id": game_id})
        item = _fetch_one_dict(cur)

    conn.commit()
    return item

# ---------- eliminar ----------
def delete_game(conn, game_id: int) -> int:
    with conn.cursor() as cur:
        cur.execute("DELETE FROM public.games WHERE id = %(id)s", {"id": game_id})
        deleted = cur.rowcount
    conn.commit()
    return deleted

def peek_latest_schedule_notice(conn, user_id: int) -> Optional[Dict[str, Any]]:
    """
    Devuelve la última notificación 'schedule_set' NO leída del usuario.
    NO la marca como leída. Retorna None si no hay nada.
    """
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id, title, body, data::json
            FROM public.notifications
            WHERE user_id = %(uid)s
              AND read_at IS NULL
              AND COALESCE(data->>'type','') = 'schedule_set'
            ORDER BY created_at DESC
            LIMIT 1
        """, {"uid": user_id})
        row = cur.fetchone()

    # No commit: solo lectura
    if not row:
        return None

    return {"id": row[0], "title": row[1], "body": row[2], "data": row[3]}

def mark_notifications_read(conn, user_id: int, ids: List[int]) -> int:
    """
    Marca como leídas (read_at = NOW()) las notificaciones del usuario cuyos IDs se pasen.
    Devuelve cuántas filas se actualizaron.
    """
    if not ids:
        return 0

    with conn.cursor() as cur:
        cur.execute("""
            UPDATE public.notifications
               SET read_at = NOW()
             WHERE user_id = %(uid)s
               AND id = ANY(%(ids)s)
               AND read_at IS NULL
        """, {"uid": user_id, "ids": ids})
        updated = cur.rowcount

    conn.commit()
    return updated
