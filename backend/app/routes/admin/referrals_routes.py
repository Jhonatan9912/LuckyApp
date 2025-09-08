# app/routes/admin/referrals_routes.py
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from flask import current_app
from . import bp  # blueprint del paquete admin
from app.services.admin.referrals_service import get_referrals_summary
from werkzeug.exceptions import BadRequest
from app.services.admin.referrals_service import get_commission_request_breakdown
from app.services.admin.referrals_payouts_service import (
    list_commission_requests,
    create_payment_batch,           # pagar (con evidencias) sigue aquí
)
# 👇 rechazar debe venir del servicio core, que restaura 'available' y notifica
from app.services.referrals.payouts_service import reject_payout_request
from pathlib import Path
from flask import send_file

# ---------------------------------------------------------------------
# GET /api/admin/referrals/summary  -> resumen global (o por referrer_id)
# ---------------------------------------------------------------------
@bp.get("/referrals/summary")
@jwt_required()
def referrals_summary():
    """
    Devuelve:
      { ok: true, total: N, active: M, inactive: K }

    Opcional:
      ?referrer_id=<id>  filtra por el promotor (si lo necesitas)
    """
    # ---- Guard: solo administradores ----
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if role_id is None:
        uid = get_jwt_identity()
        role_id = db.session.execute(
            text("SELECT role_id FROM users WHERE id=:uid"),
            {"uid": uid},
        ).scalar()

    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    # ---- Parámetro opcional ----
    referrer_id = request.args.get("referrer_id", type=int)

    # ---- Lógica de negocio ----
    summary = get_referrals_summary(referrer_id=referrer_id)

    return jsonify({"ok": True, **summary})

@bp.get("/referrals/top")
@jwt_required()
def referrals_top():
    """
    Devuelve el top de referidores con más referidos activos.
    """
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")

    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    from app.services.admin.referrals_service import get_top_referrers
    top = get_top_referrers(limit=5)

    return jsonify({"ok": True, "items": top})

@bp.get("/referrals/commission-requests")
@jwt_required()
def admin_list_commission_requests():
    """
    Lista solicitudes para el panel Admin.
    Query:
      - status: requested|processing|paid|rejected|approved|pending
      - limit, offset
      - flat=1 para devolver lista plana
    """
    try:
        status = request.args.get("status")
        limit = int(request.args.get("limit", "50"))
        offset = int(request.args.get("offset", "0"))

        res = list_commission_requests(status=status, limit=limit, offset=offset)
        # res = {"items":[...], "total":..., "limit":..., "offset":...}

        # Si piden lista plana (?flat=1), devolver solo la lista
        if (request.args.get("flat") or "").lower() in ("1", "true", "yes"):
            return jsonify(res.get("items", [])), 200

        # Por compatibilidad con clientes que esperan {ok, items:[...]}
        return jsonify({"ok": True, "items": res.get("items", []), "total": res.get("total", 0)}), 200

    except ValueError as ve:
        raise BadRequest(str(ve))
    except Exception as e:
        current_app.logger.exception("admin_list_commission_requests failed")
        return jsonify({"ok": False, "error": str(e)}), 500

@bp.get("/referrals/__ping__")
@jwt_required()
def admin_referrals_ping():
    return jsonify({"ok": True, "msg": "admin referrals routes loaded"}), 200

@bp.get("/referrals/user-detail/<int:user_id>")
@jwt_required()
def admin_get_user_detail(user_id: int):
    """
    Devuelve detalle del usuario para el modal 'Ver usuario':
      nombres, identificación, flag PRO y datos bancarios más recientes.
    """
    # Guard: solo admin
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        from app.services.admin.referrals_service import get_admin_user_detail
        item = get_admin_user_detail(user_id)
        return jsonify({"ok": True, "item": item}), 200
    except Exception as e:
        current_app.logger.exception("admin_get_user_detail failed")
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.get("/referrals/commission-requests/<int:request_id>/breakdown")
@jwt_required()
def admin_commission_request_breakdown(request_id: int):
    """
    Devuelve el desglose de la solicitud (usuarios que generaron la comisión).
    Respuesta:
      { ok: true, item: { request_id, user_id, requested_cop, items:[...], items_total_cop, matches_request, currency } }
    """
    # Guard: solo admin
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        data = get_commission_request_breakdown(request_id)
        return jsonify({"ok": True, "item": data}), 200
    except Exception as e:
        current_app.logger.exception("admin_commission_request_breakdown failed")
        return jsonify({"ok": False, "error": str(e)}), 500
    
    # ---------------------------------------------------------------------
