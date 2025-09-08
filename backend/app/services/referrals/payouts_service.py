# app/services/referrals/payouts_service.py
import os
from decimal import Decimal
from datetime import datetime, timezone, timedelta

from sqlalchemy import text
from app.db.database import db
from werkzeug.exceptions import BadRequest
import json
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from flask import current_app

DEFAULT_CURRENCY = "COP"


def get_maturity_days() -> int:
    """
    Días para pasar pending → available.
    Prod: 3 (por ventana de reembolso)
    Dev/Sandbox: configurable y corto para pruebas (0 o 1).
    """
    env = (os.getenv("ENV", "") or "").lower()
    if env in ("dev", "sandbox", "staging"):
        return int(os.getenv("MATURITY_DAYS", "1"))
    return int(os.getenv("MATURITY_DAYS", "3"))


def mature_commissions(days: int | None = None, minutes: int | None = None) -> int:
    if minutes is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=int(minutes))
    else:
        if days is None:
            days = get_maturity_days()
        cutoff = datetime.now(timezone.utc) - timedelta(days=int(days))

    with db.session.begin_nested():
        res = db.session.execute(
            text("""
                UPDATE referral_commissions
                   SET status = 'available'
                 WHERE status = 'pending'
                   AND amount_micros > 0
                   AND event_time <= :cutoff
            """),
            {"cutoff": cutoff},
        )
        return int(res.rowcount or 0)


def reject_commissions_for_token(purchase_token: str) -> int:
    if not purchase_token:
        return 0
    with db.session.begin_nested():
        res = db.session.execute(
            text("""
                UPDATE referral_commissions
                   SET status = 'rejected'
                 WHERE purchase_token = :token
                   AND status = 'pending'
            """),
            {"token": purchase_token},
        )
        return int(res.rowcount or 0)

def get_payout_totals(referrer_user_id: int, currency: str = DEFAULT_CURRENCY) -> dict:
    """
    Devuelve totales para tablero/referrals:
      - currency
      - pending   (micros → unidades)
      - available (micros → unidades)
      - paid      (micros → unidades)
      - visible_total = pending + available
    """
    row_p = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS pend,
                   COALESCE(MAX(currency_code), :cur) AS cur
              FROM referral_commissions
             WHERE referrer_user_id = :uid AND status = 'pending'
        """),
        {"uid": referrer_user_id, "cur": currency},
    ).mappings().first()

    row_a = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS avail
              FROM referral_commissions
             WHERE referrer_user_id = :uid AND status = 'available'
        """),
        {"uid": referrer_user_id},
    ).mappings().first()

    row_paid = db.session.execute(
        text("""
            SELECT COALESCE(SUM(commission_micros),0) AS paid
              FROM referral_commissions
             WHERE referrer_user_id = :uid AND status = 'paid'
        """),
        {"uid": referrer_user_id},
    ).mappings().first()

    pend_micros = (row_p or {}).get("pend", 0) or 0
    avail_micros = (row_a or {}).get("avail", 0) or 0
    paid_micros = (row_paid or {}).get("paid", 0) or 0
    cur = (row_p or {}).get("cur") or currency

    to_units = lambda x: float(Decimal(x) / Decimal(1_000_000))
    return {
        "currency": cur,
        "pending": to_units(pend_micros),
        "available": to_units(avail_micros),
        "paid": to_units(paid_micros),
        "visible_total": to_units(pend_micros + avail_micros),
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
        {"rid": referred_user_id},
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

    percent = _get_commission_percent()  # p. ej. 40
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
        },
    )
    inserted = res.rowcount and res.rowcount > 0
    if inserted:
        db.session.commit()
    else:
        db.session.rollback()
    return bool(inserted)

