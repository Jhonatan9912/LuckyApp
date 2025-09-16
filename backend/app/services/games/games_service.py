# backend/app/services/games/games_service.py
from typing import List, Tuple
from sqlalchemy import text
from app.db.database import db
from app.models.game_models import Game
from app.subscriptions.models import UserSubscription
from sqlalchemy import or_
from datetime import datetime, timezone
import random
from app.services.notify.push_sender import send_bulk_push

def _is_user_pro(user_id: int) -> bool:
    """
    True si el usuario tiene acceso PRO vigente:
      - current_period_end > ahora (UTC)
      - status en estados que permiten acceso (active, canceled, grace, on_hold, paused)
    No depende de la columna is_active (evita quedarnos pegados).
    """
    try:
        sub = (
            UserSubscription.query
            .filter_by(user_id=int(user_id), entitlement="pro")
            .first()
        )
        if not sub:
            return False

        end = getattr(sub, "current_period_end", None)
        if end is None:
            return False

        # normaliza a aware UTC
        if getattr(end, "tzinfo", None) is None:
            end = end.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)

        period_active = end > now
        status = (getattr(sub, "status", "") or "").lower()

        return period_active and status in ("active", "canceled", "grace", "on_hold", "paused")
    except Exception:
        return False
def _generate_preview_numbers(k: int = 5) -> list[int]:
    # Solo para mostrar algo en pantalla; NO toca DB
    return random.sample(range(0, 1000), k)

def find_active_unscheduled_game_id() -> int | None:
    """
    Devuelve el id del ÚLTIMO juego abierto sin ganador (si existe).
    NO crea nada.
    """
    row = db.session.execute(text("""
        SELECT id
        FROM games
        WHERE state_id = 1
          AND winning_number IS NULL
        ORDER BY id DESC
        LIMIT 1
    """)).first()
    return int(row[0]) if row else None

def _count_user_numbers_in_game(user_id: int, game_id: int) -> int:
    return int(db.session.execute(text("""
        SELECT COUNT(*)
        FROM game_numbers
        WHERE game_id = :gid
          AND taken_by = :uid
    """), {"gid": game_id, "uid": user_id}).scalar() or 0)

def get_current_open_game_id() -> int | None:
    row = db.session.execute(text("""
        SELECT id
        FROM games
        WHERE state_id = 1
          AND winning_number IS NULL
        ORDER BY id DESC
        LIMIT 1
    """)).first()
    return int(row[0]) if row else None

def get_current_selection(user_id: int) -> dict:
    """
    Devuelve la selección del usuario en el juego ABIERTO actual.
    Si no hay 5 números, retorna NOT_FOUND.
    """
    gid = get_current_open_game_id()
    if gid is None:
        return {"ok": False, "code": "NOT_FOUND", "message": "No hay juego abierto."}

    rows = db.session.execute(text("""
        SELECT number
        FROM game_numbers
        WHERE game_id = :gid AND taken_by = :uid
        ORDER BY position ASC
    """), {"gid": gid, "uid": user_id}).fetchall()

    nums = [int(r[0]) for r in rows]
    if len(nums) < 5:
        return {"ok": False, "code": "NOT_FOUND", "message": "Sin selección en juego abierto."}

    return {"ok": True, "data": {"game_id": gid, "numbers": nums, "user_id_used": user_id}}

# ===== Utilidades =====
def get_or_create_active_unscheduled_game_id() -> int:
    """
    Usa/crea el ÚNICO juego ABIERTO sin ganador.
    (state_id = 1 y winning_number IS NULL). La programación (lotería/fecha/hora)
    NO importa: se puede seguir llenando hasta 1000 o hasta que haya ganador.
    """
    row = db.session.execute(text("""
        SELECT id
        FROM games
        WHERE state_id = 1
          AND winning_number IS NULL
        ORDER BY id DESC
        LIMIT 1
        FOR UPDATE
    """)).first()

    if row:
        return int(row[0])

    new_id = db.session.execute(text("""
        INSERT INTO games (state_id, played_at)
        VALUES (1, NOW())
        RETURNING id
    """)).scalar()

    return int(new_id)


