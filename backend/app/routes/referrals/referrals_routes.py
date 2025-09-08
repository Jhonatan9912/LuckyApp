# app/routes/referrals/referrals_routes.py
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from flask import send_file, abort, current_app
from sqlalchemy import text
from app.db.database import db
from app.services.referrals.referral_service import (
    get_summary_for_user,
    get_referrals_for_user,
)
from app.services.referrals.payouts_service import get_payout_totals

# Blueprint del usuario actual: /api/me/referrals
referrals_bp = Blueprint(
    "referrals",
    __name__,
    url_prefix="/api/me/referrals",
)

referrals_public_bp = Blueprint(
    "referrals_public", __name__, url_prefix="/api/referrals"
)
@referrals_bp.get("/ping")
def ping():
    return jsonify({"ok": True, "module": "referrals"}), 200

# GET /api/me/referrals/summary
# Producción: ventana fija de 3 días para "retenida" -> "disponible"
@referrals_bp.get("/summary")
@jwt_required()
def my_referrals_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    data = get_summary_for_user(user_id, hold_days=3)
    return jsonify(data), 200

# GET /api/me/referrals/?limit=&offset=

@referrals_bp.get("/")
@jwt_required()
def my_referrals_list():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    try:
        limit = int(request.args.get("limit", 50))
        offset = int(request.args.get("offset", 0))
        limit = max(1, min(limit, 200))
        offset = max(0, offset)
    except Exception:
        limit, offset = 50, 0

    items = get_referrals_for_user(user_id, limit=limit, offset=offset)
    return jsonify(items), 200

# GET /api/me/referrals/payouts/summary?currency=COP
@referrals_bp.get("/payouts/summary")
@jwt_required()
def my_referrals_payouts_summary():
    identity = get_jwt_identity()
    user_id = identity.get("id") if isinstance(identity, dict) else int(identity)
    currency = (request.args.get("currency") or "COP").upper()
    data = get_payout_totals(user_id, currency=currency)
    return jsonify(data), 200

@referrals_bp.post("/referrals/dev/mature")
@jwt_required()
def dev_mature_referral_commissions():
    """
    DEV ONLY: promueve comisiones pending -> available usando minutos o días.
    Ej: POST /api/referrals/dev/mature?minutes=1
    """
    minutes = request.args.get("minutes", type=int)
    days = request.args.get("days", type=int)

    # (opcional) valida rol/admin si quieres reforzar seguridad
    # user_id = int(get_jwt_identity())

    from app.services.referrals.payouts_service import mature_commissions
    updated = mature_commissions(days=days, minutes=minutes)
    return {"updated": updated, "minutes": minutes, "days": days}, 200

def _get_payout_evidence_impl(batch_id: int, file_id: int):
    """Lógica compartida para devolver la evidencia si el usuario está autorizado."""
    ident = get_jwt_identity()
    uid = ident.get("id") if isinstance(ident, dict) else int(ident)

    # ¿Es admin?
    role_id = db.session.execute(
        text("SELECT role_id FROM users WHERE id=:uid"), {"uid": uid}
    ).scalar()
    is_admin = int(role_id or 0) == 1

    q = text("""
        SELECT f.storage_path
        FROM public.payout_payment_files f
        JOIN public.payout_payment_batches b  ON b.id  = f.batch_id
        JOIN public.payout_payment_batch_items bi ON bi.batch_id = b.id
        JOIN public.payout_requests pr ON pr.id = bi.payout_request_id
        WHERE f.id = :fid
          AND f.batch_id = :bid
          AND (:is_admin OR pr.user_id = :uid)
        LIMIT 1
    """)
    row = db.session.execute(
        q, {"fid": file_id, "bid": batch_id, "uid": uid, "is_admin": is_admin}
    ).mappings().first()

    if not row:
        current_app.logger.warning(
            "evidence not found/forbidden",
            extra={"fid": file_id, "bid": batch_id, "uid": uid, "is_admin": is_admin},
        )
        abort(404)

    path = row["storage_path"]
    import os

    # Si quedó relativa en la BD, la convertimos a absoluta bajo el root de la app
    if not os.path.isabs(path):
        path = os.path.join(current_app.root_path, path)

    # Normaliza separadores (Windows/Linux)
    path = os.path.normpath(path)

    try:
        return send_file(path, as_attachment=False)
    except Exception as e:
        current_app.logger.exception("send_file failed: %s", e)
        abort(404)


# /api/me/referrals/...
@referrals_bp.get("/payout-batches/<int:batch_id>/files/<int:file_id>")
@jwt_required()
def get_payout_evidence_me(batch_id: int, file_id: int):
    return _get_payout_evidence_impl(batch_id, file_id)

# /api/referrals/...
@referrals_public_bp.get("/payout-batches/<int:batch_id>/files/<int:file_id>")
@jwt_required()
def get_payout_evidence_public(batch_id: int, file_id: int):
    return _get_payout_evidence_impl(batch_id, file_id)

