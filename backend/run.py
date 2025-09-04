# backend/run.py
import sys
import os

# Asegura que la carpeta 'backend' esté en sys.path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from app import create_app

app = create_app()

if __name__ == '__main__':
    # 🔻 antes tenías solo debug y port
    app.run(host="0.0.0.0", debug=True, port=8000)