# app/services/payouts/payouts_service.py
from __future__ import annotations

from typing import Optional, Dict, Any, List
from datetime import datetime, timezone

from sqlalchemy import text, bindparam
from app.db.database import db
from app.models.payout_request import PayoutRequest
from app.services.constants import ACTIVE_PAYOUT_REQUEST_STATUSES
import sqlalchemy as sa

# Conversión y mínimos
MICROS_PER_COP = 1_000_000
MIN_WITHDRAW_COP = 100_000
MIN_WITHDRAW_MICROS = MIN_WITHDRAW_COP * MICROS_PER_COP

# Canales permitidos (alineados con el frontend)
ALLOWED_TYPES = {"bank", "nequi", "daviplata", "bancolombia_cell", "other"}
# Tipos de cuenta bancaria (enum en DB)
ALLOWED_BANK_KINDS = {"savings", "checking"}

CURRENCY_CODE = "COP"


# ----------------------- NUEVO: helper de transacción -----------------------
# ----------------------- FIX: helper de transacción robusto -----------------------
def _begin_ctx(session):
    """
    Devuelve un context manager de transacción adecuado:
    - Si ya hay transacción activa (incl. autobegin), usa SAVEPOINT (begin_nested()).
    - Si no hay, abre una transacción normal (begin()).
    Soporta scoped_session y SQLAlchemy 1.4/2.x.
    """
    has_tx = False

    # 1) Intento: API get_transaction() (1.4/2.x)
    tx_getter = getattr(session, "get_transaction", None)
    try:
        if callable(tx_getter) and tx_getter() is not None:
            has_tx = True
    except Exception:
        pass

    # 2) Intento: preguntarle a la conexión si está en transacción (incluye autobegin)
    if not has_tx:
        try:
            conn = session.connection()
            in_tx = getattr(conn, "in_transaction", None)
            if callable(in_tx) and in_tx():
                has_tx = True
        except Exception:
            has_tx = False

    return session.begin_nested() if has_tx else session.begin()
# -------------------------------------------------------------------------------


def _validate_bank_code_return_id(bank_code: str) -> int:
    row = db.session.execute(
        text("""
            SELECT id
            FROM public.banks
            WHERE code = :code AND active = TRUE
            LIMIT 1
        """),
        {"code": bank_code},
    ).mappings().first()
    if not row:
        raise ValueError("bank_code no existe o está inactivo")
    return int(row["id"])


def _pri_schema_info() -> Dict[str, Any]:
    rows = db.session.execute(
        text("""
            SELECT column_name, is_nullable
            FROM information_schema.columns
            WHERE table_schema='public'
              AND table_name='payout_request_items'
              AND column_name IN (
                'referral_commission_id','commission_id','amount_micros','commission_micros'
              )
        """)
    ).mappings().all()
    cols = {r["column_name"]: (r["is_nullable"] == "YES") for r in rows}

    has_ref = "referral_commission_id" in cols
    has_comm = "commission_id" in cols
    if not has_ref and not has_comm:
        raise ValueError(
            "payout_request_items no tiene ni 'referral_commission_id' ni 'commission_id'"
        )

    ref_notnull = has_ref and (cols["referral_commission_id"] is False)
    comm_notnull = has_comm and (cols["commission_id"] is False)

    if "amount_micros" in cols:
        amount_col = "amount_micros"
    elif "commission_micros" in cols:
        amount_col = "commission_micros"
    else:
        amount_col = None

    return {
        "has_ref_col": has_ref,
        "has_comm_col": has_comm,
        "ref_notnull": ref_notnull,
        "comm_notnull": comm_notnull,
        "amount_col": amount_col,
    }


