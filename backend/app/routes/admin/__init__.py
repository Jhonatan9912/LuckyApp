# app/routes/admin/__init__.py
from flask import Blueprint

bp = Blueprint("admin", __name__, url_prefix="/api/admin")

# Todas las rutas /api/admin/* de este blueprint exigen rol administrador
# (validado contra la BD, no contra el token).
from app.security.guards import protect_blueprint_admin  # noqa: E402
protect_blueprint_admin(bp)

# Adjunta módulos que usan ESTE bp
from . import admin_routes, users_routes, referrals_routes  # noqa: F401  👈 AÑADIDO