# POST /api/admin/referrals/payout-requests/:id/reject
#   body: { "reason": "texto del motivo" }
# ---------------------------------------------------------------------
@bp.post("/referrals/payout-requests/<int:request_id>/reject")
@jwt_required()
def admin_reject_payout_request(request_id: int):
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    body = request.get_json(silent=True) or {}
    reason = (body.get("reason") or "").strip()
    admin_id = get_jwt_identity()

    try:
        out = reject_payout_request(
        request_id=request_id,
        reason=reason,
        admin_id=admin_id,   # <- el core espera admin_id (no admin_user_id)
    )
        db.session.commit()   # 👈 commit real del request HTTP
        return jsonify({"ok": True, "item": out}), 200
    except BadRequest as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("admin_reject_payout_request failed")
        return jsonify({"ok": False, "error": str(e)}), 500

@bp.post("/referrals/payout-batches")
@jwt_required()
def admin_create_payout_batch():
    """
    Crea un lote de pagos a partir de payout_requests seleccionados.
    Acepta:
      - JSON: { "request_ids": [int,...], "note": "texto" }  (sin archivos)
      - multipart/form-data:
          request_ids: puede venir varias veces o como JSON string
          note: texto
          files: múltiples archivos (input name="files")
    Responde:
      { ok: true, item: { batch_id, total_micros, currency, request_ids, files_count, created_at } }
    """
    # Guard: solo admin
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    admin_id = get_jwt_identity()

    try:
        req_ids = []       # lista de ints
        note = ""
        files = None       # lista de FileStorage o None

        # 1) Si es multipart (con adjuntos)
        if request.content_type and "multipart/form-data" in request.content_type.lower():
            import json as _json

            # 1) recolecta posibles variantes de campos repetidos
            raw_list = []
            raw_list += request.form.getlist("request_ids")
            raw_list += request.form.getlist("request_ids[]")
            raw_list += request.form.getlist("ids")
            raw_list += request.form.getlist("ids[]")

            if raw_list:
                # ✅ si vino UN SOLO campo y parece JSON -> parsear JSON
                if len(raw_list) == 1 and raw_list[0].strip().startswith("["):
                    req_ids = [int(x) for x in _json.loads(raw_list[0])]
                else:
                    # caso: varios campos repetidos request_ids=19 & request_ids=27
                    req_ids = [int(x) for x in raw_list if str(x).strip() != ""]
            else:
                # ✅ también acepta un único campo JSON
                payload = (request.form.get("request_ids") or
                           request.form.get("request_ids[]") or
                           request.form.get("ids") or
                           request.form.get("ids[]") or "").strip()
                if payload.startswith("["):
                    req_ids = [int(x) for x in _json.loads(payload)]
                elif "," in payload:
                    req_ids = [int(x) for x in payload.split(",") if x.strip()]
                else:
                    req_ids = []

            note = (request.form.get("note") or "").strip()
            files = request.files.getlist("files")

        else:
            # 2) JSON puro (sin archivos)
            body = request.get_json(silent=True) or {}
            req_ids = [int(x) for x in (body.get("request_ids") or [])]
            note = (body.get("note") or "").strip()
            files = None

        if not req_ids:
            raise BadRequest("Debes enviar al menos un request_id")

        item = create_payment_batch(
            request_ids=req_ids,
            note=note,
            files=files,
            admin_user_id=admin_id,
        )
        # commit explícito del request
        db.session.commit()
        return jsonify({"ok": True, "item": item}), 200

    except BadRequest as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("admin_create_payout_batch failed")
        return jsonify({"ok": False, "error": str(e)}), 500
    
from sqlalchemy import text

