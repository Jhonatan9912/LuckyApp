# app/services/admin/admin_service.py
from sqlalchemy import text
from app.db.database import db


def get_lottery_dashboard_summary():
    total_users = db.session.execute(text("SELECT COUNT(*) FROM users")).scalar() or 0

    # Juegos activos (state_id=1)
    try:
        active_games = db.session.execute(text("""
            SELECT COUNT(*) FROM games WHERE state_id = 1
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        active_games = 0

    # 👇 jugadores = COUNT DISTINCT (game_id, taken_by) en game_numbers
    try:
        players_count = db.session.execute(text("""
            SELECT COUNT(*) FROM (
                SELECT gn.game_id, gn.taken_by
                FROM game_numbers gn
                -- Si quisieras contar SOLO juegos activos, descomenta la línea de abajo:
                -- JOIN games g ON g.id = gn.game_id AND g.state_id = 1
                GROUP BY gn.game_id, gn.taken_by
            ) t
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        players_count = 0

    tickets_today = 0
    revenue_ytd = 0.0
    sales_by_month = []
    revenue_by_month = []
    latest_sales = []

    latest_users = db.session.execute(text("""
        SELECT id, name, phone, public_code, role_id
        FROM users
        ORDER BY id DESC
        LIMIT 5
    """)).mappings().all()
    latest_users = [dict(r) for r in latest_users]

    return {
        "kpis": {
            "users": int(total_users),
            "total_users": int(total_users),

            "games": int(active_games),
            "total_games": int(active_games),

            "players": int(players_count),
            "total_players": int(players_count),

            "tickets_today": int(tickets_today),
            "revenue_ytd": float(revenue_ytd),
        },
        "sales_by_month": sales_by_month,
        "revenue_by_month": revenue_by_month,
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
