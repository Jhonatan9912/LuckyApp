from app.routes.identification import identification_bp
from app.routes.register.register_routes import register_bp
from app.routes.auth.auth_routes import auth_bp
from app.routes.reset.password_reset_routes import password_reset_bp
from app.routes.games.games_routes import games_bp
from app.routes.admin import bp as admin_bp
from app.routes.admin.games_routes import admin_games_bp  
from app.routes.admin.players_routes import admin_players_bp
from app.routes.notify.notifications_routes import notifications_bp
from app.routes.admin.games_routes import admin_games_bp, me_notifications_bp

def register_routes(app):
    app.register_blueprint(identification_bp)
    app.register_blueprint(register_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(password_reset_bp)
    app.register_blueprint(games_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(admin_games_bp)
    app.register_blueprint(admin_players_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(me_notifications_bp)
