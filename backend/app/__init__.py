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
    # Configuración de Base de Datos
    # =========================
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # =========================
    # JWT y Secret Keys
    # =========================
    app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'cambia-esta-clave-en-produccion')
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', app.config['JWT_SECRET_KEY'])

    # =========================
    # Configuración de Correo
    # =========================
    app.config['MAIL_SERVER'] = os.getenv('MAIL_SERVER', 'smtp.gmail.com')
    app.config['MAIL_PORT'] = int(os.getenv('MAIL_PORT', '587'))
    app.config['MAIL_USE_TLS'] = os.getenv('MAIL_USE_TLS', 'true').lower() == 'true'
    app.config['MAIL_USE_SSL'] = os.getenv('MAIL_USE_SSL', 'false').lower() == 'true'
    app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME')
    app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD')
    app.config['MAIL_DEFAULT_SENDER_NAME'] = os.getenv('MAIL_DEFAULT_SENDER_NAME', 'Mi App')
    app.config['MAIL_DEFAULT_SENDER_EMAIL'] = os.getenv('MAIL_DEFAULT_SENDER_EMAIL', app.config['MAIL_USERNAME'])

    if not (app.config['MAIL_USERNAME'] and app.config['MAIL_PASSWORD']):
        app.logger.warning("⚠ Mail no configurado: faltan MAIL_USERNAME/MAIL_PASSWORD.")
    else:
        app.logger.info("✅ Configuración SMTP cargada.")

    # =========================
    # Configuración Reset Password
    # =========================
    app.config['DEFAULT_COUNTRY_CODE'] = os.getenv('DEFAULT_COUNTRY_CODE', '')
    app.config['RESET_CODE_TTL_MIN'] = int(os.getenv('RESET_CODE_TTL_MIN', '10'))
    app.config['RESET_TOKEN_TTL_MIN'] = int(os.getenv('RESET_TOKEN_TTL_MIN', '30'))

    # =========================
    # Inicialización segura de dependencias
    # =========================
    try:
        init_db(app)
    except Exception as e:
        app.logger.error("❌ init_db() falló al arrancar: %s", e)

    JWTManager(app)

    # Registra TODOS los blueprints desde routes/__init__.py
    register_routes(app)

    @app.get("/healthz")
    def healthz():
        return {"ok": True}, 200

    return app