@bp.get("/referrals/payout-batches")
@jwt_required()
def admin_list_payout_batches():
    # Guard admin
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        limit  = int(request.args.get("limit",  "50"))
        offset = int(request.args.get("offset", "0"))

        sql = text("""
            WITH base AS (
            SELECT
                pb.id,
                pb.created_at,
                pb.currency_code AS currency,
                COALESCE(
                pb.total_micros,
                SUM(COALESCE(pbi.amount_micros, pr.amount_micros))
                ) AS total_micros,
                COUNT(DISTINCT pbi.payout_request_id) AS requests_count,
                MIN(pr.user_id)           AS first_user_id,
                MIN(u.name)               AS first_user_name,
                MIN(u.public_code)        AS first_user_code,        -- 👈 NUEVO
                EXISTS (
                SELECT 1 FROM payout_payment_files pf WHERE pf.batch_id = pb.id
                ) AS has_files
            FROM payout_payment_batches pb
            LEFT JOIN payout_payment_batch_items pbi ON pbi.batch_id = pb.id
            LEFT JOIN payout_requests pr            ON pr.id = pbi.payout_request_id
            LEFT JOIN users u                       ON u.id = pr.user_id
            GROUP BY pb.id, pb.created_at, pb.currency_code, pb.total_micros
            )
            SELECT
            id,
            created_at,
            currency,
            requests_count                                   AS items,
            (total_micros / 1000000)::bigint                 AS total_cop,
            has_files,
            first_user_id,
            first_user_name,
            first_user_code,                                  -- 👈 NUEVO
            ('PB-' || lpad(id::text, 6, '0'))               AS code
            FROM base
            ORDER BY id DESC
            LIMIT :limit OFFSET :offset
        """)


        rows = db.session.execute(sql, {"limit": limit, "offset": offset}).mappings().all()

        items = []
        for r in rows:
            items.append({
                "id":           int(r["id"]),
                "created_at":   r["created_at"].isoformat() if r["created_at"] else None,
                "currency":     r["currency"] or "COP",
                "items":        int(r["items"] or 0),
                "total_cop":    int(r["total_cop"] or 0),
                "has_files":    bool(r["has_files"]),
                "first_user_id":   int(r["first_user_id"]) if r["first_user_id"] is not None else None,
                "first_user_name": r["first_user_name"],
                "first_user_code": r["first_user_code"],     # 👈 NUEVO
                "code":            r["code"],
            })


        return jsonify(items), 200   # tu Flutter ya soporta lista “plana”
    except Exception as e:
        current_app.logger.exception("admin_list_payout_batches failed")
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.get("/referrals/payout-batches/<int:batch_id>/details")
@jwt_required()
def admin_payout_batch_details(batch_id: int):
    # Guard admin
    claims = get_jwt() or {}
    role_id = claims.get("role_id") or claims.get("rid") or claims.get("role")
    if int(role_id or 0) != 1:
        return jsonify({"ok": False, "error": "Solo administradores"}), 403

    try:
        # HEAD
        head_sql = text("""
            WITH head AS (
              SELECT
                pb.id,
                pb.created_at,
                pb.currency_code AS currency,
                COUNT(DISTINCT pbi.payout_request_id) AS items,
                COALESCE(pb.total_micros, SUM(COALESCE(pbi.amount_micros, pr.amount_micros))) AS total_micros
              FROM payout_payment_batches pb
              LEFT JOIN payout_payment_batch_items pbi ON pbi.batch_id = pb.id
              LEFT JOIN payout_requests pr            ON pr.id = pbi.payout_request_id
              WHERE pb.id = :bid
              GROUP BY pb.id, pb.created_at, pb.currency_code, pb.total_micros
            )
            SELECT id, created_at, currency, items,
                   (total_micros / 1000000)::bigint AS total_cop
            FROM head
        """)
        h = db.session.execute(head_sql, {"bid": batch_id}).mappings().first()
        if not h:
            return jsonify({"ok": False, "error": "Batch no encontrado"}), 404

        batch = {
            "id":         int(h["id"]),
            "created_at": h["created_at"].isoformat() if h["created_at"] else None,
            "currency":   h["currency"] or "COP",
            "total_cop":  int(h["total_cop"] or 0),
            "items":      int(h["items"] or 0),
        }

        # REQUESTS
        req_sql = text("""
            SELECT
              pr.id                                         AS request_id,
              pr.user_id,
              u.name                                        AS user_name,
              u.public_code                                 AS user_code,
              u.identification_number                       AS document_id,
              (COALESCE(pbi.amount_micros, pr.amount_micros) / 1000000)::bigint AS amount_cop,
              pr.requested_at                                AS created_at
            FROM payout_payment_batch_items pbi
            JOIN payout_requests pr ON pr.id = pbi.payout_request_id
            LEFT JOIN users u        ON u.id = pr.user_id
            WHERE pbi.batch_id = :bid
            ORDER BY pr.id
        """)
        req_rows = db.session.execute(req_sql, {"bid": batch_id}).mappings().all()
        requests = [{
            "id":          int(r["request_id"]),
            "user_id":     int(r["user_id"]) if r["user_id"] is not None else None,
            "user_name":   r["user_name"],
            "user_code":   r["user_code"],
            "document_id": r["document_id"],
            "amount_cop":  int(r["amount_cop"] or 0),
            "created_at":  r["created_at"].isoformat() if r["created_at"] else None,
        } for r in req_rows]

        # FILES
        files_sql = text("""
            SELECT id, file_name, storage_path
            FROM payout_payment_files
            WHERE batch_id = :bid
            ORDER BY id
        """)
        file_rows = db.session.execute(files_sql, {"bid": batch_id}).mappings().all()
        files = [{
            "id":   int(f["id"]),
            "name": f["file_name"],
            # URL relativa servida por otra ruta (ajústala si ya tienes una distinta)
            "url":  f"/api/admin/referrals/payout-batches/{batch_id}/files/{int(f['id'])}",
            # "path": f["storage_path"],  # si te sirve para debug
        } for f in file_rows]

        return jsonify({"ok": True, "item": {
            "batch": batch,
            "requests": requests,
            "files": files,
        }}), 200

    except Exception as e:
        current_app.logger.exception("admin_payout_batch_details failed")
        return jsonify({"ok": False, "error": str(e)}), 500