def _pick_available_commissions(user_id: int, schema: Dict[str, Any]) -> List[Dict[str, Any]]:
    sql = text("""
        SELECT rc.id, rc.commission_micros
        FROM public.referral_commissions rc
        WHERE rc.referrer_user_id = :uid
          AND (
                rc.status = 'available'
             OR (
                    rc.status = 'pending'
                AND (rc.event_time IS NULL OR rc.event_time <= now() - interval '3 days')
             )
          )
          AND NOT EXISTS (
                SELECT 1
                FROM public.payout_request_items pri
                JOIN public.payout_requests pr
                  ON pr.id = pri.payout_request_id
                WHERE (pri.referral_commission_id = rc.id OR pri.commission_id = rc.id)
                  AND pr.user_id = :uid
                  AND pr.status::text IN :active_statuses
          )
        ORDER BY rc.event_time ASC NULLS LAST, rc.id ASC
        FOR UPDATE SKIP LOCKED
    """).bindparams(
        bindparam("active_statuses", expanding=True),
    )

    params = {
        "uid": user_id,
        "active_statuses": ACTIVE_PAYOUT_REQUEST_STATUSES,  # ['requested','approved','pending']
    }

    rows = db.session.execute(sql, params).mappings().all()
    return [dict(r) for r in rows]


def _cleanup_stale_items_for_user(user_id: int):
    db.session.execute(
        sa.text("""
            DELETE FROM payout_request_items pri
            USING payout_requests pr
            WHERE pri.payout_request_id = pr.id
              AND pr.user_id = :uid
              AND pr.status IN ('cancelled','rejected')
        """),
        {"uid": user_id},
    )


