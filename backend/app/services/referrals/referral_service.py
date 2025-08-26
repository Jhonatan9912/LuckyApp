from typing import List, Dict, Any
from sqlalchemy import text
from app.db.database import db  # tu SQLAlchemy()

# Cambia esta condición si tu lógica PRO es distinta (status/expires_at).
PRO_CONDITION = "s.status = 'active'"

def get_summary_for_user(user_id: int) -> Dict[str, int]:
    sql = text(f"""
        WITH base AS (
          SELECT r.id,
                 r.referred_user_id,
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
          COUNT(*)                       AS total,
          COUNT(*) FILTER (WHERE pro_active) AS activos
        FROM base;
    """)
    row = db.session.execute(sql, {"uid": user_id}).one()
    total = int(row.total or 0)
    activos = int(row.activos or 0)
    return {
        "total": total,
        "activos": activos,
        "inactivos": max(total - activos, 0),
    }

def get_referrals_for_user(user_id: int, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
    sql = text(f"""
        SELECT
          r.id,
          r.referred_user_id,
          u.name   AS referred_name,
          u.email  AS referred_email,
          r.status::text AS status,        -- enum -> text
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
    rows = db.session.execute(sql, {"uid": user_id, "limit": limit, "offset": offset}).mappings().all()
    out = []
    for r in rows:
        out.append({
            "id": r["id"],
            "referred_user_id": r["referred_user_id"],
            "referred_name": r["referred_name"],
            "referred_email": r["referred_email"],
            "status": r["status"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "pro_active": bool(r["pro_active"]),
        })
    return out

def link_referral_on_signup(referral_code: str | None, new_user_id: int) -> None:
    """
    Si el usuario se registró con referral_code, registra/actualiza la fila en referrals.
    Respeta el índice único (referrer_user_id, referred_user_id) y hace UPSERT.
    """
    if not referral_code:
        return

    sql = text("""
        WITH referrer AS (
          SELECT id AS referrer_id
          FROM users
          WHERE public_code = :code
          LIMIT 1
        )
        INSERT INTO referrals (
          referrer_user_id, referred_user_id, referral_code_used, status, created_at, updated_at
        )
        SELECT r.referrer_id, :new_uid, :code, 'registered', NOW(), NOW()
        FROM referrer r
        ON CONFLICT (referrer_user_id, referred_user_id)
        DO UPDATE SET
          referral_code_used = EXCLUDED.referral_code_used,
          status = 'registered',
          updated_at = NOW();
    """)
    db.session.execute(sql, {"code": referral_code, "new_uid": new_user_id})
    db.session.commit()