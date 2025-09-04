# app/services/admin/referrals_service.py
from __future__ import annotations

from typing import Optional, Dict, Any
from sqlalchemy import text, bindparam, Integer
from app.db.database import db


def get_referrals_summary(referrer_id: Optional[int] = None) -> Dict[str, Any]:
    """
    Resumen global (o por referidor) de personas referidas.

    Definiciones:
      - total   : cantidad de filas en public.referrals
      - active  : referidos cuya última fila en public.user_subscriptions
                  tiene is_premium = TRUE y expires_at > NOW()
      - inactive: total - active

    Parámetros:
      referrer_id (opcional): si se pasa, filtra por ese promotor.

    Devuelve:
      { "total": int, "active": int, "inactive": int }
    """
    # Si aún no existe la tabla, devolvemos ceros (primera instalación)
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
        """).bindparams(*( [bindparam("rid", type_=Integer)] if referrer_id is not None else [] ))

        total = db.session.execute(total_stmt, params).scalar() or 0

        # ---------- ACTIVOS ----------
        # Tomamos la ÚLTIMA suscripción por usuario referido (LATERAL + ORDER/LIMIT 1)
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
        """).bindparams(*( [bindparam("rid", type_=Integer)] if referrer_id is not None else [] ))

        active = db.session.execute(active_stmt, params).scalar() or 0

        # ---------- INACTIVOS ----------
        inactive = int(total) - int(active)
        if inactive < 0:
            inactive = 0

        return {
            "total": int(total),
            "active": int(active),
            "inactive": int(inactive),
        }
    except Exception:
        # Fallback silencioso si la tabla no existe aún
        return {"total": 0, "active": 0, "inactive": 0}
