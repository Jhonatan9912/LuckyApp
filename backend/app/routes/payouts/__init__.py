from flask import Blueprint

payouts_bp = Blueprint("payouts", __name__, url_prefix="/api/me/payouts")

from .payouts_routes import *  # noqa
