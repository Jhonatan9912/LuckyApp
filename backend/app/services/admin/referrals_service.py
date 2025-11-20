# app/services/admin/referrals_service.py
from __future__ import annotations

from typing import Optional, Dict, Any
from sqlalchemy import text, bindparam, Integer
from app.db.database import db
from typing import Optional, Dict, Any, List

_MICROS = 1_000_000  # 1 COP = 1_000_000 micros


def _micros_to_cop(v) -> int:
    try:
        return int((v or 0) // _MICROS)
    except Exception:
        return 0

def _micros_to_int(v) -> int:
    """Convierte micros a enteros de COP (ej. 100_000_000 -> 100000)."""
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
    Cada fila:
      {
        user_id, name, phone, active_count, status,
        active_users: [
          { user_id, name, phone, status },
          ...
        ]
      }

      - status: 'PRO' si el PROMOTOR tiene una suscripción activa; de lo contrario 'FREE'.
      - active_users: lista de referidos ACTIVOS (PRO o FREE según su sub).
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
                        ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at)
                             DESC NULLS LAST
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
                        ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at)
                             DESC NULLS LAST
                    ) AS rn
                FROM public.user_subscriptions s
            )
            SELECT
                r.referrer_user_id AS user_id,
                COALESCE(
                  NULLIF(MAX(u.name), ''),
                  MAX(u.email),
                  'ID #' || r.referrer_user_id::text
                ) AS name,
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
                ) AS status,

                -- 👇 Lista de referidos activos (los mismos que cuentan en active_count)
                COALESCE(
                  (
                    SELECT json_agg(
                      json_build_object(
                        'user_id', ru.id,
                        'name', COALESCE(
                                   NULLIF(ru.name, ''),
                                   ru.email,
                                   'ID #' || ru.id::text
                               ),
                        'phone', COALESCE(NULLIF(ru.phone, ''), ''),
                        'status',
                          CASE
                            WHEN lsr2.is_premium IS TRUE
                             AND lsr2.expires_at IS NOT NULL
                             AND lsr2.expires_at > NOW()
                            THEN 'PRO' ELSE 'FREE'
                          END
                      )
                      ORDER BY ru.id
                    )
                    FROM public.referrals r2
                    JOIN last_sub ls2
                      ON ls2.user_id = r2.referred_user_id
                     AND ls2.rn = 1
                    JOIN public.users ru
                      ON ru.id = r2.referred_user_id
                    LEFT JOIN last_sub lsr2
                      ON lsr2.user_id = r2.referred_user_id
                     AND lsr2.rn = 1
                    WHERE r2.referrer_user_id = r.referrer_user_id
                      AND ls2.is_premium IS TRUE
                      AND ls2.expires_at IS NOT NULL
                      AND ls2.expires_at > NOW()
                  ),
                  '[]'::json
                ) AS active_users

            FROM public.referrals r
            JOIN last_sub ls
              ON ls.user_id = r.referred_user_id
             AND ls.rn = 1
            LEFT JOIN public.users u
              ON u.id = r.referrer_user_id
            LEFT JOIN last_sub_ref lsr
              ON lsr.user_id = r.referrer_user_id
             AND lsr.rn = 1
            WHERE r.referrer_user_id IS NOT NULL
              AND ls.is_premium IS TRUE
              AND ls.expires_at IS NOT NULL
              AND ls.expires_at > NOW()
            GROUP BY r.referrer_user_id
            ORDER BY active_count DESC
            LIMIT :lim
        """)

        rows = db.session.execute(stmt, {"lim": limit}).mappings().all()

        out: list[dict] = []
        for r in rows:
            active_users = r.get("active_users") or []
            # Según el driver, puede venir como list[dict] o como JSON string,
            # pero normalmente con SQLAlchemy + psycopg2 ya viene deserializado.
            out.append(
                {
                    "user_id": r["user_id"],
                    "name": r["name"],
                    "phone": r["phone"],
                    "active_count": r["active_count"],
                    "status": r["status"] or "FREE",
                    "active_users": active_users,
                }
            )
        return out

    except Exception as e:
        print("get_top_referrers ERROR:", e)
        return []

def get_admin_user_detail(user_id: int) -> Dict[str, Any]:
    """
    Devuelve el objeto que el front necesita para 'Ver usuario':
      {
        "user_id": int,
        "full_name": str,
        "id_number": str,
        "is_pro": bool,
        "payee_full_name": str,
        "payee_id_number": str,
        "account_type": str,       # 'bank' | 'nequi' | 'daviplata' | 'other'
        "provider_name": str,      # nombre del banco/proveedor (por bank_id)
        "account_number": str,
        "bank_kind": Optional[str] # 'savings' | 'checking' | None
      }
    Saca:
      - users: full_name / identification_number
      - user_subscriptions: última fila activa para is_pro
      - payout_requests: ÚLTIMA solicitud (ORDER BY requested_at/created_at DESC) para datos bancarios
      - banks: mapear bank_id -> name
    """

    sql = text("""
        WITH last_sub AS (
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
        latest_payout AS (
            SELECT pr.*
            FROM public.payout_requests pr
            WHERE pr.user_id = :user_id
            ORDER BY COALESCE(pr.requested_at, pr.created_at) DESC
            LIMIT 1
        )
        SELECT
            u.id AS user_id,
            u.name AS full_name,               -- <<<<<<  AQUI
            u.identification_number AS id_number,

            CASE
              WHEN ls.is_premium IS TRUE
              AND ls.expires_at IS NOT NULL
              AND ls.expires_at > NOW()
              THEN TRUE ELSE FALSE
            END AS is_pro,

            lp.account_type,
            b.name AS provider_name,
            lp.account_number,
            lp.account_kind AS bank_kind,
            COALESCE(lp.observations, '') AS observations

        FROM public.users u
        LEFT JOIN last_sub ls
          ON ls.user_id = u.id AND ls.rn = 1
        LEFT JOIN latest_payout lp
          ON TRUE
        LEFT JOIN public.banks b
          ON b.id = lp.bank_id
        WHERE u.id = :user_id
        LIMIT 1;
    """)

    row = db.session.execute(sql, {"user_id": user_id}).mappings().first()
    if not row:
        # Devuelve estructura vacía estándar si el usuario no existe
        return {
            "user_id": user_id,
            "full_name": "",
            "id_number": "",
            "is_pro": False,
            "payee_full_name": "",
            "payee_id_number": "",
            "account_type": "",
            "provider_name": "",
            "account_number": "",
            "bank_kind": None,
            "admin_note": "",
        }

    full_name = (row.get("full_name") or "").strip()
    id_number = (row.get("id_number") or "").strip()

    return {
        "user_id": int(row["user_id"]),
        "full_name": full_name,
        "id_number": id_number,
        "is_pro": bool(row.get("is_pro")),

        # Beneficiario: si aún no guardas titular distinto, usa el mismo usuario
        "payee_full_name": full_name,
        "payee_id_number": id_number,

        "account_type": (row.get("account_type") or ""),
        "provider_name": (row.get("provider_name") or ""),
        "account_number": (row.get("account_number") or ""),
        "bank_kind": (row.get("bank_kind") or None),
        "observations": (row.get("observations") or ""),
    }

def get_commission_request_breakdown(request_id: int) -> Dict[str, Any]:
    """
    Devuelve el desglose de una solicitud de pago (payout_request) por items de comisión.
    Requiere que referral_commissions tenga vínculo con payout_request_id.
    Respuesta:
      {
        "request_id": 501,
        "user_id": 40,                       # quien solicita el pago (referrer)
        "requested_cop": 100000,             # monto de la solicitud (en COP)
        "currency": "COP",
        "items": [
          {
            "referred_user_id": 123,         # el referido que generó la comisión
            "name": "Pedro Gomez",
            "id_number": "1010...",
            "is_pro": true,                  # confirmado que es PRO (última sub vigente)
            "commission_cop": 40000,         # aporte de este referido
            "created_at": "2025-08-31T12:00:00Z"
          },
          ...
        ],
        "items_total_cop": 100000,           # suma de items
        "matches_request": true              # true si coincide con requested_cop
      }
    """
    # 1) Trae cabecera de la solicitud
    head_sql = text("""
    SELECT
      pr.id              AS request_id,
      pr.user_id         AS referrer_user_id,
      pr.amount_micros   AS amount_micros,
      COALESCE(pr.currency_code, 'COP') AS currency,
      COALESCE(pr.admin_note, '') AS admin_note 
    FROM public.payout_requests pr
    WHERE pr.id = :rid
    LIMIT 1
""")

    head = db.session.execute(head_sql, {"rid": request_id}).mappings().first()
    if not head:
        return {"request_id": request_id, "items": [], "requested_cop": 0, "items_total_cop": 0, "matches_request": False, "currency": "COP"}

    requested_cop = _micros_to_int(head["amount_micros"])
    currency = head["currency"]

    items_sql = text("""
        WITH last_sub AS (
            SELECT
              s.user_id, s.is_premium, s.expires_at,
              ROW_NUMBER() OVER (
                PARTITION BY s.user_id
                ORDER BY COALESCE(s.expires_at, s.updated_at, s.created_at) DESC NULLS LAST
              ) AS rn
            FROM public.user_subscriptions s
        )
        SELECT
          rc.referred_user_id,
          u.public_code,
          u.name AS referred_name,
          u.identification_number AS referred_id_number,
          CASE
            WHEN ls.is_premium IS TRUE
            AND ls.expires_at IS NOT NULL
            AND ls.expires_at > NOW()
            THEN TRUE ELSE FALSE
          END AS is_pro,
          rc.commission_micros
        FROM public.referral_commissions rc
        JOIN public.users u ON u.id = rc.referred_user_id
        LEFT JOIN last_sub ls ON ls.user_id = rc.referred_user_id AND ls.rn = 1
        WHERE rc.payout_request_id = :rid
        ORDER BY rc.id ASC
    """)

    rows = db.session.execute(items_sql, {"rid": request_id}).mappings().all()

    items: List[Dict[str, Any]] = []
    items_total_cop = 0

    for r in rows:
        cop = _micros_to_int(r["commission_micros"])
        items_total_cop += cop
        items.append({
            "referred_user_id": r["referred_user_id"],
            "public_code": r["public_code"],        # 👈 agregado
            "name": r["referred_name"] or "",
            "id_number": r["referred_id_number"] or "",
            "is_pro": bool(r["is_pro"]),
            "commission_cop": cop,
            "created_at": r.get("created_at").isoformat() if r.get("created_at") else None,
        })

    return {
        "request_id": int(head["request_id"]),
        "user_id": int(head["referrer_user_id"]),
        "requested_cop": int(requested_cop),
        "currency": str(currency),
        "items": items,
        "items_total_cop": int(items_total_cop),
        "matches_request": (int(items_total_cop) == int(requested_cop)),
        "admin_note": head.get("admin_note") or "",   # 👈 nuevo
    }
