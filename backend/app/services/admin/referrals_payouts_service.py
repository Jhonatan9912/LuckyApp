# -*- coding: utf-8 -*-
from __future__ import annotations
from typing import List, Dict, Any, Tuple, Optional
import os, uuid
from werkzeug.datastructures import FileStorage
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from app.db.database import db
from flask import current_app
from datetime import timezone
from pathlib import Path
from werkzeug.utils import secure_filename

ISO_KEYS = ("requested_at", "updated_at", "processed_at", "created_at")

def _to_iso_utc(dt):
    if dt is None:
        return None
    try:
        return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        # si viene ya como string, lo dejamos tal cual
        return str(dt)

def _isoify_record(d: Dict[str, Any], keys=ISO_KEYS) -> Dict[str, Any]:
    out = dict(d)
    for k in keys:
        v = out.get(k)
        if hasattr(v, "isoformat"):
            out[k] = _to_iso_utc(v)
    return out
# =========================================================
#  CONFIG
# =========================================================
_MICROS = 1_000_000

def _upload_dir_pair() -> tuple[Path, str]:
    """
    Devuelve (base_abs, base_rel):
    - base_abs: ruta ABSOLUTA bajo current_app.root_path (donde se guarda el archivo)
    - base_rel: ruta RELATIVA que se guarda en BD (ej: 'storage/payment_files')
    """
    rel = current_app.config.get("PAYMENT_UPLOAD_DIR") or os.environ.get("PAYMENT_UPLOAD_DIR")
    if not rel:
        rel = os.path.join("storage", "payment_files")  # default relativo

    # normaliza a estilo POSIX para BD
    base_rel = rel.replace("\\", "/").strip("/")

    base_abs = Path(current_app.root_path) / base_rel
    base_abs.mkdir(parents=True, exist_ok=True)
    return base_abs, base_rel

def _save_upload(file: FileStorage) -> tuple[str, int, str]:
    """
    Guarda el archivo en base_abs y devuelve:
      - storage_path_rel (para BD), p.ej. 'storage/payment_files/<uuid>.jpeg'
      - size_bytes
      - mime_type
    """
    base_abs, base_rel = _upload_dir_pair()

    safe_name = secure_filename(file.filename or "")
    ext = Path(safe_name).suffix.lower() or ""
    fname = f"{uuid.uuid4().hex}{ext}"

    full_path = base_abs / fname
    file.save(str(full_path))

    size = full_path.stat().st_size
    mime = file.mimetype or "application/octet-stream"

    storage_path_rel = f"{base_rel}/{fname}"  # ← lo que irá a la BD (relativo)
    return storage_path_rel, size, mime

# =========================================================
#  UTILIDADES (maturity)
# =========================================================
def get_maturity_days() -> int:
    env = (os.getenv("ENV", "") or "").lower()
    if env in ("dev", "sandbox", "staging"):
        return int(os.getenv("MATURITY_DAYS", "1"))
    return int(os.getenv("MATURITY_DAYS", "3"))

def mature_commissions(days: int | None = None, minutes: int | None = None) -> int:
    """
    Promueve comisiones a 'available' si aplica (placeholder si tus rutas lo llaman).
    Si no tienes lógica aquí, devuelve 0 sin hacer nada.
    """
    # Si ya tienes una versión real en otro módulo, puedes moverla aquí.
    return 0

# =========================================================
#  FUNCIONES QUE ESPERAN TUS RUTAS ADMIN
#  (sin depender de app.services.referrals.payouts_service)
# =========================================================

