# app/routes/admin/__init__.py
from flask import Blueprint

bp = Blueprint("admin", __name__, url_prefix="/api/admin")

# Adjunta módulos que usan ESTE bp
from . import admin_routes, users_routes  # noqa: F401
