from typing import List, Dict, Any
from sqlalchemy import text
from app.db.database import db  # tu SQLAlchemy()

# Cambia esta condición si tu lógica PRO es distinta (status/expires_at).
PRO_CONDITION = "s.status = 'active'"


def get_summary_for_user(user_id: int) -> Dict[str, Any]:
    sql = text(f"""
        WITH base AS (
          SELECT r.id,
                 r.referred_user_id,
                 EXISTS (
                   SELECT 1 FROM user_subscriptions s
                   WHERE s.user_id = r.referred_user_id
                     AND ({PRO_CONDITION})
                 ) AS pro_active
          FROM referrals r
          WHERE r.referrer_user_id = :uid
        ),
        counts AS (
          SELECT
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE pro_active) AS activos
          FROM base
        ),
        sums AS (
          SELECT
            COALESCE(SUM(CASE WHEN status IN ('approved','available','accrued')
                              THEN commission_micros END),0) AS available_micros,
            COALESCE(SUM(CASE WHEN status IN ('pending','grace','hold')
                              THEN commission_micros END),0) AS pending_micros,
            COALESCE(SUM(CASE WHEN status = 'paid'
                              THEN commission_micros END),0) AS paid_micros,
            COALESCE(SUM(commission_micros),0) AS total_micros
          FROM referral_commissions
          WHERE referrer_user_id = :uid
        )
        SELECT
          c.total,
          c.activos,
          s.available_micros,
          s.pending_micros,
          s.paid_micros,
          s.total_micros
        FROM counts c
        CROSS JOIN sums s;
    """)
    row = db.session.execute(sql, {"uid": user_id}).mappings().one()

    total = int(row["total"] or 0)
    activos = int(row["activos"] or 0)
    inactivos = max(total - activos, 0)

    def m2c(v): return float(v or 0) / 1_000_000.0

    available_micros = int(row["available_micros"] or 0)
    pending_micros   = int(row["pending_micros"] or 0)
    paid_micros      = int(row["paid_micros"] or 0)
    total_micros     = int(row["total_micros"] or 0)

    return {
        "total": total, "activos": activos, "inactivos": inactivos,
        "available_micros": available_micros,
        "pending_micros":   pending_micros,
        "paid_micros":      paid_micros,
        "total_micros":     total_micros,
        "available_cop": m2c(available_micros),
        "pending_cop":   m2c(pending_micros),
        "paid_cop":      m2c(paid_micros),
        "total_cop":     m2c(total_micros),
        "__debug_stamp": "summary_v2_commissions",
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

  # =======================
#  COMISIONES (LEDGER)
# =======================
from datetime import datetime, timezone

def _get_commission_percent() -> float:
    """
    Lee el % desde commission_settings (key='referral_cut_percent').
    Devuelve flotante en [0..100].
    """
    row = db.session.execute(
        text("""
            SELECT value
              FROM commission_settings
             WHERE key = 'referral_cut_percent'
             LIMIT 1
        """)
    ).first()
    if not row or row[0] is None:
        return 0.0
    try:
        return float(str(row[0]).strip())
    except Exception:
        return 0.0


def _get_referrer_user_id(referred_user_id: int) -> int | None:
    """
    Quién refirió al usuario (si existe).
    Ajusta nombres de columnas si difieren.
    """
    row = db.session.execute(
        text("""
            SELECT referrer_user_id
              FROM referrals
             WHERE referred_user_id = :rid
             ORDER BY created_at ASC
             LIMIT 1
        """),
        {"rid": referred_user_id}
    ).first()
    return int(row[0]) if row and row[0] is not None else None


def register_referral_commission(
    *,
    referred_user_id: int,
    product_id: str,
    amount_micros: int,
    currency_code: str,
    purchase_token: str,
    order_id: str | None = None,
    source: str = "google_play",
    event_time: datetime | None = None,
) -> bool:
    """
    Calcula la comisión con el % actual en BD y la inserta en referral_commissions.
    Idempotente por (referred_user_id, product_id, purchase_token, order_id).
    Devuelve True si insertó; False si ya existía o no hay referrer.
    """
    referrer_id = _get_referrer_user_id(referred_user_id)
    if not referrer_id:
        return False  # no hay a quién pagar

    percent = _get_commission_percent()  # p. ej. 50
    commission_micros = int(round(amount_micros * (percent / 100.0)))
    when = (event_time or datetime.now(timezone.utc)).isoformat()

    res = db.session.execute(
        text("""
            INSERT INTO referral_commissions (
              referrer_user_id, referred_user_id, source,
              product_id, purchase_token, order_id, event_time,
              amount_micros, currency_code, percent, commission_micros, status
            )
            VALUES (
              :referrer_id, :referred_id, :source,
              :product_id, :purchase_token, :order_id, :event_time,
              :amount_micros, :currency_code, :percent, :commission_micros, 'pending'
            )
            ON CONFLICT (referred_user_id, product_id, purchase_token, order_id)
            DO NOTHING
        """),
        {
            "referrer_id": referrer_id,
            "referred_id": referred_user_id,
            "source": source,
            "product_id": product_id,
            "purchase_token": purchase_token,
            "order_id": order_id,
            "event_time": when,
            "amount_micros": amount_micros,
            "currency_code": currency_code,
            "percent": percent,
            "commission_micros": commission_micros,
        }
    )
    inserted = res.rowcount and res.rowcount > 0
    if inserted:
        db.session.commit()
    else:
        db.session.rollback()  # nada que hacer, ya existía
    return bool(inserted)


def get_payouts_summary_for_referrer(referrer_user_id: int) -> dict:
    """
    Totales para mostrar en tu ReferralProvider (pendiente / pagado).
    Devuelve en unidades (no micros).
    """
    row_p = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS pend,
                   COALESCE(MAX(currency_code),'COP') AS cur
              FROM referral_commissions
             WHERE referrer_user_id = :uid AND status = 'pending'
        """),
        {"uid": referrer_user_id}
    ).mappings().first()

    row_paid = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS paid
              FROM referral_commissions
             WHERE referrer_user_id = :uid AND status = 'paid'
        """),
        {"uid": referrer_user_id}
    ).mappings().first()

    pending = (row_p["pend"] or 0) / 1_000_000.0
    paid = (row_paid["paid"] or 0) / 1_000_000.0
    return {"pending": pending, "paid": paid, "currency": row_p["cur"] or "COP"}

def get_commissions_for_user(user_id: int, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
    sql = text("""
        SELECT
          id,
          referrer_user_id,
          referred_user_id,
          source,
          product_id,
          purchase_token,
          order_id,
          event_time,
          amount_micros,
          currency_code,
          percent,
          commission_micros,
          status
        FROM referral_commissions
        WHERE referrer_user_id = :uid
        ORDER BY event_time DESC NULLS LAST, id DESC
        LIMIT :limit OFFSET :offset
    """)
    rows = db.session.execute(sql, {"uid": user_id, "limit": limit, "offset": offset}).mappings().all()
    def m2c(x): return float(x or 0)/1_000_000.0
    return [{
        "id": r["id"],
        "referred_user_id": r["referred_user_id"],
        "source": r["source"],
        "product_id": r["product_id"],
        "order_id": r["order_id"],
        "event_time": r["event_time"].isoformat() if r["event_time"] else None,
        "amount_cop": m2c(r["amount_micros"]),
        "currency_code": r["currency_code"],
        "percent": r["percent"],
        "commission_cop": m2c(r["commission_micros"]),
        "status": r["status"],
    } for r in rows]
