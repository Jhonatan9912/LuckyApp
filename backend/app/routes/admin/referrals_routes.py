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
    
    