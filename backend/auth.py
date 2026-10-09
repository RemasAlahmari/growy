import json
import os
from pathlib import Path
from typing import Optional

import firebase_admin
from dotenv import load_dotenv
from fastapi import Header, HTTPException
from firebase_admin import auth, credentials

load_dotenv()

LOCAL_KEY_FILE = Path(__file__).parent / "firebase-service-account.json"


def load_firebase_credentials():
    # On the server: the whole JSON key is stored in an environment variable.
    key_json = os.getenv("FIREBASE_SERVICE_ACCOUNT")
    if key_json:
        return credentials.Certificate(json.loads(key_json))
    # On your laptop: read the local key file (never committed to Git).
    return credentials.Certificate(str(LOCAL_KEY_FILE))


# Initialize Firebase only once (the --reload option can import this file again)
if not firebase_admin._apps:
    firebase_admin.initialize_app(load_firebase_credentials())


def verify_token(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.split("Bearer ")[1]

    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")