# app/routes/admin/referrals_routes.py
from pathlib import Path
import os, mimetypes
...
@bp.get("/referrals/payout-batches/<int:batch_id>/files/<int:file_id>")
@jwt_required()
def admin_download_payout_file(batch_id: int, file_id: int):
    row = db.session.execute(text("""
        SELECT file_name, mime_type, storage_path
        FROM payout_payment_files
        WHERE id = :fid AND batch_id = :bid
    """), {"fid": file_id, "bid": batch_id}).mappings().first()
    if not row:
        return jsonify({"ok": False, "error": "file_not_found"}), 404

    storage_path = (row["storage_path"] or "").strip()

    # === NUEVO: resolver rutas de forma consistente ===
    def resolve_storage_path(sp: str) -> Path:
        p = Path(sp.lstrip("./"))
        if p.is_absolute():
            return p

        APP_ROOT = Path(os.getenv("APP_ROOT", "/workspace/app"))
        BASE_STORAGE = Path(os.getenv("BASE_STORAGE_DIR", "/workspace/app/storage"))
        UPLOAD_DIR = os.getenv("PAYMENT_UPLOAD_DIR", "storage/payment_files")

        s = str(p)
        # Caso 1: ya viene con 'storage/...'
        if s.startswith("storage/"):
            return (APP_ROOT / s).resolve()
        # Caso 2: viene con 'payment_files/...'
        if s.startswith("payment_files/"):
            return (BASE_STORAGE / s).resolve()
        # Caso 3: viene solo el nombre o subruta; cuélgalo del UPLOAD_DIR
        return (APP_ROOT / UPLOAD_DIR / s).resolve()

    full_path = resolve_storage_path(storage_path)

    if not full_path.exists():
        current_app.logger.warning("file_missing_on_disk %s", full_path)
        return jsonify({"ok": False, "error": "file_missing_on_disk"}), 404

    mime = row["mime_type"] or mimetypes.guess_type(str(full_path))[0] or "application/octet-stream"

    return send_file(
        full_path,
        mimetype=mime,
        as_attachment=False,
        download_name=row["file_name"] or "evidence",
        conditional=True,
        max_age=3600,
    )