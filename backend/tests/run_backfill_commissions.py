# backend/tests/run_backfill_commissions.py

import os, sys

# añade "backend/" al sys.path para que "from app ..." funcione
HERE = os.path.dirname(__file__)                         # .../backend/tests
BACKEND_DIR = os.path.abspath(os.path.join(HERE, ".."))  # .../backend
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app import create_app
from app.subscriptions.service import backfill_commissions

app = create_app()

with app.app_context():
    res = backfill_commissions(limit=2000)
    print("=== RESULTADO BACKFILL ===")
    print(res)
