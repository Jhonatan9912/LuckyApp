# app/services/admin/admin_service.py
from sqlalchemy import text
from app.db.database import db


from sqlalchemy import text
from app.db.database import db


def get_lottery_dashboard_summary():

    # 👤 Total usuarios
    total_users = db.session.execute(
        text("SELECT COUNT(*) FROM users")
    ).scalar() or 0

    # 🎮 Juegos activos
    try:
        active_games = db.session.execute(text("""
            SELECT COUNT(*)
            FROM games
            WHERE COALESCE(state_id, 1) = 1
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        active_games = 0

    # 👥 Jugadores únicos (por juego)
    try:
        players_count = db.session.execute(text("""
            SELECT COUNT(*) FROM (
                SELECT gn.game_id, gn.taken_by
                FROM game_numbers gn
                WHERE gn.taken_by IS NOT NULL
                GROUP BY gn.game_id, gn.taken_by
            ) t
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        players_count = 0

    # 🎟 Ventas hoy (números tomados hoy)
    try:
        numbers_today = db.session.execute(text("""
            SELECT COUNT(*)
            FROM game_numbers
            WHERE taken_by IS NOT NULL
              AND DATE(taken_at) = CURRENT_DATE
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        numbers_today = 0

    # 📅 Ventas año actual
    try:
        numbers_ytd = db.session.execute(text("""
            SELECT COUNT(*)
            FROM game_numbers
            WHERE taken_by IS NOT NULL
              AND EXTRACT(YEAR FROM taken_at) = EXTRACT(YEAR FROM CURRENT_DATE)
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        numbers_ytd = 0

    # 📊 Ventas por mes
    try:
        sales_by_month = db.session.execute(text("""
            SELECT 
                TO_CHAR(date_trunc('month', taken_at), 'YYYY-MM') AS month,
                COUNT(*) AS qty
            FROM game_numbers
            WHERE taken_by IS NOT NULL
            GROUP BY 1
            ORDER BY 1
        """)).mappings().all()

        sales_by_month = [dict(r) for r in sales_by_month]

    except Exception:
        db.session.rollback()
        sales_by_month = []

    # 👤 Últimos usuarios
    latest_users = db.session.execute(text("""
        SELECT id, name, phone, public_code, role_id
        FROM users
        ORDER BY id DESC
        LIMIT 5
    """)).mappings().all()

    latest_users = [dict(r) for r in latest_users]

    # 🎟 Últimas ventas (últimos números tomados)
    try:
        latest_sales = db.session.execute(text("""
            SELECT 
                gn.id AS sale_id,
                gn.game_id,
                gn.number,
                gn.taken_at,
                u.name AS user_name
            FROM game_numbers gn
            JOIN users u ON u.id = gn.taken_by
            WHERE gn.taken_by IS NOT NULL
            ORDER BY gn.taken_at DESC
            LIMIT 5
        """)).mappings().all()

        latest_sales = [dict(r) for r in latest_sales]

    except Exception:
        db.session.rollback()
        latest_sales = []

    return {
        "kpis": {
            "users": int(total_users),
            "total_users": int(total_users),

            "games": int(active_games),
            "total_games": int(active_games),

            "players": int(players_count),
            "total_players": int(players_count),

            "numbers_today": int(numbers_today),
            "numbers_ytd": int(numbers_ytd),
        },
        "sales_by_month": sales_by_month,
        "latest_users": latest_users,
        "latest_sales": latest_sales,
    }


def get_active_games_export_rows():
    """
    Retorna una fila por (juego, jugador, número reservado) con:

    - game_id
    - lottery_name
    - played_date (YYYY-MM-DD)
    - played_time (HH:MM)
    - user_id
    - user_name
    - user_phone
    - number
    - reserved_numbers_in_game  -> total de números reservados en ese juego
    - players_in_game           -> total de jugadores en ese juego
    """
    try:
        rows = db.session.execute(text("""
            WITH stats AS (
                SELECT
                    g.id AS game_id,
                    COUNT(*)                    AS reserved_numbers_in_game,
                    COUNT(DISTINCT gn.taken_by) AS players_in_game
                FROM game_numbers gn
                JOIN games g ON g.id = gn.game_id
                WHERE COALESCE(g.state_id, 1) = 1   -- juegos activos
                GROUP BY g.id
            )
            SELECT
                g.id AS game_id,
                COALESCE(l.name, g.lottery_name) AS lottery_name,
                to_char(g.played_at, 'YYYY-MM-DD') AS played_date,
                to_char(g.played_at, 'HH24:MI')   AS played_time,
                u.id    AS user_id,
                u.name  AS user_name,
                u.phone AS user_phone,
                gn.number AS number,
                s.reserved_numbers_in_game,
                s.players_in_game
            FROM game_numbers gn
            JOIN games g          ON g.id = gn.game_id
            LEFT JOIN lotteries l ON l.id = g.lottery_id
            JOIN users u          ON u.id = gn.taken_by    -- solo números tomados
            JOIN stats s          ON s.game_id = g.id      -- une estadísticas por juego
            WHERE COALESCE(g.state_id, 1) = 1              -- juegos activos
            ORDER BY g.id, u.id, gn.number
        """)).mappings().all()

        return [dict(r) for r in rows]

    except Exception as e:
        print("⚠️ Error en get_active_games_export_rows:", e)
        db.session.rollback()
        return []
