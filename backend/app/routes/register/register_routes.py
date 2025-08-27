# app/routes/register/register_routes.py
from flask import Blueprint, request, jsonify
from app.services.register.register_service import register_user
import traceback
from datetime import datetime

register_bp = Blueprint('register', __name__, url_prefix="/api/auth")

@register_bp.route('/register', methods=['POST'])
def register():
    try:
        data = request.get_json() or {}

        # Parseo de fecha: acepta 'YYYY-MM-DD' o ISO completo.
        b = str(data.get('birthdate', '')).strip()
        if not b:
            return jsonify({'ok': False, 'error': 'birthdate es requerido'}), 400
        try:
            birthdate = datetime.fromisoformat(b).date() if 'T' in b else datetime.strptime(b, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({'ok': False, 'error': 'Formato de fecha inválido (use YYYY-MM-DD)'}), 400

        data['birthdate'] = birthdate  # ✅ pasamos date real al service

        result, status_code = register_user(data)
        return jsonify(result), status_code

    except ValueError as ve:
        return jsonify({'ok': False, 'error': str(ve)}), 400
    except Exception:
        traceback.print_exc()
        return jsonify({'ok': False, 'error': 'Error interno del servidor'}), 500
