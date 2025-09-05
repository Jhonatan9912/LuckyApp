# app/routes/meta/banks_routes.py
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import text
from app.db.database import db

meta_bp = Blueprint("meta", __name__, url_prefix="/api/meta")

def _parse_active(val: str | None):
    """None -> True (por defecto solo activos); 'all/any' -> None; true/false."""
    if val is None:
        return True
    v = val.strip().lower()
    if v in ("all", "any", ""):
        return None
    if v in ("true", "1", "t", "yes", "y"):
        return True
    if v in ("false", "0", "f", "no", "n"):
        return False
    return True

@meta_bp.get("/banks")
@jwt_required(optional=True)
def list_banks():
    """
    Lista bancos desde public.banks.

    Query:
      - entity_type: BANK | CF | COOP | SEDPE | OTHER (opcional)
      - active: true/false/all (default true)
      - q: filtro por nombre (opcional)
    """
    et = (request.args.get("entity_type") or "").strip() or None     # str|None
    active = _parse_active(request.args.get("active"))               # True|False|None
    q = (request.args.get("q") or "").strip()

    clauses = ["1=1"]
    params: dict = {}

    # Solo filtramos si hay valor; así evitamos parámetros NULL en comparaciones
    if active is not None:
        clauses.append("b.active = :active")
        params["active"] = active

    if et is not None:
        # Comparamos como texto para no depender del tipo enum
        clauses.append("b.entity_type::text = :et")
        params["et"] = et

    if q:
        clauses.append(
            "(LOWER(b.name) LIKE LOWER(:qpat) OR LOWER(b.short_name) LIKE LOWER(:qpat))"
        )
        params["qpat"] = f"%{q}%"

    where_sql = " AND ".join(clauses)

    sql = text(f"""
        SELECT
          b.id,
          b.code,
          b.name,
          b.short_name,
          b.country_code,
          b.active,
          b.entity_type::text AS entity_type,
          b.ach_code,
          b.swift_bic,
          b.pse_code
        FROM public.banks b
        WHERE {where_sql}
        ORDER BY COALESCE(b.short_name, b.name), b.name
    """)

    rows = db.session.execute(sql, params).mappings().all()
    return jsonify([dict(r) for r in rows]), 200
