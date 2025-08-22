# app/services/admin/admin_service.py  (o donde esté esta función)
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

    # 👇 NUEVO: jugadores = COUNT DISTINCT (game_id, taken_by) en game_numbers
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

    try:
        tickets_today = db.session.execute(text("""
            SELECT COALESCE(SUM(quantity),0)
            FROM tickets
            WHERE sale_date = CURRENT_DATE
        """)).scalar() or 0
    except Exception:
        db.session.rollback()
        tickets_today = 0

    try:
        revenue_ytd = db.session.execute(text("""
            SELECT COALESCE(SUM(total_amount),0)
            FROM tickets
            WHERE EXTRACT(YEAR FROM sale_date) = EXTRACT(YEAR FROM CURRENT_DATE)
        """)).scalar() or 0.0
    except Exception:
        db.session.rollback()
        revenue_ytd = 0.0

    try:
        sales_by_month = db.session.execute(text("""
            SELECT TO_CHAR(date_trunc('month', sale_date), 'YYYY-MM') AS month,
                   SUM(quantity) AS qty
            FROM tickets
            WHERE EXTRACT(YEAR FROM sale_date) = EXTRACT(YEAR FROM CURRENT_DATE)
            GROUP BY 1 ORDER BY 1
        """)).mappings().all()
        sales_by_month = [dict(r) for r in sales_by_month]
    except Exception:
        db.session.rollback()
        sales_by_month = []

    try:
        revenue_by_month = db.session.execute(text("""
            SELECT TO_CHAR(date_trunc('month', sale_date), 'YYYY-MM') AS month,
                   SUM(total_amount) AS revenue
            FROM tickets
            WHERE EXTRACT(YEAR FROM sale_date) = EXTRACT(YEAR FROM CURRENT_DATE)
            GROUP BY 1 ORDER BY 1
        """)).mappings().all()
        revenue_by_month = [dict(r) for r in revenue_by_month]
    except Exception:
        db.session.rollback()
        revenue_by_month = []

    latest_users = db.session.execute(text("""
        SELECT id, name, phone, public_code, role_id
        FROM users
        ORDER BY id DESC
        LIMIT 5
    """)).mappings().all()
    latest_users = [dict(r) for r in latest_users]

    try:
        latest_sales = db.session.execute(text("""
            SELECT id AS sale_id, total_amount, sale_date
            FROM tickets
            ORDER BY sale_date DESC, id DESC
            LIMIT 5
        """)).mappings().all()
        latest_sales = [dict(r) for r in latest_sales]
    except Exception:
        db.session.rollback()
        latest_sales = []

    return {
        "kpis": {
            # incluye las claves que tu Flutter ya espera como alternativas
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
