import json
import logging
import os
from pathlib import Path
from typing import Optional

import firebase_admin
import google.auth.credentials
from dotenv import load_dotenv
from fastapi import Header, HTTPException
from firebase_admin import auth, credentials

load_dotenv()

logger = logging.getLogger("growy.auth")

# Default location of the service-account key on a laptop: backend/firebase-service-account.json
# (git-ignored). Found no matter which folder uvicorn is started from.
LOCAL_KEY_FILE = Path(__file__).parent / "firebase-service-account.json"

# The app's Firebase project (public: it is also in lib/firebase_options.dart).
DEFAULT_PROJECT_ID = "growy-4036d"


class _ProjectIdOnly(credentials.Base):
    """Used when no service-account key is available.

    Checking a login token only needs the project ID and Google's public
    certificates, so no secret key is required. (Admin features such as creating
    users would need the real key, but the backend doesn't use them.)
    """

    def get_credential(self):
        return google.auth.credentials.AnonymousCredentials()


def _key_file() -> Optional[Path]:
    custom_path = os.getenv("FIREBASE_CREDENTIALS", "").strip()
    if custom_path:
        path = Path(custom_path)
        if not path.is_absolute():
            path = Path(__file__).parent / path
    else:
        path = LOCAL_KEY_FILE
    return path if path.is_file() else None


def load_firebase_credentials():
    """Returns (credential, options, description of where it came from)."""
    project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip() or DEFAULT_PROJECT_ID
    # 1. On the server (Railway/Render): the whole JSON key in an environment variable.
    key_json = os.getenv("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if key_json:
        return credentials.Certificate(json.loads(key_json)), {}, "FIREBASE_SERVICE_ACCOUNT"
    # 2. A service-account key file (FIREBASE_CREDENTIALS, or backend/firebase-service-account.json).
    path = _key_file()
    if path:
        return credentials.Certificate(str(path)), {}, f"key file {path.name}"
    if os.getenv("FIREBASE_CREDENTIALS", "").strip():
        logger.warning("FIREBASE_CREDENTIALS points to a file that doesn't exist; using the project ID instead.")
    # 3. No key: verify logins with the project ID only.
    return _ProjectIdOnly(), {"projectId": project_id}, f"project ID {project_id} (no key file needed)"


def init_firebase():
    """Initialises the Firebase Admin SDK once (safe to call many times).

    Called at startup and before every token check, so tests that replace
    verify_token never need a real key file.
    """
    if not firebase_admin._apps:
        credential, options, source = load_firebase_credentials()
        firebase_admin.initialize_app(credential, options)
        logger.info("Firebase login checks ready (%s)", source)


def login_check_mode() -> str:
    """How login tokens are checked, for /health: "service_account", "project_id:<id>" or "error"."""
    try:
        init_firebase()
        app = firebase_admin.get_app()
    except Exception as e:
        logger.warning("Firebase is not set up: %s", e)
        return "error"
    if isinstance(app.credential, _ProjectIdOnly):
        return f"project_id:{app.project_id}"
    return "service_account"


def verify_token(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.split("Bearer ")[1]

    init_firebase()
    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except auth.CertificateFetchError:
        # The server couldn't download Google's public certificates (no internet).
        logger.warning("Could not reach Google to check a login token")
        raise HTTPException(status_code=503, detail="The server can't check logins right now. Check its internet connection.")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
