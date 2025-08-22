from typing import Any, Dict, List

def _fetch_all_dicts(cur) -> List[dict]:
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]

def list_notifications(conn, user_id: int, unread_only: bool, page: int, per_page: int) -> Dict[str, Any]:
    page = max(page, 1)
    per_page = min(max(per_page, 1), 200)
    offset = (page - 1) * per_page

    with conn.cursor() as cur:
        where = "WHERE user_id = %(uid)s"
        if unread_only:
            where += " AND read_at IS NULL"

        cur.execute(f"""
            SELECT
                id,
                title,
                body,
                data,
                data->>'type'                  AS type,
                (data->>'game_id')::int        AS game_id,
                (data->>'winning_number')::int AS winning_number,
                to_char(created_at,'YYYY-MM-DD HH24:MI:SS') AS created_at,
                read_at IS NOT NULL            AS read
            FROM public.notifications
            {where}
            ORDER BY created_at DESC
            LIMIT %(limit)s OFFSET %(offset)s
        """, {"uid": user_id, "limit": per_page, "offset": offset})
        items = _fetch_all_dicts(cur)

        cur.execute(f"SELECT COUNT(*) FROM public.notifications {where}", {"uid": user_id})
        total = int(cur.fetchone()[0] or 0)

    return {"items": items, "page": page, "per_page": per_page, "total": total}

def mark_as_read(conn, user_id: int, ids: List[int]) -> int:
    if not ids:
        return 0
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE public.notifications
               SET read_at = now()
             WHERE user_id = %(uid)s AND id = ANY(%(ids)s) AND read_at IS NULL
        """, {"uid": user_id, "ids": ids})
        n = cur.rowcount
    conn.commit()
    return n

def mark_all_as_read(conn, user_id: int) -> int:
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE public.notifications
               SET read_at = now()
             WHERE user_id = %(uid)s AND read_at IS NULL
        """, {"uid": user_id})
        n = cur.rowcount
    conn.commit()
    return n

def create_notification(conn, user_id: int, title: str, body: str, data: Dict[str, Any]) -> int:
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO public.notifications (user_id, title, body, data)
            VALUES (%(uid)s, %(title)s, %(body)s, %(data)s)
            RETURNING id
        """, {"uid": user_id, "title": title, "body": body, "data": data})
        nid = int(cur.fetchone()[0])
    conn.commit()
    return nid

def create_notifications_for_game_winner(conn, game_id: int, winning_number: int) -> dict:
    """
    Inserta:
      - General (winner_announced) para todos los que participaron EXCEPTO el/los ganador(es)
      - Personal (you_won) para el/los ganador(es)
    Devuelve {'general': N, 'personal': M}
    """
    out = {"general": 0, "personal": 0}
    with conn.cursor() as cur:
        # 1) Ganadores del juego
        cur.execute("""
            WITH winners AS (
            SELECT DISTINCT taken_by AS user_id
            FROM public.game_numbers
            WHERE game_id = %(gid)s
                AND LPAD(CAST(number AS TEXT), 3, '0') = LPAD(CAST(%(num)s AS TEXT), 3, '0')
                AND taken_by IS NOT NULL
            )

            INSERT INTO public.notifications (user_id, title, body, data)
            SELECT DISTINCT
                gn.taken_by AS user_id,
                CONCAT('¡Ganaste el juego #', g.id, '!') AS title,
                CONCAT('Ganaste con el número ', LPAD(CAST(%(num)s AS TEXT), 3, '0')) AS body,
                jsonb_build_object(
                    'type', 'you_won',
                    'game_id', g.id,
                    'winning_number', %(num)s
                ) AS data
            FROM public.game_numbers gn
            JOIN public.games g ON g.id = gn.game_id
            WHERE gn.game_id = %(gid)s
            AND gn.taken_by IS NOT NULL
            AND LPAD(CAST(gn.number AS TEXT), 3, '0') = LPAD(CAST(%(num)s AS TEXT), 3, '0')

        """, {"gid": game_id, "num": winning_number})
        out["general"] = cur.rowcount

        # 2) Personal SOLO para ganadores
        cur.execute("""
            INSERT INTO public.notifications (user_id, title, body, data)
            SELECT DISTINCT
                   gn.taken_by AS user_id,
                   CONCAT('¡Ganaste el juego #', g.id, '!') AS title,
                   CONCAT('Ganaste con el número ', LPAD(CAST(%(num)s AS TEXT), 3, '0')) AS body,
                   jsonb_build_object(
                       'type', 'you_won',
                       'game_id', g.id,
                       'winning_number', %(num)s
                   ) AS data
            FROM public.game_numbers gn
            JOIN public.games g ON g.id = gn.game_id
           WHERE gn.game_id = %(gid)s
             AND gn.taken_by IS NOT NULL
             AND gn.number = %(num)s;   -- 👈 solo el/los ganador(es)
        """, {"gid": game_id, "num": winning_number})
        out["personal"] = cur.rowcount

    conn.commit()
    return out

def create_notifications_for_personal_winners(conn, game_id: int, winning_number: int) -> int:
    """
    Crea notificaciones SOLO para los usuarios que realmente sacaron el número ganador.
    """
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO public.notifications (user_id, title, body, data)
            SELECT
                gn.taken_by AS user_id,
                CONCAT('¡Ganaste el juego #', g.id, '!') AS title,
                CONCAT('Tu número ganador es ', LPAD(CAST(%(num)s AS TEXT), 3, '0')) AS body,
                jsonb_build_object(
                    'type', 'you_won',
                    'game_id', g.id,
                    'winning_number', %(num)s
                ) AS data
            FROM public.game_numbers gn
            JOIN public.games g ON g.id = gn.game_id
            WHERE gn.game_id = %(gid)s
              AND gn.taken_by IS NOT NULL
              AND gn.number = %(num)s
        """, {"gid": game_id, "num": winning_number})
        n = cur.rowcount
    conn.commit()
    return n

