# app/repositories/referral_repository.py
from typing import List, Tuple, Dict, Any
from sqlalchemy import text
from app.db.database import db

# Ajusta esta condición a tu realidad:
#   - si usas status='active' -> deja la primera
#   - si usas expiración -> usa la segunda o combina ambas
PRO_CONDITION = "s.status = 'active'"
# PRO_CONDITION = "(s.expires_at IS NOT NULL AND s.expires_at > NOW())"

def list_by_referrer(referrer_id: int, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
    sql = text(f"""
        SELECT
          r.id,
          r.referred_user_id,
          u.name  AS referred_name,
          u.email AS referred_email,
          r.status::text AS status,
          r.created_at,
          EXISTS (
            SELECT 1
            FROM user_subscriptions s
            WHERE s.user_id = r.referred_user_id
              AND ({PRO_CONDITION})
          ) AS pro_active
        FROM referrals r
        LEFT JOIN users u ON u.id = r.referred_user_id
        WHERE r.referrer_user_id = :uid
        ORDER BY r.created_at DESC NULLS LAST, r.id DESC
        LIMIT :limit OFFSET :offset;
    """)
    rows = db.session.execute(sql, {"uid": referrer_id, "limit": limit, "offset": offset}).mappings().all()
    out: List[Dict[str, Any]] = []
    for r in rows:
        out.append({
            "id": r["id"],
            "referred_user_id": r["referred_user_id"],
            "referred_name": r.get("referred_name"),
            "referred_email": r.get("referred_email"),
            "status": r["status"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "pro_active": bool(r["pro_active"]),
        })
    return out

def summary_by_referrer(referrer_id: int) -> Tuple[int, int]:
    sql = text(f"""
        WITH base AS (
          SELECT
            r.id,
            EXISTS (
              SELECT 1
              FROM user_subscriptions s
              WHERE s.user_id = r.referred_user_id
                AND ({PRO_CONDITION})
            ) AS pro_active
          FROM referrals r
          WHERE r.referrer_user_id = :uid
        )
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE pro_active) AS activos
        FROM base;
    """)
    row = db.session.execute(sql, {"uid": referrer_id}).one()
    total = int(row.total or 0)
    activos = int(row.activos or 0)
    return total, activos
