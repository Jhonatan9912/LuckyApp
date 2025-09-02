# app/services/referrals/payouts_service.py
import os
from decimal import Decimal
from sqlalchemy import text
from app.db.database import db
from datetime import datetime, timezone, timedelta

DEFAULT_CURRENCY = "COP"


def get_maturity_days() -> int:
    """
    Días para pasar pending → available.
    Prod: 3 (por ventana de reembolso)
    Dev/Sandbox: configurable y corto para pruebas (0 o 1).
    """
    env = (os.getenv('ENV', '') or '').lower()
    if env in ('dev', 'sandbox', 'staging'):
        return int(os.getenv('MATURITY_DAYS', '1'))
    return int(os.getenv('MATURITY_DAYS', '3'))

def mature_commissions(days: int | None = None) -> int:
    """
    Pasa comisiones de pending → available si:
      - amount_micros > 0
      - event_time <= now - days
    Devuelve cuántas filas actualizó.
    """
    if days is None:
        days = get_maturity_days()

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)

    res = db.session.execute(
        text("""
            UPDATE referral_commissions
               SET status = 'available'
             WHERE status = 'pending'
               AND amount_micros > 0
               AND event_time <= :cutoff
        """),
        {"cutoff": cutoff.isoformat()}
    )
    db.session.commit()

    return int(res.rowcount or 0)

def reject_commissions_for_token(purchase_token: str) -> int:
    """
    Marca como 'rejected' todas las comisiones PENDIENTES asociadas al purchase_token.
    Se usa cuando llega RTDN con notificationType=12 (REVOKED/Refund).
    Devuelve cuántas filas actualizó.
    """
    if not purchase_token:
        return 0

    res = db.session.execute(
        text("""
            UPDATE referral_commissions
               SET status = 'rejected'
             WHERE purchase_token = :token
               AND status = 'pending'
        """),
        {"token": purchase_token}
    )
    db.session.commit()
    return int(res.rowcount or 0)


def get_payout_totals(referrer_user_id: int, currency: str = DEFAULT_CURRENCY) -> dict:
    """
    Devuelve:
      - currency
      - pending:   suma en micros → unidades
      - available: suma en micros → unidades (listo para retiro)
      - paid:      suma en micros → unidades (pagado históricamente)
      - visible_total: pending + available (lo que muestras al usuario de inmediato)
    """
    row_p = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS pend,
                   COALESCE(MAX(currency_code), :cur) AS cur
            FROM referral_commissions
            WHERE referrer_user_id = :uid AND status = 'pending'
        """),
        {"uid": referrer_user_id, "cur": currency}
    ).mappings().first()

    row_a = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS avail
            FROM referral_commissions
            WHERE referrer_user_id = :uid AND status = 'available'
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

    pend_micros  = (row_p or {}).get("pend", 0) or 0
    avail_micros = (row_a or {}).get("avail", 0) or 0
    paid_micros  = (row_paid or {}).get("paid", 0) or 0
    cur = (row_p or {}).get("cur") or currency

    to_units = lambda x: float(Decimal(x) / Decimal(1_000_000))
    return {
        "currency": cur,
        "pending": to_units(pend_micros),
        "available": to_units(avail_micros),        # ← para habilitar el botón
        "paid": to_units(paid_micros),
        "visible_total": to_units(pend_micros + avail_micros),  # ← lo que ves desde el día 0
    }

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
