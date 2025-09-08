# app/routes/referrals/referrals_public_routes.py
# -*- coding: utf-8 -*-
from __future__ import annotations

from pathlib import Path
from flask import Blueprint, send_file, abort, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from app.services.referrals.payout_batches_service import (
    authorize_and_get_evidence_path,
    get_payout_batch_details,
)

referrals_public_bp = Blueprint(
    "referrals_public",
    __name__,
    url_prefix="/api/referrals",
)

def _current_user_id() -> int:
    ident = get_jwt_identity()
    try:
        return int(ident.get("id")) if isinstance(ident, dict) else int(ident)
    except Exception:
        return 0


@referrals_public_bp.get("/payout-batches/<int:batch_id>/files/<int:file_id>")
@jwt_required()
def get_payout_evidence(batch_id: int, file_id: int):
    """
    Descarga segura de evidencia del pago.
    La autorización y resolución de la ruta la hace el service.
    """
    uid = _current_user_id()
    try:
        p: Path = authorize_and_get_evidence_path(batch_id=batch_id, file_id=file_id, uid=uid)
    except FileNotFoundError:
        abort(404, description="Archivo de evidencia no encontrado")
    except Exception:
        abort(404)

    return send_file(str(p), as_attachment=True)


@referrals_public_bp.get("/payout-batches/<int:batch_id>/details")
@jwt_required()
def payout_batch_details(batch_id: int):
    """
    Devuelve cabecera, requests y archivos (sin URL aún).
    Aquí armamos la URL pública del archivo para el front.
    """
    uid = _current_user_id()
    try:
        data = get_payout_batch_details(batch_id=batch_id, uid=uid)
    except Exception:
        abort(404)

    # Agregar URL pública para cada archivo
    files_with_urls = [
        {
            **f,
            "url": f"/api/referrals/payout-batches/{batch_id}/files/{f['id']}",
        }
        for f in data.get("files", [])
    ]
    data["files"] = files_with_urls
    return jsonify(data)