def list_commission_requests(
    status: Optional[str] = None,
    user_id: Optional[int] = None,
    q: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    order: str = "pr.requested_at DESC",
) -> Dict[str, Any]:
    """
    Lista solicitudes en payout_requests con filtros básicos.
    Devuelve {"items":[...], "total": int}
    Incluye account_type/account_kind traducidos al ES y los crudos *_raw.
    """
    where = ["1=1"]
    params: Dict[str, Any] = {}

    if status:
        where.append("pr.status = :status")
        params["status"] = status

    if user_id is not None:
        where.append("pr.user_id = :user_id")
        params["user_id"] = int(user_id)

    if q:
        where.append(
            "(pr.account_number ILIKE :q "
            "OR COALESCE(pr.user_note,'') ILIKE :q "
            "OR COALESCE(pr.admin_note,'') ILIKE :q)"
        )
        params["q"] = f"%{q}%"

    where_sql = " AND ".join(where)
    order_sql = order if order.strip() else "pr.requested_at DESC"

    sql_items = text(f"""
        SELECT
            pr.id,
            pr.user_id,
            u.name AS user_name,

            -- valores crudos
            pr.account_type::text AS account_type_raw,
            pr.account_kind::text AS account_kind_raw,

            -- etiquetas en español
            CASE LOWER(COALESCE(pr.account_type::text, ''))
                WHEN 'bank'      THEN 'Banco'
                WHEN 'nequi'     THEN 'Nequi'
                WHEN 'daviplata' THEN 'Daviplata'
                ELSE COALESCE(pr.account_type::text, '')
            END AS account_type,

            pr.bank_id,

            CASE LOWER(COALESCE(pr.account_kind::text, ''))
                WHEN 'savings'  THEN 'Ahorros'
                WHEN 'saving'   THEN 'Ahorros'
                WHEN 'checking' THEN 'Corriente'
                WHEN 'current'  THEN 'Corriente'
                ELSE COALESCE(pr.account_kind::text, '')
            END AS account_kind,

            pr.account_number,
            pr.amount_micros,
            pr.currency_code,
            pr.status,
            pr.user_note,
            pr.admin_note,
            pr.requested_at,
            pr.updated_at,
            pr.processed_at,
            pr.observations,
            pr.created_at
        FROM public.payout_requests pr
        LEFT JOIN public.users u ON u.id = pr.user_id
        WHERE {where_sql}
        ORDER BY {order_sql}
        LIMIT :limit OFFSET :offset
    """)

    params["limit"] = int(limit)
    params["offset"] = int(offset)

    rows = db.session.execute(sql_items, params).mappings().all()
    items = [_isoify_record(dict(r)) for r in rows]

    sql_count = text(f"""
        SELECT COUNT(*) AS c
        FROM public.payout_requests pr
        WHERE {where_sql}
    """)
    total = int(db.session.execute(sql_count, params).scalar() or 0)

    return {
        "items": items,
        "total": total,
        "limit": int(limit),
        "offset": int(offset),
    }

def approve_commission_request(request_id: int, admin_user_id: Optional[int] = None, note: str = "") -> Dict[str, Any]:
    """
    Marca una solicitud como 'requested' (aprobada para pago) y deja nota de admin.
    Si prefieres flujo 'approved' → luego batch paga, ajusta al valor de enum que uses.
    """
    sql = text("""
        UPDATE public.payout_requests
        SET status = 'requested',
            admin_note = COALESCE(:note, admin_note),
            updated_at = NOW()
        WHERE id = :id
        RETURNING id, status, updated_at
    """)
    row = db.session.execute(sql, {"id": int(request_id), "note": note or ""}).mappings().first()
    if not row:
        raise ValueError(f"Solicitud {request_id} no existe")
    return _isoify_record(dict(row), keys=("updated_at",))


def reject_commission_request(request_id: int, admin_user_id: Optional[int] = None, reason: str = "") -> Dict[str, Any]:
    """
    Rechaza la solicitud (status = 'rejected') y guarda razón en admin_note.
    """
    sql = text("""
        UPDATE public.payout_requests
        SET status = 'rejected',
            admin_note = COALESCE(:reason, admin_note),
            updated_at = NOW()
        WHERE id = :id
        RETURNING id, status, updated_at
    """)
    row = db.session.execute(sql, {"id": int(request_id), "reason": reason or ""}).mappings().first()
    if not row:
        raise ValueError(f"Solicitud {request_id} no existe")
    return _isoify_record(dict(row), keys=("updated_at",))

