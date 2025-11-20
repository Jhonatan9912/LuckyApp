# app/routes/admin/admin_routes.py
from flask import jsonify, current_app, Response
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import text
from app.db.database import db
from . import bp

from app.services.admin.admin_service import (
    get_lottery_dashboard_summary,
    get_active_games_export_rows,
)


def _require_admin():
    """
    Valida que el usuario actual tenga role_id = 1 (admin).
    Lanza una respuesta 403 si no es admin.
    """
    try:
        claims = get_jwt() or {}
        role_id = claims.get("role_id")

        if role_id is None:
            uid = int(get_jwt_identity())
            role_id = db.session.execute(
                text("SELECT role_id FROM users WHERE id = :uid"),
                {"uid": uid},
            ).scalar()

        if int(role_id) != 1:
            return jsonify({"ok": False, "error": "Solo administradores"}), 403

        return None  # OK
    except Exception:
        current_app.logger.exception("_require_admin: role check failed")
        return jsonify({"ok": False, "error": "Rol inválido"}), 403


# -------------------------------------------------------------------
#  RESUMEN DEL DASHBOARD
# -------------------------------------------------------------------
@bp.get("/dashboard/summary")
@jwt_required()
def dashboard_summary():
    # 1) Validar admin
    resp = _require_admin()
    if resp is not None:
        return resp

    # 2) Devolver el mismo shape que usaba Flutter
    try:
        summary = get_lottery_dashboard_summary()

        # Por si el service devuelve (data, status)
        if isinstance(summary, tuple):
            summary = summary[0]

        if not isinstance(summary, dict):
            summary = {"value": summary}

        return jsonify(summary), 200
    except Exception:
        current_app.logger.exception("dashboard_summary: service error")
        return (
            jsonify(
                {"ok": False, "error": "Fallo en dashboard_summary"},
            ),
            500,
        )


# -------------------------------------------------------------------
#  EXPORTAR JUEGOS ACTIVOS + NÚMEROS RESERVADOS (CSV AGRUPADO)
# -------------------------------------------------------------------
@bp.get("/dashboard/export-active-games")
@jwt_required()
def export_active_games():
    """
    Devuelve un CSV descargable con este formato:

    Juego 40
    Jugadores:,3
    Numeros reservados:,15
    user_id,user_name,user_phone,number
    83,Juan,3001234567,231
    ...

    (línea en blanco)

    Juego 41
    ...
    """
    # 1) Validar admin
    resp = _require_admin()
    if resp is not None:
        return resp

    # 2) Obtener datos desde el service
    try:
        rows = get_active_games_export_rows()
    except Exception:
        current_app.logger.exception("export_active_games: service error")
        return (
            jsonify(
                {"ok": False, "error": "No se pudo obtener la información"},
            ),
            500,
        )

    # 3) Si no hay datos, devolver CSV básico
    if not rows:
        csv_data = "No hay juegos activos ni numeros reservados."
        return Response(
            csv_data,
            mimetype="text/csv",
            headers={
                "Content-Disposition": "attachment; filename=juegos_activos.csv"
            },
        )

    # 4) Construir CSV agrupado por juego
    lines: list[str] = []
    current_game_id = None

    for r in rows:
        game_id = r.get("game_id")
        lottery_name = r.get("lottery_name") or ""
        played_date = r.get("played_date") or ""
        played_time = r.get("played_time") or ""
        players_in_game = r.get("players_in_game") or 0
        reserved_numbers = r.get("reserved_numbers_in_game") or 0

        # Cuando cambia de juego, escribimos cabecera de sección
        if game_id != current_game_id:
            if current_game_id is not None:
                # línea en blanco entre juegos
                lines.append("")

            # Cabecera del juego
            title = f"Juego {game_id}"
            if lottery_name:
                title += f" - {lottery_name}"
            if played_date or played_time:
                title += f" ({played_date} {played_time})"

            lines.append(title)
            lines.append(f"Jugadores:,{players_in_game}")
            lines.append(f"Numeros reservados:,{reserved_numbers}")
            # Encabezado de la tabla de jugadores
            lines.append("user_id,user_name,user_phone,number")

            current_game_id = game_id

        # Fila de detalle (jugador + numero)
        line = [
            str(r.get("user_id", "")),
            str(r.get("user_name", "")),
            str(r.get("user_phone", "")),
            str(r.get("number", "")),
        ]
        lines.append(",".join(line))

    csv_raw = "\n".join(lines)

    return Response(
        csv_raw,
        mimetype="text/csv",
        headers={
            "Content-Disposition": "attachment; filename=juegos_activos.csv"
        },
    )
