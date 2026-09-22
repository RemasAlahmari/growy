from fastapi import FastAPI, Depends
from sqlmodel import Session, select
from database import create_db_and_tables, get_session
from models import User
from auth import verify_token

app = FastAPI()

@app.on_event("startup")
def on_startup():
    create_db_and_tables()

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.post("/users/sync")
def sync_user(
    username: str,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    firebase_uid = decoded_token["uid"]
    email = decoded_token.get("email", "")

    existing_user = session.exec(
        select(User).where(User.firebase_uid == firebase_uid)
    ).first()

    if existing_user:
        return existing_user

    new_user = User(
        firebase_uid=firebase_uid,
        username=username,
        email=email
    )
    session.add(new_user)
    session.commit()
    session.refresh(new_user)
    return new_user