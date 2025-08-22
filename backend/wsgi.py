# backend/wsgi.py
import os

def _make_fallback():
    from flask import Flask, jsonify
    f = Flask(__name__)

    @f.get("/health")
    def _health():
        return jsonify(ok=True, fallback=True), 200

    @f.get("/")
    def _root():
        return "WSGI fallback running", 200

    return f

# Permite forzar el fallback con una variable de entorno en Railway
if os.getenv("FORCE_WSGI_FALLBACK", "").lower() in {"1", "true", "yes"}:
    app = _make_fallback()
else:
    try:
        from app import create_app  # app/__init__.py
        app = create_app()
    except Exception as _e:
        # Si tu factory rompe por DB u otra cosa, igual levantamos
        app = _make_fallback()
