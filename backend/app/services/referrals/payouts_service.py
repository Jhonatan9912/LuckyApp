# app/services/referrals/payouts_service.py
from decimal import Decimal
from sqlalchemy import text
from app.db.database import db
from datetime import datetime, timezone

DEFAULT_CURRENCY = "COP"

def get_payout_totals(referrer_user_id: int, currency: str = DEFAULT_CURRENCY) -> dict:
    row_p = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS pend,
                   COALESCE(MAX(currency_code), :cur) AS cur
            FROM referral_commissions
            WHERE referrer_user_id = :uid AND status = 'pending'
        """),
        {"uid": referrer_user_id, "cur": currency}
    ).mappings().first()

    row_paid = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS paid
            FROM referral_commissions
            WHERE referrer_user_id = :uid AND status = 'paid'
        """),
        {"uid": referrer_user_id}
    ).mappings().first()

    pend_micros = (row_p or {}).get("pend", 0) or 0
    paid_micros = (row_paid or {}).get("paid", 0) or 0
    cur = (row_p or {}).get("cur") or currency

    to_units = lambda x: float(Decimal(x) / Decimal(1_000_000))
    return {"currency": cur, "pending": to_units(pend_micros), "paid": to_units(paid_micros)}

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
    Devuelve el referrer del usuario referido (si existe).
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
    Calcula la comisión con el % actual y la inserta en referral_commissions.
    Idempotente por (referred_user_id, product_id, purchase_token, order_id).
    Devuelve True si insertó; False si ya existía o no hay referrer.
    """
    referrer_id = _get_referrer_user_id(referred_user_id)
    if not referrer_id:
        return False  # no hay a quién pagar

    percent = _get_commission_percent()  # p.ej. 40
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
        db.session.rollback()
    return bool(inserted)