def _get_or_create_current_game(user_id: int | None, avoid_game_id: int | None = None) -> int:
    """
    Devuelve el id del juego actual (último ABIERTO: sin winning_number y state_id != 2)
    y con cupo (<1000). Si no existe, crea uno nuevo.
    """
    params = {}
    where = "WHERE winning_number IS NULL AND (state_id IS NULL OR state_id <> 2)"
    if avoid_game_id:
        where += " AND id <> :avoid"
        params["avoid"] = avoid_game_id

    last_id = db.session.execute(text(f"""
        SELECT id
        FROM games
        {where}
        ORDER BY id DESC
        LIMIT 1
    """), params).scalar()

    if last_id is not None:
        used = db.session.execute(text("""
            SELECT COUNT(*) FROM game_numbers WHERE game_id = :gid
        """), {"gid": last_id}).scalar()
        if used < 1000:
            return last_id

    # No hay juego abierto con cupo -> crea uno nuevo (estado abierto)
    g = Game(user_id=user_id, state_id=1)
    db.session.add(g)
    db.session.flush()  # obtiene g.id sin commit
    return g.id


def generate_five_available(user_id: int | None, avoid_game_id: int | None = None) -> Tuple[int | None, List[int]]:
    """
    - PRO: usa/crea el juego abierto sin programar y trae 5 libres de ese juego.
    - NO PRO: NO crea juegos. Si hay juego abierto, muestra 5 libres de ese juego.
              Si no hay juego abierto, devuelve un PREVIEW (números random) y game_id=None.
    """
    # ---- Usuario NO PRO: no crear juegos ----
    if not user_id or not _is_user_pro(int(user_id)):
        gid = find_active_unscheduled_game_id()
        if gid is None:
            # No hay juego abierto -> devolvemos preview sin tocar DB
            return None, _generate_preview_numbers()
        # Hay juego abierto -> mostramos 5 disponibles de ese juego (sin reservar)
        rows = db.session.execute(text("""
            WITH taken AS (
                SELECT number FROM game_numbers WHERE game_id = :gid
            )
            SELECT n AS number
            FROM generate_series(0, 999) n
            WHERE NOT EXISTS (SELECT 1 FROM taken t WHERE t.number = n)
            ORDER BY random()
            LIMIT 5;
        """), {"gid": gid}).fetchall()
        numbers = [int(r[0]) for r in rows]
        # Si por cualquier razón hay menos de 5, completamos con preview local
        if len(numbers) < 5:
            faltan = 5 - len(numbers)
            extra = [n for n in _generate_preview_numbers(5 + faltan) if n not in numbers][:faltan]
            numbers += extra
        return gid, numbers

    # ---- Usuario PRO: comportamiento original (puede crear) ----
    gid = get_or_create_active_unscheduled_game_id()
    # Si ya tiene 5 en este juego, devuelve esos mismos 5 (no generes otros)
    existing = db.session.execute(text("""
        SELECT number
        FROM game_numbers
        WHERE game_id = :gid AND taken_by = :uid
        ORDER BY position ASC
    """), {"gid": gid, "uid": int(user_id)}).fetchall()

    if existing and len(existing) >= 5:
        numbers = [int(r[0]) for r in existing[:5]]
        return gid, numbers

    rows = db.session.execute(text("""
        WITH taken AS (
            SELECT number FROM game_numbers WHERE game_id = :gid
        )
        SELECT n AS number
        FROM generate_series(0, 999) n
        WHERE NOT EXISTS (SELECT 1 FROM taken t WHERE t.number = n)
        ORDER BY random()
        LIMIT 5;
    """), {"gid": gid}).fetchall()

    numbers = [int(r[0]) for r in rows]
    return gid, numbers


