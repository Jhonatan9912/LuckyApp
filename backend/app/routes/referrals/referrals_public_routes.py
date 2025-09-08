# app/routes/referrals/referrals_public_routes.py
from flask import Blueprint, send_file, abort
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy import text
from app.db.database import db

referrals_public_bp = Blueprint("referrals_public", __name__, url_prefix="/api/referrals")

@referrals_public_bp.get("/payout-batches/<int:batch_id>/files/<int:file_id>")
@jwt_required()
def get_payout_evidence(batch_id: int, file_id: int):
    """
    Descarga segura de evidencia del pago.
    Autoriza si el usuario autenticado es dueño de alguna solicitud del batch
    o si es admin (role_id=1).
    """
    uid = get_jwt_identity()

    role_id = db.session.execute(
        text("SELECT role_id FROM users WHERE id=:uid"),
        {"uid": uid}
    ).scalar()
    is_admin = int(role_id or 0) == 1

    q = text("""
        SELECT f.storage_path
        FROM public.payout_payment_files f
        JOIN public.payout_payment_batches b ON b.id = f.batch_id
        JOIN public.payout_payment_batch_items bi ON bi.batch_id = b.id
        JOIN public.payout_requests pr ON pr.id = bi.payout_request_id
        WHERE f.id = :fid AND f.batch_id = :bid
          AND (:is_admin OR pr.user_id = :uid)
        LIMIT 1
    """)
    row = db.session.execute(
        q, {"fid": file_id, "bid": batch_id, "uid": uid, "is_admin": is_admin}
    ).mappings().first()
    if not row:
        abort(404)

    path = row["storage_path"]
    try:
        return send_file(path, as_attachment=True)
    except Exception:
        abort(404)
