# app/services/referrals/payout_batches_service.py
# -*- coding: utf-8 -*-
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import current_app
from sqlalchemy import text
from app.db.database import db


# ---------------------------
#  Helpers internos
# ---------------------------

def _resolve_abs_path(storage_path: str) -> Path:
    """
    Convierte una ruta relativa (guardada en BD) a absoluta bajo root_path.
    Si ya es absoluta, sólo la normaliza.
    """
    path = storage_path or ""
    if not os.path.isabs(path):
        path = os.path.join(current_app.root_path, path)
    return Path(os.path.normpath(path))


def _is_admin(uid: int) -> bool:
    role_id = db.session.execute(
        text("SELECT role_id FROM public.users WHERE id = :uid"),
        {"uid": uid},
    ).scalar()
    try:
        return int(role_id or 0) == 1
    except Exception:
        return False


# ---------------------------
#  API del service
# ---------------------------

def authorize_and_get_evidence_path(*, batch_id: int, file_id: int, uid: int) -> Path:
    """
    Verifica autorización (dueño del batch o admin) y devuelve la ruta ABSOLUTA del archivo.
    Lanza ValueError si no existe o no autorizado.
    """
    is_admin = _is_admin(uid)

    q = text("""
        SELECT f.storage_path
        FROM public.payout_payment_files f
        JOIN public.payout_payment_batches b   ON b.id  = f.batch_id
        JOIN public.payout_payment_batch_items bi ON bi.batch_id = b.id
        JOIN public.payout_requests pr          ON pr.id = bi.payout_request_id
        WHERE f.id = :fid
          AND f.batch_id = :bid
          AND (:is_admin OR pr.user_id = :uid)
        LIMIT 1
    """)

    row = db.session.execute(
        q, {"fid": file_id, "bid": batch_id, "uid": uid, "is_admin": is_admin}
    ).mappings().first()

    if not row:
        raise ValueError("not_found_or_forbidden")

    p = _resolve_abs_path(row["storage_path"] or "")

    if not p.exists():
        # Fallback por cambio de extensión (.jpg ↔ .jpeg)
        cand = list(p.parent.glob(p.stem + ".*"))
        if cand:
            p = cand[0]
        else:
            raise FileNotFoundError("file_missing_on_disk")

    return p


def get_payout_batch_details(*, batch_id: int, uid: int) -> Dict[str, Any]:
    """
    Devuelve cabecera del batch, solicitudes y archivos.
    Autoriza si el usuario es admin o dueño de alguna solicitud del batch.
    Lanza ValueError si no existe/autorización fallida.
    """
    is_admin = _is_admin(uid)

    # 1) Cabecera + autorización por pertenencia
    head_sql = text("""
        SELECT b.id,
               b.created_at AT TIME ZONE 'UTC' AS created_at_utc,
               b.currency_code,
               b.total_micros,
               COUNT(bi.payout_request_id) AS items
        FROM public.payout_payment_batches b
        JOIN public.payout_payment_batch_items bi ON bi.batch_id = b.id
        JOIN public.payout_requests pr            ON pr.id = bi.payout_request_id
        WHERE b.id = :bid
          AND (:is_admin OR pr.user_id = :uid)
        GROUP BY b.id
        LIMIT 1
    """)
    head = db.session.execute(
        head_sql, {"bid": batch_id, "uid": uid, "is_admin": is_admin}
    ).mappings().first()
    if not head:
        raise ValueError("not_found_or_forbidden")

    # 2) Descubrir columnas opcionales en users (código/documento)
    cols = db.session.execute(text("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema='public' AND table_name='users'
          AND column_name IN ('public_code','document_id','document','dni','cedula','cedula_nit')
    """)).mappings().all()
    have = {c["column_name"] for c in cols}

    user_selects = [
        "u.id AS user_id",
        "COALESCE(u.name, 'Usuario') AS user_name",
    ]
    if "public_code" in have:
        user_selects.append("u.public_code AS user_code")
    else:
        user_selects.append("u.id::text AS user_code")

    doc_expr: Optional[str] = None
    for cand in ("document_id", "cedula_nit", "cedula", "dni", "document"):
        if cand in have:
            doc_expr = f"u.{cand} AS document_id"
            break
    user_selects.append(doc_expr or "NULL::text AS document_id")

    rq_sql = text(f"""
        SELECT
            pr.id AS request_id,
            pr.amount_micros,
            pr.currency_code,
            pr.created_at AT TIME ZONE 'UTC' AS created_at_utc,
            {", ".join(user_selects)}
        FROM public.payout_payment_batch_items bi
        JOIN public.payout_requests pr ON pr.id = bi.payout_request_id
        LEFT JOIN public.users u       ON u.id = pr.user_id
        WHERE bi.batch_id = :bid
        ORDER BY pr.created_at, pr.id
    """)
    rq_rows = db.session.execute(rq_sql, {"bid": batch_id}).mappings().all()

    requests: List[Dict[str, Any]] = []
    for r in rq_rows:
        currency = r["currency_code"] or "COP"
        amount = int(r["amount_micros"] or 0)
        amount_cop = amount // 1_000_000 if currency == "COP" else amount
        requests.append({
            "id": int(r["request_id"]),
            "user_id": int(r["user_id"]) if r["user_id"] is not None else None,
            "user_name": r["user_name"],
            "user_code": r["user_code"],
            "document_id": r["document_id"],
            "amount_cop": amount_cop,
            "created_at": r["created_at_utc"].isoformat() if r["created_at_utc"] else None,
        })

    # 3) Archivos
    files_sql = text("""
        SELECT id, file_name
        FROM public.payout_payment_files
        WHERE batch_id = :bid
        ORDER BY id
    """)
    files = [
        {"id": int(f["id"]), "name": f["file_name"]}
        for f in db.session.execute(files_sql, {"bid": batch_id}).mappings().all()
    ]

    # 4) Cabecera final
    currency = head["currency_code"] or "COP"
    total_val = int(head["total_micros"] or 0)
    total_cop = total_val // 1_000_000 if currency == "COP" else total_val

    return {
        "batch": {
            "id": int(head["id"]),
            "created_at": head["created_at_utc"].isoformat() if head["created_at_utc"] else None,
            "currency": currency,
            "total_cop": total_cop,
            "items": int(head["items"] or 0),
        },
        "requests": requests,
        # Nota: la URL pública se arma en route (para no acoplar a Blueprint aquí)
        "files": files,
    }
