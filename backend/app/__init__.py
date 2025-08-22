# app/__init__.py
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from .routes import register_routes
from .db.database import init_db
from dotenv import load_dotenv
import os

def create_app():
    load_dotenv()

    app = Flask(__name__)
    CORS(app)

    # =========================
    # Database
    # =========================
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # =========================
    # JWT / Secrets
    # =========================
    app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'cambia-esta-clave-en-produccion')
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', app.config['JWT_SECRET_KEY'])

    # =========================
    # Mail (Gmail SMTP)
    # =========================
    app.config['MAIL_SERVER'] = os.getenv('MAIL_SERVER', 'smtp.gmail.com')
    app.config['MAIL_PORT'] = int(os.getenv('MAIL_PORT', '587'))
    app.config['MAIL_USE_TLS'] = os.getenv('MAIL_USE_TLS', 'true').lower() == 'true'
    app.config['MAIL_USE_SSL'] = os.getenv('MAIL_USE_SSL', 'false').lower() == 'true'
    app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME')              # tu_cuenta@gmail.com
    app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD')              # app password (16 chars)
    app.config['MAIL_DEFAULT_SENDER_NAME'] = os.getenv('MAIL_DEFAULT_SENDER_NAME', 'Mi App')
    app.config['MAIL_DEFAULT_SENDER_EMAIL'] = os.getenv('MAIL_DEFAULT_SENDER_EMAIL', app.config['MAIL_USERNAME'])

    # Log de configuración de mail (sin secretos)
    if not (app.config['MAIL_USERNAME'] and app.config['MAIL_PASSWORD']):
        app.logger.warning("Mail no configurado: faltan MAIL_USERNAME/MAIL_PASSWORD. No se podrán enviar correos.")
    else:
        app.logger.info("Mail SMTP configurado (usuario: %s)", app.config['MAIL_USERNAME'])

    # =========================
    # Reset Password settings
    # =========================
    app.config['DEFAULT_COUNTRY_CODE'] = os.getenv('DEFAULT_COUNTRY_CODE', '')
    app.config['RESET_CODE_TTL_MIN']  = int(os.getenv('RESET_CODE_TTL_MIN', '10'))
    app.config['RESET_TOKEN_TTL_MIN'] = int(os.getenv('RESET_TOKEN_TTL_MIN', '30'))


    # Init infra
    init_db(app)
    JWTManager(app)
    register_routes(app)

    @app.get("/healthz")
    def healthz():
            return {"ok": True}, 200

    return app