def reject_payout_request(*, request_id: int, reason: str, admin_id: int | None) -> dict:
    """
    Rechaza una solicitud de retiro y revierte comisiones:
      - referral_commissions: status -> 'available' y payout_request_id = NULL
      - payout_request_items: elimina filas (si existe la tabla)
      - payout_requests: status -> 'rejected' (+ auditoría si existen columnas)
      - notificación (jsonb si aplica)
    Manejo de transacción: SIEMPRE SAVEPOINT (begin_nested) aquí.
    El commit real lo hace la ruta.
    """
    if not reason or len(reason.strip()) < 5:
        raise BadRequest("Motivo inválido")

    with db.session.begin_nested():
        # --- 0) Esquema dinámico ---
        pri_exists = db.session.execute(sa.text("""
            SELECT 1
              FROM information_schema.tables
             WHERE table_schema='public' AND table_name='payout_request_items'
             LIMIT 1
        """)).scalar() is not None

        pr_cols = db.session.execute(sa.text("""
            SELECT column_name
              FROM information_schema.columns
             WHERE table_schema='public' AND table_name='payout_requests'
               AND column_name IN ('rejected_by','rejected_reason','rejected_at','admin_note')
        """)).mappings().all()
        pr_have = {c["column_name"] for c in pr_cols}

        # --- 1) Lock + datos del request ---
        req = db.session.execute(
            sa.text("""
                SELECT id, user_id, amount_micros, currency_code, status
                  FROM payout_requests
                 WHERE id = :rid
                 FOR UPDATE
            """),
            {"rid": request_id},
        ).mappings().first()
        if not req:
            raise BadRequest("Solicitud no encontrada")

        status = (req["status"] or "").lower()
        if status not in ("requested", "processing", "pending", "approved"):
            raise BadRequest(f"No se puede rechazar en estado '{status}'")

        user_id = int(req["user_id"])
        amount_micros = int(req["amount_micros"] or 0)
        currency_code = (req["currency_code"] or "COP").upper()

        # --- 2) Revertir comisiones a 'available' ---
        db.session.execute(
            sa.text("""
                UPDATE referral_commissions
                   SET status = 'available', payout_request_id = NULL
                 WHERE payout_request_id = :rid
            """),
            {"rid": request_id},
        )

        if pri_exists:
            db.session.execute(
                sa.text("""
                    UPDATE referral_commissions rc
                       SET status = 'available', payout_request_id = NULL
                      FROM payout_request_items pri
                     WHERE pri.payout_request_id = :rid
                       AND rc.id = COALESCE(pri.commission_id, pri.referral_commission_id)
                """),
                {"rid": request_id},
            )
            db.session.execute(
                sa.text("DELETE FROM payout_request_items WHERE payout_request_id = :rid"),
                {"rid": request_id},
            )

        # --- 3) Marcar payout_request como 'rejected' ---
        if {"rejected_by", "rejected_reason", "rejected_at"} & pr_have:
            if "rejected_by" in pr_have:
                db.session.execute(
                    sa.text("""
                        UPDATE payout_requests
                           SET status = 'rejected',
                               rejected_by = :admin_id,
                               rejected_reason = :reason,
                               rejected_at = NOW(),
                               updated_at = NOW()
                         WHERE id = :rid
                    """),
                    {"rid": request_id, "reason": reason, "admin_id": admin_id},
                )
            else:
                db.session.execute(
                    sa.text("""
                        UPDATE payout_requests
                           SET status = 'rejected',
                               rejected_reason = :reason,
                               rejected_at = NOW(),
                               updated_at = NOW()
                         WHERE id = :rid
                    """),
                    {"rid": request_id, "reason": reason},
                )
        elif "admin_note" in pr_have:
            db.session.execute(
                sa.text("""
                    UPDATE payout_requests
                       SET status = 'rejected',
                           admin_note = :reason,
                           updated_at = NOW()
                     WHERE id = :rid
                """),
                {"rid": request_id, "reason": reason},
            )
        else:
            db.session.execute(
                sa.text("""
                    UPDATE payout_requests
                       SET status = 'rejected', updated_at = NOW()
                     WHERE id = :rid
                """),
                {"rid": request_id},
            )

        # --- 4) Notificación ---
        payload = {
            "type": "withdrawal_rejected",
            "payout_request_id": request_id,
            "amount_cop": int(round(amount_micros / 1_000_000)),
            "currency": currency_code,
            "reason": reason,
            "rejected_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            db.session.execute(
                sa.text("""
                    INSERT INTO notifications (user_id, title, body, data, is_read, created_at)
                    VALUES (:uid, :title, :body, :data, false, NOW())
                """).bindparams(sa.bindparam("data", type_=JSONB)),
                {
                    "uid": user_id,
                    "title": "Tu retiro fue rechazado",
                    "body": "Hemos devuelto el dinero a Disponible.",
                    "data": payload,
                },
            )
        except Exception:
            current_app.logger.exception("notify withdrawal_rejected failed")

    # (sin commit aquí; lo hace la ruta)
    return {
        "request_id": request_id,
        "user_id": user_id,
        "amount_micros": amount_micros,
        "status": "rejected",
    }