def create_payout_request(
    *,
    user_id: int,
    account_type: str,
    account_number: str,
    account_kind: Optional[str] = None,
    bank_code: Optional[str] = None,
    observations: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Crea una solicitud de retiro dentro de una transacción segura:
      1) Bloquea comisiones retirables (FOR UPDATE SKIP LOCKED).
      2) Inserta payout_requests.
      3) Inserta payout_request_items respetando columnas reales.
      4) Marca esas comisiones como 'in_withdrawal'.
    El commit/rollback lo maneja el context manager.
    """
    # ---------- Validaciones previas ----------
    atype = (account_type or "").lower().strip()
    if atype not in ALLOWED_TYPES:
        raise ValueError("account_type inválido")

    num = (account_number or "").strip()
    if not num:
        raise ValueError("account_number requerido")

    notes = (observations or "").strip() or None
    if notes and len(notes) > 500:
        raise ValueError("observations demasiado largas (máx 500)")

    bank_id: Optional[int] = None

    if atype in {"nequi", "daviplata", "bancolombia_cell"}:
        if not num.isdigit() or len(num) != 10:
            raise ValueError("Número de celular inválido (debe tener 10 dígitos)")
        account_kind = None
        bank_code = None
    elif atype == "bank":
        ak = (account_kind or "").lower().strip()
        if ak not in ALLOWED_BANK_KINDS:
            raise ValueError("account_kind requerido para cuenta bancaria (savings/checking)")
        if not num.isdigit() or len(num) < 5:
            raise ValueError("Número de cuenta inválido (sólo dígitos, mín. 5)")
        if not bank_code:
            raise ValueError("bank_code requerido para cuenta bancaria")
        bank_id = _validate_bank_code_return_id(bank_code.strip().upper())
        account_kind = ak
    else:
        if len(num) < 5:
            raise ValueError("account_number inválido")
        account_kind = None
        bank_code = None

    # ---------- Trabajo con DB ----------
    now = datetime.now(timezone.utc)
    schema = _pri_schema_info()

    # ⚠️ Todo el flujo atómico
    with _begin_ctx(db.session):
        # 1) Tomar comisiones retirables (queda protegido por la transacción)
        items = _pick_available_commissions(user_id, schema)
        total_micros = sum(int(i["commission_micros"] or 0) for i in items)

        if total_micros < MIN_WITHDRAW_MICROS:
            disponible_cop = total_micros // MICROS_PER_COP
            raise ValueError(
                f"Tu saldo disponible es {disponible_cop} COP y el mínimo de retiro es {MIN_WITHDRAW_COP} COP."
            )
        if total_micros <= 0:
            raise ValueError("No tienes comisiones disponibles para retirar.")

        # 2) Crear la solicitud
        req = PayoutRequest(
            user_id=user_id,
            account_type=atype,
            account_kind=account_kind,
            bank_id=bank_id,
            account_number=num,
            amount_micros=total_micros,
            currency_code=CURRENCY_CODE,
            status="requested",
            observations=notes,
            requested_at=now,
            created_at=now,
            updated_at=now,
        )
        db.session.add(req)
        db.session.flush()  # necesitamos req.id

        # Limpia ítems viejos de solicitudes canceladas/rechazadas (mismo usuario)
        _cleanup_stale_items_for_user(user_id)

        # 3) INSERT dinámico del detalle respetando NOT NULL
        cols = ["payout_request_id"]
        vals = [":rid"]

        if schema["has_ref_col"] and schema["has_comm_col"]:
            cols += ["referral_commission_id", "commission_id"]
            vals += [":cid", ":cid"]
        elif schema["has_ref_col"]:
            cols += ["referral_commission_id"]
            vals += [":cid"]
        else:
            cols += ["commission_id"]
            vals += [":cid"]

        if schema["amount_col"]:
            cols.append(schema["amount_col"])
            vals.append(":amt")

        conflict_sql = "ON CONFLICT (commission_id) DO NOTHING" if schema["has_comm_col"] else "ON CONFLICT DO NOTHING"

        insert_sql = text(
            f"""
            INSERT INTO public.payout_request_items
                ({", ".join(cols)})
            VALUES ({", ".join(vals)})
            {conflict_sql}
            """
        )

        for it in items:
            params = {"rid": req.id, "cid": it["id"]}
            if schema["amount_col"]:
                params["amt"] = it["commission_micros"]
            db.session.execute(insert_sql, params)

            # 4) Marcar comisión como EN RETIRO y vincularla al request
            db.session.execute(
                text("""
                    UPDATE public.referral_commissions
                    SET status = 'in_withdrawal',
                        payout_request_id = :rid
                    WHERE id = :cid
                """),
                {"cid": it["id"], "rid": req.id},
            )


        # (commit automático al salir del with)

        return {
            "id": req.id,
            "amount_micros": total_micros,
            "currency_code": CURRENCY_CODE,
            "status": "requested",
            "requested_at": now.isoformat(),
        }


def list_commission_requests(
    *,
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    allowed_status = {"requested", "processing", "paid", "rejected", "approved", "pending"}
    where_status = ""
    params: Dict[str, Any] = {"limit": max(1, min(limit, 200)), "offset": max(0, offset)}

    if status:
        st = status.strip().lower()
        if st not in allowed_status:
            raise ValueError("status inválido")
        where_status = "AND pr.status::text = :status"
        params["status"] = st

    sql = text(f"""
        SELECT
            pr.id,
            pr.user_id,
            u.name AS user_name,
            to_char(pr.created_at AT TIME ZONE 'UTC', 'Mon YYYY') AS month_label,
            pr.amount_micros,
            pr.currency_code AS currency,
            pr.status::text    AS status,
            pr.created_at
        FROM public.payout_requests pr
        LEFT JOIN public.users u ON u.id = pr.user_id
        WHERE 1=1
          {where_status}
        ORDER BY pr.created_at DESC, pr.id DESC
        LIMIT :limit OFFSET :offset
    """)

    rows = db.session.execute(sql, params).mappings().all()
    return [
        {
            "id": int(r["id"]),
            "user_id": int(r["user_id"]),
            "user_name": (r["user_name"] or "Usuario").strip(),
            "month_label": (r["month_label"] or "").strip(),
            "amount_micros": int(r["amount_micros"] or 0),
            "currency": (r["currency"] or "COP"),
            "status": (r["status"] or "").strip(),
            "created_at": (r["created_at"].isoformat() if r["created_at"] else None),
        }
        for r in rows
    ]
