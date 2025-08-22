from flask import Blueprint, jsonify
from app.models.identification_type import IdentificationType

identification_bp = Blueprint('identification', __name__)

@identification_bp.route('/identification-types', methods=['GET'])
def get_identification_types():
    types = IdentificationType.query.all()
    data = [t.to_dict() for t in types]
    return jsonify(data)  # ✔️ más limpio y seguro
