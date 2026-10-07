import os
# backend/app/routes/__init__.py  (o donde tengas register_routes)

from app.routes.identification import identification_bp
from app.routes.register.register_routes import register_bp
from app.routes.auth.auth_routes import auth_bp

# 👇 CAMBIA este import para traer también el alias
from app.routes.reset.password_reset_routes import (
    password_reset_bp,      # /api/reset/...
    auth_reset_alias_bp,    # /api/auth/...  <-- alias que espera Flutter
)
from app.routes.payouts import payouts_bp
from app.routes.games.games_routes import games_bp
from app.routes.admin import bp as admin_bp
from app.routes.admin.players_routes import admin_players_bp
from app.routes.notify.notifications_routes import notifications_bp
from app.routes.admin.games_routes import admin_games_bp, me_notifications_bp
from app.routes.health import health_bp
from app.subscriptions.routes import subscriptions_bp
from app.subscriptions.webhooks import webhooks_bp
from app.routes.referrals.referrals_routes import referrals_bp, referrals_public_bp
from app.routes.dev_mock import dev_bp      
from app.routes.payouts.banks_routes import meta_bp

def register_routes(app):
    app.register_blueprint(identification_bp)
    app.register_blueprint(register_bp)
    app.register_blueprint(auth_bp)

    # Rutas de reset originales
    app.register_blueprint(password_reset_bp)      # /api/reset/...

    # 👇 REGISTRA EL ALIAS
    app.register_blueprint(auth_reset_alias_bp)    # /api/auth/...

    app.register_blueprint(games_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(admin_games_bp)
    app.register_blueprint(admin_players_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(me_notifications_bp)
    app.register_blueprint(health_bp)
    app.register_blueprint(subscriptions_bp)
    app.register_blueprint(webhooks_bp)
    app.register_blueprint(referrals_bp)
    # Rutas de simulación (crean comisiones de dinero): SOLO en desarrollo local.
    if os.getenv("ENABLE_DEV_ROUTES", "").lower() in ("1", "true", "yes"):
        app.register_blueprint(dev_bp)
    app.register_blueprint(payouts_bp)
    app.register_blueprint(meta_bp)
    app.register_blueprint(referrals_public_bp)