def commit_selection(user_id: int, game_id: int, numbers: List[int]) -> dict:
    """
    Intenta guardar exactamente 5 números para el juego dado.
    - Si otro jugador tomó alguno, devuelve conflicto.
    - Si el juego cambió (se llenó en el camino), obliga a volver a jugar.
    """
    # Sanitizar entrada
    if len(numbers) != 5:
        return {"ok": False, "error": "Debes enviar exactamente 5 números."}
    if len(set(numbers)) != 5:
        return {"ok": False, "error": "Los 5 números deben ser distintos."}
    if any((n < 0 or n > 999) for n in numbers):
        return {"ok": False, "error": "Cada número debe estar entre 0 y 999."}
    # --- PREMIUM guard: solo PRO pueden reservar ---
    if not _is_user_pro(user_id):
        return {
            "ok": False,
            "code": "NOT_PREMIUM",
            "error": "Necesitas la suscripción PRO para reservar."
        }

    # --- BLOQUE NUEVO: no permitir confirmar en juegos cerrados, con ganador o programados ---
    row = db.session.execute(text("""
        SELECT
            winning_number,
            state_id,
            (SELECT COUNT(*) FROM game_numbers WHERE game_id = :gid) AS used,
            lottery_id,
            lottery_name,
            scheduled_date,
            scheduled_time
        FROM games
        WHERE id = :gid
    """), {"gid": game_id}).fetchone()

    if row is None:
        db.session.rollback()
        return {"ok": False, "code": "NOT_FOUND", "error": "Juego inexistente."}

    winning_number, state_id, used = row[0], row[1], int(row[2])
    lottery_id, lottery_name, scheduled_date, scheduled_time = row[3], row[4], row[5], row[6]

    # 1) Cerrado por el admin o ya con ganador
    if winning_number is not None or (state_id == 2):
        db.session.rollback()
        return {"ok": False, "code": "GAME_SWITCHED",
                "error": "El juego ya fue cerrado. Vuelve a jugar."}
    
    # 3) Lleno por cupo
    if used >= 1000:
        db.session.rollback()
        return {"ok": False, "code": "GAME_SWITCHED",
                "error": "El juego cambió (se completó). Vuelve a jugar."}

    # ⛔ Tope por usuario en este juego: no permitir segundo commit ni parciales
    current_count = _count_user_numbers_in_game(user_id, game_id)

    if current_count >= 5:
        # Ya tiene su selección completa en este juego
        rows = db.session.execute(text("""
            SELECT number
            FROM game_numbers
            WHERE game_id = :gid AND taken_by = :uid
            ORDER BY position ASC
        """), {"gid": game_id, "uid": user_id}).fetchall()
        current_numbers = [int(r[0]) for r in rows[:5]]
        db.session.rollback()
        return {
            "ok": False,
            "code": "LIMIT_REACHED",
            "error": "Ya tienes 5 números reservados para este juego.",
            "data": {"game_id": game_id, "numbers": current_numbers, "user_id_used": user_id}
        }

    if 0 < current_count < 5:
        # Estado parcial: fuerza liberar primero para evitar acumulaciones invisibles entre dispositivos
        rows = db.session.execute(text("""
            SELECT number
            FROM game_numbers
            WHERE game_id = :gid AND taken_by = :uid
            ORDER BY position ASC
        """), {"gid": game_id, "uid": user_id}).fetchall()
        current_numbers = [int(r[0]) for r in rows]
        db.session.rollback()
        return {
            "ok": False,
            "code": "PARTIAL_EXISTS",
            "error": "Ya tienes números reservados parciales en este juego. Libera tu selección para reemplazarla.",
            "data": {"game_id": game_id, "numbers": current_numbers, "user_id_used": user_id}
        }

    # Intento de inserción atómica con 'ON CONFLICT DO NOTHING'
    # Usamos RETURNING para saber cuántos se insertaron realmente.
    sql = text("""
        WITH ins AS (
          INSERT INTO game_numbers (game_id, number, position, taken_by)
          VALUES
            (:gid, :n1, 1, :uid),
            (:gid, :n2, 2, :uid),
            (:gid, :n3, 3, :uid),
            (:gid, :n4, 4, :uid),
            (:gid, :n5, 5, :uid)
          ON CONFLICT (game_id, number) DO NOTHING
          RETURNING id
        )
        SELECT COUNT(*) FROM ins;
    """)

    res = db.session.execute(sql, {
        "gid": game_id,
        "uid": user_id,
        "n1": numbers[0], "n2": numbers[1], "n3": numbers[2],
        "n4": numbers[3], "n5": numbers[4],
    }).scalar()

    if res == 5:
        db.session.commit()

        used = db.session.execute(text("""
            SELECT COUNT(*) FROM game_numbers WHERE game_id = :gid
        """), {"gid": game_id}).scalar()
        completed = (used >= 1000)

        if completed:
            # Marca el juego como cerrado y deja listo el siguiente “abierto y sin programar”
            db.session.execute(text("""
                UPDATE games
                SET state_id = 2, played_at = NOW()
                WHERE id = :gid AND state_id = 1
            """), {"gid": game_id})
            # Garantiza que exista el siguiente juego abierto y sin programar
            _ = get_or_create_active_unscheduled_game_id()
            db.session.commit()

        return {
            "ok": True,
            "game_completed": completed,
            "user_id_used": user_id
        }

    # Si no insertó los 5, deshacer y avisar conflicto
    db.session.rollback()
    return {"ok": False, "code": "CONFLICT",
            "error": "Alguno(s) de los números ya no están disponibles. Vuelve a jugar."}

