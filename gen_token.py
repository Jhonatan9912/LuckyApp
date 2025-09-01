from app import create_app
from flask_jwt_extended import create_access_token

app = create_app()
with app.app_context():
    print(create_access_token(identity={'id': 15}))
