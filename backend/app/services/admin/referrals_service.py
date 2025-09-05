# app/services/admin/referrals_service.py
from __future__ import annotations

from typing import Optional, Dict, Any
from sqlalchemy import text, bindparam, Integer
from app.db.database import db


_MICROS = 1_000_000  # 1 COP = 1_000_000 micros


def _micros_to_cop(v) -> int:
    try:
        return int((v or 0) // _MICROS)
    except Exception:
        return 0


def get_referrals_summary(referrer_id: Optional[int] = None) -> Dict[str, Any]:
    """
    Resumen global (o por referidor) de personas referidas + montos.

    Definiciones:
      - total   : cantidad de filas en public.referrals
      - active  : referidos cuya última fila en public.user_subscriptions
                  tiene is_premium = TRUE y expires_at > NOW()
      - inactive: total - active

      - pending_cop : SUM(commission_micros) WHERE status='available'
      - paid_cop    : SUM(commission_micros) WHERE status='paid'
        (ambos provenientes de public.referral_commissions)

    Parámetros:
      referrer_id (opcional): si se pasa, filtra por ese promotor.

    Devuelve:
      {
        "total": int,
        "active": int,
        "inactive": int,
        "pending_cop": int,
        "paid_cop": int,
        "currency": "COP"
      }
    """
    try:
        where_total = "WHERE 1=1"
        params: Dict[str, Any] = {}

        if referrer_id is not None:
            where_total += " AND r.referrer_user_id = :rid"
            params["rid"] = int(referrer_id)

        # ---------- TOTAL ----------
        total_stmt = text(f"""
            SELECT COUNT(*)::bigint
            FROM public.referrals r
            {where_total}
        """).bindparams(*([bindparam("rid", type_=Integer)] if referrer_id is not None else []))

        total = db.session.execute(total_stmt, params).scalar() or 0

        # ---------- ACTIVOS ----------
        where_active = where_total + """
            AND sub.is_premium IS TRUE
            AND sub.expires_at IS NOT NULL
            AND sub.expires_at > NOW()
        """

        active_stmt = text(f"""
            SELECT COUNT(*)::bigint
            FROM public.referrals r
            LEFT JOIN LATERAL (
                SELECT s.is_premium, s.expires_at
                FROM public.user_subscriptions s
                WHERE s.user_id = r.referred_user_id
                ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at) DESC NULLS LAST
                LIMIT 1
            ) AS sub ON TRUE
            {where_active}
        """).bindparams(*([bindparam("rid", type_=Integer)] if referrer_id is not None else []))

        active = db.session.execute(active_stmt, params).scalar() or 0
        inactive = max(int(total) - int(active), 0)

        # ---------- COMISIONES: pendiente / pagada ----------
        where_comm = "WHERE 1=1"
        if referrer_id is not None:
            where_comm += " AND rc.referrer_user_id = :rid"

        comm_stmt = text(f"""
            SELECT
                COALESCE(SUM(CASE WHEN rc.status = 'available' THEN rc.commission_micros END), 0) AS pending_micros,
                COALESCE(SUM(CASE WHEN rc.status = 'paid'      THEN rc.commission_micros END), 0) AS paid_micros,
                -- Si tienes múltiples monedas, aquí podrías agregar lógica adicional.
                COALESCE(MAX(rc.currency_code), 'COP') AS currency
            FROM public.referral_commissions rc
            {where_comm}
        """).bindparams(*([bindparam("rid", type_=Integer)] if referrer_id is not None else []))

        row = db.session.execute(comm_stmt, params).mappings().first() or {}
        pending_cop = _micros_to_cop(row.get("pending_micros"))
        paid_cop = _micros_to_cop(row.get("paid_micros"))
        currency = row.get("currency") or "COP"

        return {
            "total": int(total),
            "active": int(active),
            "inactive": int(inactive),
            "pending_cop": int(pending_cop),
            "paid_cop": int(paid_cop),
            "currency": str(currency),
        }

    except Exception:
        # Fallback silencioso si las tablas no existen aún
        return {
            "total": 0,
            "active": 0,
            "inactive": 0,
            "pending_cop": 0,
            "paid_cop": 0,
            "currency": "COP",
        }

def get_top_referrers(limit: int = 5) -> list[dict]:
    """
    Devuelve el top de usuarios que más referidos activos tienen.
    Cada fila: { user_id, name, phone, active_count, status }
      - status: 'PRO' si el PROMOTOR tiene una suscripción activa; de lo contrario 'FREE'.
    """
    try:
        stmt = text("""
            WITH last_sub AS (        -- última suscripción del REFERIDO
                SELECT
                    s.user_id,
                    s.is_premium,
                    s.expires_at,
                    ROW_NUMBER() OVER (
                        PARTITION BY s.user_id
                        ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at) DESC NULLS LAST
                    ) AS rn
                FROM public.user_subscriptions s
            ),
            last_sub_ref AS (         -- última suscripción del PROMOTOR
                SELECT
                    s.user_id,
                    s.is_premium,
                    s.expires_at,
                    ROW_NUMBER() OVER (
                        PARTITION BY s.user_id
                        ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at) DESC NULLS LAST
                    ) AS rn
                FROM public.user_subscriptions s
            )
            SELECT
                r.referrer_user_id AS user_id,
                COALESCE(NULLIF(MAX(u.name), ''), MAX(u.email), 'ID #' || r.referrer_user_id::text) AS name,
                COALESCE(NULLIF(MAX(u.phone), ''), '') AS phone,
                COUNT(*)::int AS active_count,
                -- PRO si el promotor tiene una sub activa; si no, FREE
                MAX(
                  CASE
                    WHEN lsr.is_premium IS TRUE
                     AND lsr.expires_at IS NOT NULL
                     AND lsr.expires_at > NOW()
                    THEN 'PRO' ELSE 'FREE'
                  END
                ) AS status
            FROM public.referrals r
            JOIN last_sub ls
              ON ls.user_id = r.referred_user_id AND ls.rn = 1
            LEFT JOIN public.users u
              ON u.id = r.referrer_user_id
            LEFT JOIN last_sub_ref lsr
              ON lsr.user_id = r.referrer_user_id AND lsr.rn = 1
            WHERE r.referrer_user_id IS NOT NULL
              AND ls.is_premium IS TRUE
              AND ls.expires_at IS NOT NULL
              AND ls.expires_at > NOW()
            GROUP BY r.referrer_user_id
            ORDER BY active_count DESC
            LIMIT :lim
        """)

        rows = db.session.execute(stmt, {"lim": limit}).mappings().all()

        return [
            {
                "user_id": r["user_id"],
                "name": r["name"],
                "phone": r["phone"],
                "active_count": r["active_count"],
                "status": r["status"] or "FREE",
            }
            for r in rows
        ]
    except Exception as e:
        print("get_top_referrers ERROR:", e)
        return []