# =========================================================
#  PAGAR: crear lote y marcar requests como 'paid'
# =========================================================
def create_payment_batch(
    request_ids: List[int],
    note: str = "",
    files: List[FileStorage] | None = None,
    admin_user_id: int | None = None,
) -> Dict[str, Any]:
    """
    Crea un lote de pago con evidencias. Marca payout_requests como 'paid' de forma atómica.
    Requiere que las solicitudes estén en 'requested'.
    """
    if not request_ids:
        raise ValueError("Debes enviar al menos un payout_request_id")

    request_ids = list(dict.fromkeys(int(x) for x in request_ids))  # dedup + cast

    with db.session.begin_nested():
        # 1) Lock de solicitudes
        lock_sql = text("""
            SELECT id, user_id, amount_micros, currency_code, status
            FROM public.payout_requests
            WHERE id = ANY(:ids)
            FOR UPDATE
        """)
        rows = db.session.execute(lock_sql, {"ids": request_ids}).mappings().all()
        if len(rows) != len(request_ids):
            faltantes = set(request_ids) - {r["id"] for r in rows}
            raise ValueError(f"Solicitudes inexistentes: {sorted(faltantes)}")

        allowed = {"requested"}  # ajusta si quieres permitir 'approved'
        bad_status = [r["id"] for r in rows if (r["status"] or "") not in allowed]
        if bad_status:
            raise ValueError(f"Solo se pueden pagar solicitudes en estado 'requested'. No válidas: {bad_status}")

        currencies = {(r["currency_code"] or "COP") for r in rows}
        if len(currencies) > 1:
            raise ValueError(f"Moneda mixta no soportada en el mismo lote: {sorted(currencies)}")
        currency = currencies.pop() if currencies else "COP"

        total_micros = sum(int(r["amount_micros"] or 0) for r in rows)
        if total_micros <= 0:
            raise ValueError("El total del lote debe ser mayor que 0")

        # 2) Cabecera del lote
        ins_batch = text("""
            INSERT INTO public.payout_payment_batches
                (admin_user_id, status, total_micros, currency_code, note, confirmed_at)
            VALUES (:admin_user_id, 'confirmed', :total_micros, :currency, :note, NOW())
            RETURNING id, created_at
        """)
        batch = db.session.execute(ins_batch, {
            "admin_user_id": admin_user_id,
            "total_micros": int(total_micros),
            "currency": currency,
            "note": note or "",
        }).mappings().first()
        batch_id = batch["id"]

        # 3) Items del lote
        ins_item = text("""
            INSERT INTO public.payout_payment_batch_items
                (batch_id, payout_request_id, amount_micros)
            VALUES (:bid, :rid, :amt)
            ON CONFLICT DO NOTHING
        """)
        for r in rows:
            db.session.execute(ins_item, {"bid": batch_id, "rid": r["id"], "amt": int(r["amount_micros"] or 0)})

        # 4) Archivos (si hay)
        if files:
            ins_file = text("""
                INSERT INTO public.payout_payment_files
                    (batch_id, file_name, mime_type, size_bytes, storage_path)
                VALUES (:bid, :fname, :mime, :size, :path)
            """)
            for f in files:
                if not f or (f.filename or "").strip() == "":
                    continue
                path, size, mime = _save_upload(f)  # AHORA 'path' ES RELATIVO
                db.session.execute(ins_file, {
                    "bid": batch_id,
                    "fname": os.path.basename(f.filename or ""),  # nombre original
                    "mime": mime,
                    "size": int(size),
                    "path": path,  # ← guarda 'storage/payment_files/<uuid>.<ext>'
                })
               # 5) Marcar solicitudes como pagadas
        upd = text("""
            UPDATE public.payout_requests
            SET status = 'paid',
                processed_at = NOW(),
                updated_at = NOW()
            WHERE id = ANY(:ids)
        """)
        db.session.execute(upd, {"ids": request_ids})

        # 5.1) Marcar comisiones involucradas como 'paid'
        # 5.1.a) Si las comisiones apuntan directo al request
        db.session.execute(text("""
            UPDATE referral_commissions
            SET status = 'paid'
            WHERE payout_request_id = ANY(:ids)
        """), {"ids": request_ids})

        # 5.1.b) Si existe tabla intermedia payout_request_items, actualizar por join
        pri_exists = db.session.execute(text("""
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema='public' AND table_name='payout_request_items'
            LIMIT 1
        """)).scalar() is not None

        if pri_exists:
            db.session.execute(text("""
                UPDATE referral_commissions rc
                SET status = 'paid'
                FROM payout_request_items pri
                WHERE pri.payout_request_id = ANY(:ids)
                  AND rc.id = COALESCE(pri.commission_id, pri.referral_commission_id)
            """), {"ids": request_ids})

        # 6.1) Obtener archivos del batch para el payload (evidencias)
        files_meta = db.session.execute(text("""
            SELECT id, file_name, storage_path
            FROM public.payout_payment_files
            WHERE batch_id = :bid
            ORDER BY id
        """), {"bid": batch_id}).mappings().all()

        # 6.2) Traer datos bancarios / cuenta de cada request para enmascarar
        req_info = db.session.execute(text("""
            SELECT id, user_id, account_number, amount_micros, currency_code
            FROM public.payout_requests
            WHERE id = ANY(:ids)
        """), {"ids": request_ids}).mappings().all()

        import json as _json

        def _mask_account(acc: str | None) -> str:
            s = (acc or "").strip()
            if len(s) <= 4:
                return "****"
            return "****" + s[-4:]

        # 6.3) Notificar a cada usuario
        notify_sql = text("""
            INSERT INTO public.notifications
                (user_id, title, body, data, is_read, created_at)
            VALUES
                (:uid, :title, :body, CAST(:data AS JSONB), FALSE, NOW())
        """)

        for r in req_info:
            uid = int(r["user_id"])
            amt_micros = int(r["amount_micros"] or 0)
            currency = (r["currency_code"] or "COP").upper()
            amount_cop = amt_micros // 1_000_000 if currency == "COP" else amt_micros

            payload = {
                "type": "withdrawal_paid",
                "payout_request_id": int(r["id"]),
                "batch_id": int(batch_id),
                "amount": amount_cop,
                "currency": currency,
                "amount_cop": amount_cop if currency == "COP" else None,
                "account_masked": _mask_account(r["account_number"]),
                "note": (note or ""),
                "paid_at": batch["created_at"].astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
                "files": [
                    {
                        "id": int(f["id"]),
                        "name": f["file_name"],
                        "url": f"/api/referrals/payout-batches/{batch_id}/files/{int(f['id'])}",
                    }
                    for f in files_meta
                ],
            }

            title = "Pago de retiro confirmado"
            body = f"Se pagó {amount_cop:,} {currency} a tu cuenta {payload['account_masked']}.".replace(",", ".")

            try:
                db.session.execute(
                    notify_sql,
                    {
                        "uid": uid,
                        "title": title,
                        "body": body,
                        "data": _json.dumps(payload, ensure_ascii=False),
                    },
                )
            except Exception as e:
                current_app.logger.warning("notify insert failed for user %s: %s", uid, e)

        return {
            "batch_id": int(batch_id),
            "total_micros": int(total_micros),
            "currency": currency,
            "request_ids": request_ids,
            "files_count": len(files or []),
            "created_at": batch["created_at"].isoformat(),
        }

# === Aliases extra para compatibilidad con rutas existentes ===
def approve_payout_request(*args, **kwargs):
    return approve_commission_request(*args, **kwargs)

def reject_payout_request(*args, **kwargs):
    return reject_commission_request(*args, **kwargs)
