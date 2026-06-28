"""Shared test setup.

Tests live at the repo root (not under src/) so they are never packaged into the
deployment zip. This file makes the Flask app importable and sets the environment
variables app.py reads at import time, before any test module imports it.

No real Azure resources are touched: the tests that exercise the routes mock the
module-level blob client and the SAS signer, which are the only things that would
otherwise require Azure credentials and network access.
"""

import os
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC))

os.environ.setdefault("STORAGE_ACCOUNT_NAME", "testaccount")
os.environ.setdefault("IMAGES_CONTAINER_NAME", "images")
os.environ.setdefault("FLASK_SECRET_KEY", "test-secret")
