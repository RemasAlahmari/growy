from fastapi import HTTPException
from sqlmodel import Session, select

from models import User


def get_current_user(session: Session, decoded_token: dict) -> User:
    # Finds the logged-in user's row from their Firebase token.
    user = session.exec(
        select(User).where(User.firebase_uid == decoded_token["uid"])
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found. Call /users/sync first.")
    return user
