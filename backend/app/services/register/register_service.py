# app/services/register/register_service.py (o ruta equivalente)
from app.models.user import User
from app.db.database import db
from werkzeug.security import generate_password_hash
from sqlalchemy.exc import IntegrityError
from sqlalchemy import text
from datetime import datetime

def register_user(data):
    required = [
        'name', 'identification_type_id', 'identification_number',
        'phone', 'birthdate', 'password', 'email',
        'accept_terms', 'accept_data'   # 👈 NUEVOS
    ]

    # Requeridos: presencia
    missing = [k for k in required if k not in data]
    if missing:
        return {'ok': False, 'error': f'Faltan campos: {", ".join(missing)}'}, 400

    # Requeridos no vacíos (excepto los booleanos)
    empty = [k for k in ['name','identification_type_id','identification_number','phone','birthdate','password','email']
            if not str(data.get(k, '')).strip()]
    if empty:
        return {'ok': False, 'error': f'Campos vacíos: {", ".join(empty)}'}, 400


    # Normalizar datos
    name = str(data['name']).strip()
    identification_type_id = int(data['identification_type_id'])
    identification_number = str(data['identification_number']).strip()
    phone = ''.join(ch for ch in str(data['phone']) if ch.isdigit())
    email = str(data['email']).strip().lower()
    birthdate = data['birthdate']                # ya parseado en la ruta
    password_hash = generate_password_hash(str(data['password']))
    # Opcional: código de país (p. ej. '+57'); si no viene, queda None
    country_code = (data.get('country_code') or '').strip() or None
    if country_code and not (country_code.startswith('+') and country_code[1:].isdigit() and 1 <= len(country_code[1:]) <= 4):
        return {'ok': False, 'error': 'country_code inválido. Formato esperado +<1..4 dígitos>'}, 400

    # Versión de los documentos de consentimiento (útil para auditoría)
    consent_version = str(data.get('consent_version') or 'v1')

    # Timestamps de aceptación (sólo si aceptó)
    accepted_terms_at = datetime.utcnow() if data.get('accept_terms') else None
    accepted_data_at  = datetime.utcnow() if data.get('accept_data')  else None

    # Consentimientos + referido
    accept_terms = bool(data.get('accept_terms'))
    accept_data  = bool(data.get('accept_data'))
    referral_code = (data.get('referral_code') or '').strip() or None

    if not (accept_terms and accept_data):
        return {'ok': False, 'error': 'Debes aceptar Términos y Tratamiento de Datos'}, 400

    # Unicidad
    phone_exists = db.session.query(User.id).filter_by(phone=phone).first() is not None
    ident_exists = db.session.query(User.id).filter_by(identification_number=identification_number).first() is not None
    email_exists = db.session.query(User.id).filter_by(email=email).first() is not None
    if phone_exists or ident_exists or email_exists:
        msgs = []
        if phone_exists: msgs.append('teléfono ya registrado')
        if ident_exists: msgs.append('identificación ya registrada')
        if email_exists: msgs.append('correo ya registrado')
        return {'ok': False, 'error': '; '.join(msgs)}, 409

    try:
        # ---- transacción ----
        user = User(
            name=name,
            identification_type_id=identification_type_id,
            identification_number=identification_number,
            phone=phone,
            email=email,
            birthdate=birthdate,
            password_hash=password_hash,
            role_id=2,   # estándar

            # 👇 NUEVOS
            country_code=country_code,                 # opcional
            accepted_terms_at=accepted_terms_at,       # timestamp si aceptó
            accepted_data_at=accepted_data_at,         # timestamp si aceptó
            consent_version=consent_version,           # p. ej. 'v1'
        )

        db.session.add(user)
        db.session.flush()  # 👈 asegura user.id sin commit aún

        # Si llegó código de referido, lo registramos
        if referral_code:
            referrer = db.session.query(User).filter(
                User.public_code == referral_code
            ).first()

            if not referrer:
                db.session.rollback()
                return {'ok': False, 'error': 'Código de referido inválido'}, 400

            if referrer.id == user.id:
                db.session.rollback()
                return {'ok': False, 'error': 'No puedes referirte a ti mismo'}, 400

            # Inserta en referrals (usa tu tabla creada)
            db.session.execute(text("""
                INSERT INTO referrals
                    (referrer_user_id, referred_user_id, referral_code_used, status, source, notes, created_at, updated_at)
                VALUES
                    (:referrer_id, :referred_id, :code, 'pending', 'signup', NULL, NOW(), NOW())
            """), {
                'referrer_id': referrer.id,
                'referred_id': user.id,
                'code': referral_code,
            })

        db.session.commit()
        db.session.refresh(user)
        return {
            'ok': True,
            'message': 'Usuario registrado correctamente',
            'user_id': user.id,
            'public_code': user.public_code,
        }, 201

    except IntegrityError:
        db.session.rollback()
        return {'ok': False, 'error': 'Teléfono, identificación o correo ya registrados'}, 409
    except Exception:
        db.session.rollback()
        raise