# ===== Liberar selección anterior (reemplazo) =====

def release_selection(user_id: int, game_id: int) -> dict:
    """
    Borra de game_numbers todas las filas reservadas por este usuario en ese juego.
    Devuelve:
      - {"ok": True, "released": N} si borró N filas (N puede ser 0..5)
      - {"ok": False, "error": "..."} si algo falló
    """
    try:
        res = db.session.execute(text("""
            DELETE FROM game_numbers
            WHERE game_id = :gid
              AND taken_by = :uid
            RETURNING id;
        """), {"gid": game_id, "uid": user_id})

        released = len(res.fetchall())  # cuántas filas borró
        db.session.commit()

        return {"ok": True, "released": released}

    except Exception as e:
        db.session.rollback()
        return {"ok": False, "error": f"release_failed: {e}"}

def get_last_selection(user_id: int) -> dict:
    """
    Devuelve la última selección COMPLETA (5 números) del usuario.
    Si no hay, retorna {"ok": False, "code": "NOT_FOUND"}.
    """
    try:
        row = db.session.execute(text("""
            SELECT g.id AS game_id
            FROM games g
            JOIN game_numbers gn ON gn.game_id = g.id
            WHERE gn.taken_by = :uid
            GROUP BY g.id
            HAVING COUNT(*) >= 5
            ORDER BY g.id DESC
            LIMIT 1
        """), {"uid": user_id}).fetchone()

        if row is None:
            return {"ok": False, "code": "NOT_FOUND", "message": "Sin selección previa"}

        gid = int(row[0])

        nums = db.session.execute(text("""
            SELECT number
            FROM game_numbers
            WHERE game_id = :gid AND taken_by = :uid
            ORDER BY position ASC
        """), {"gid": gid, "uid": user_id}).fetchall()

        numbers = [int(r[0]) for r in nums]
        if len(numbers) < 5:
            return {"ok": False, "code": "NOT_FOUND", "message": "Sin selección previa"}

        return {"ok": True, "data": {"game_id": gid, "numbers": numbers, "user_id_used": user_id}}
    except Exception as e:
        return {"ok": False, "code": "ERROR", "message": f"{e}"}

