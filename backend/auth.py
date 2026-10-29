import os

import firebase_admin
from firebase_admin import credentials, auth
from fastapi import Header, HTTPException


def init_firebase():
    """Initialises the Firebase Admin SDK once. Called at app startup."""
    try:
        firebase_admin.get_app()
    except ValueError:  # not initialised yet
        # Service-account JSON, shared privately and never committed. A relative
        # path is resolved from the folder you start uvicorn in (backend/).
        path = os.getenv("FIREBASE_CREDENTIALS", "firebase-service-account.json")
        cred = credentials.Certificate(path)
        firebase_admin.initialize_app(cred)


def verify_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")

    token = authorization.split("Bearer ")[1]

    init_firebase()
    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
