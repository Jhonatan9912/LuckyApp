# app/services/referrals/payouts_service.py
from decimal import Decimal
from sqlalchemy import text
from app.db.database import db

DEFAULT_CURRENCY = "COP"

def get_payout_totals(user_id: int, currency: str = DEFAULT_CURRENCY) -> dict:
    """
    Suma de recompensas por referido para el beneficiario (user_id).
    Devuelve pendientes y pagadas en la moneda dada.
    NOTA: status es enum -> comparamos casteando a text para evitar errores.
    """
    sql = text("""
        SELECT
          COALESCE(SUM(CASE WHEN status::text = 'pending' AND currency = :cur THEN amount ELSE 0 END), 0) AS pending,
          COALESCE(SUM(CASE WHEN status::text = 'paid'    AND currency = :cur THEN amount ELSE 0 END), 0) AS paid
        FROM referral_rewards
        WHERE beneficiary_user_id = :uid;
    """)
    row = db.session.execute(sql, {"uid": user_id, "cur": currency}).one_or_none()

    pending = Decimal(row.pending or 0) if row else Decimal(0)
    paid    = Decimal(row.paid or 0)    if row else Decimal(0)

    return {
        "currency": currency,
        "pending": float(pending),  # frontend espera números
        "paid": float(paid),
    }
