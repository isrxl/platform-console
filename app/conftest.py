import os
import sys

# Ensure the app modules (app.py, db.py, keyvault.py, config.py) are importable
# when pytest is invoked as `pytest tests/` from the app/ directory.
sys.path.insert(0, os.path.dirname(__file__))
