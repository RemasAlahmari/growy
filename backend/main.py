from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import SQLModel, Session, select, Field
from database import create_db_and_tables, get_session
from models import User, Habit, Avatar
from auth import verify_token

MAX_COLOR_VALUE = 0xFFFFFFFF  # largest possible Flutter Color.value


class AvatarUpdate(SQLModel):
    # The body the Flutter app sends (same keys as CharacterConfig.toJson())
    skin: int = Field(ge=0, le=MAX_COLOR_VALUE)
    hair: int = Field(ge=0, le=MAX_COLOR_VALUE)
    shirt: int = Field(ge=0, le=MAX_COLOR_VALUE)
    pants: int = Field(ge=0, le=MAX_COLOR_VALUE)
    shoes: int = Field(ge=0, le=MAX_COLOR_VALUE)


def avatar_to_dict(avatar: Avatar) -> dict:
    # Same shape that CharacterConfig.fromJson() expects in Flutter
    return {
        "skin": avatar.skin,
        "hair": avatar.hair,
        "shirt": avatar.shirt,
        "pants": avatar.pants,
        "shoes": avatar.shoes,
    }


app = FastAPI()

# Allow the Flutter web app to call this backend from the browser
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # for local development only; restrict this before deploying
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

@app.get("/habits")
def get_habits(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    habits = session.exec(select(Habit).order_by(Habit.id)).all()
    return habits

@app.get("/users/me/avatar")
def get_my_avatar(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    user = session.exec(
        select(User).where(User.firebase_uid == decoded_token["uid"])
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found. Call /users/sync first.")

    avatar = session.exec(
        select(Avatar).where(Avatar.user_id == user.id)
    ).first()

    # No saved avatar yet: return the default colors (without saving anything)
    if not avatar:
        avatar = Avatar(user_id=user.id)

    return avatar_to_dict(avatar)

@app.put("/users/me/avatar")
def update_my_avatar(
    data: AvatarUpdate,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    user = session.exec(
        select(User).where(User.firebase_uid == decoded_token["uid"])
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found. Call /users/sync first.")

    avatar = session.exec(
        select(Avatar).where(Avatar.user_id == user.id)
    ).first()

    # First save for this user: create the avatar row
    if not avatar:
        avatar = Avatar(user_id=user.id)

    avatar.skin = data.skin
    avatar.hair = data.hair
    avatar.shirt = data.shirt
    avatar.pants = data.pants
    avatar.shoes = data.shoes

    session.add(avatar)
    session.commit()
    session.refresh(avatar)
    return avatar_to_dict(avatar)