def set_winner(game_id: int, winning_number: int) -> tuple[bool, str | None]:
    try:
        db.session.execute(text("""
            UPDATE games
            SET winning_number = :num,
                state_id = 2
            WHERE id = :gid
        """), {"gid": game_id, "num": winning_number})

        db.session.commit()
        return True, None
    except Exception as e:
        db.session.rollback()
        return False, str(e)

def list_user_history(conn, user_id: int, page: int, per_page: int) -> dict:
    """
    Devuelve el historial paginado de juegos en los que el usuario participó.
    - conn: raw_connection() (ya lo abres/cierra la ruta)
    - user_id: id del usuario
    - page / per_page: paginación

    Retorna:
    {
      "ok": True,
      "page": <int>,
      "per_page": <int>,
      "total": <int>,
      "items": [
        {
          "game_id": <int>,
          "numbers": [n1, n2, n3, n4, n5],  # según los que ese usuario reservó en ese juego
          "state_id": <int|null>,
          "winning_number": <int|null>
        },
        ...
      ]
    }
    """
    # --- PREMIUM guard: historial solo para PRO ---
    if not _is_user_pro(user_id):
        return {
            "ok": False,
            "code": "NOT_PREMIUM",
            "message": "El historial es solo para usuarios PRO."
        }

    try:
        offset = max(0, (int(page) - 1) * int(per_page))
        limit = max(1, int(per_page))
        cur = conn.cursor()

        # Total de juegos en los que el usuario tiene al menos 1 número
        cur.execute(
            """
            SELECT COUNT(*) FROM (
              SELECT gn.game_id
              FROM game_numbers gn
              WHERE gn.taken_by = %s
              GROUP BY gn.game_id
            ) t;
            """,
            (user_id,),
        )
        total = int(cur.fetchone()[0])

        cur.execute(
            """
            SELECT
            g.id AS game_id,                 -- r[0]
            g.state_id,                      -- r[1]
            g.winning_number,                -- r[2]
            COALESCE(g.lottery_name, l.name) AS lottery_name,  -- r[3]
            g.scheduled_date,                -- r[4]
            g.scheduled_time,                -- r[5]
            g.played_at,                     -- r[6]
            ARRAY_AGG(gn.number ORDER BY gn.position) AS numbers  -- r[7]
            FROM games g
            JOIN game_numbers gn ON gn.game_id = g.id
            LEFT JOIN lotteries l ON l.id = g.lottery_id
            WHERE gn.taken_by = %s
            GROUP BY
            g.id, g.state_id, g.winning_number,
            COALESCE(g.lottery_name, l.name),
            g.scheduled_date, g.scheduled_time, g.played_at
            ORDER BY g.id DESC
            LIMIT %s OFFSET %s;
            """,
            (user_id, limit, offset),
        )

        rows = cur.fetchall()
        cur.close()

        items = []
        for r in rows:
            # r[0]..r[7] según el SELECT que te pasé:
            # 0 game_id, 1 state_id, 2 winning_number, 3 lottery_name (COALESCE),
            # 4 scheduled_date, 5 scheduled_time, 6 played_at, 7 numbers[]
            items.append({
                "game_id": int(r[0]),
                "state_id": int(r[1]) if r[1] is not None else None,
                "winning_number": int(r[2]) if r[2] is not None else None,
                "lottery_name": r[3],
                "scheduled_date": r[4].isoformat() if r[4] else None,
                "scheduled_time": str(r[5]) if r[5] else None,
                "played_at": r[6].isoformat() if r[6] else None,
                "numbers": [int(n) for n in (r[7] or [])],
            })


        return {
            "ok": True,
            "page": int(page),
            "per_page": int(per_page),
            "total": total,
            "items": items,
        }

    except Exception as e:
        try:
            cur.close()
        except Exception:
            pass
        return {"ok": False, "message": f"history_error: {e}"}
