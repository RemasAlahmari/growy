import logging

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import SQLModel, Session, select, Field
from database import create_db_and_tables, get_session
from models import User, Habit, Avatar, HabitLog, today_ksa
from auth import verify_token, init_firebase
from datetime import timedelta
from sqlalchemy import func

import ai_verification
from leveling import level_for_points

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("growy")
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
    init_firebase()
    if ai_verification.is_configured():
        logger.info("AI verification ready (model: %s)", ai_verification.model_name())
    else:
        logger.warning("GEMINI_API_KEY is not set: photo verification will return 503 until you add it to backend/.env")

@app.get("/health")
def health_check():
    # Never returns the key itself, only whether one is set.
    return {
        "status": "ok",
        "ai_configured": ai_verification.is_configured(),
        "ai_model": ai_verification.model_name(),
    }

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


def get_current_user(session: Session, decoded_token: dict) -> User:
    # Finds the logged-in user's row from their Firebase token.
    user = session.exec(
        select(User).where(User.firebase_uid == decoded_token["uid"])
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found. Call /users/sync first.")
    return user
 
 
@app.get("/users/me")
def get_me(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Everything the Home header needs: name, points, level, streak, today's points.
    user = get_current_user(session, decoded_token)
 
    today_points = session.exec(
        select(func.coalesce(func.sum(HabitLog.points_earned), 0)).where(
            HabitLog.user_id == user.id,
            HabitLog.completed_date == today_ksa(),
            HabitLog.verification_status == "verified",
        )
    ).one()
 
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "total_points": user.total_points,
        "current_level": user.current_level,
        "streak_days": user.streak_days,
        "today_points": today_points,
    }
 
 
@app.get("/habits/today")
def get_today_habits(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # All habits, plus for THIS user: done today? and how many days in a row.
    # Only "verified" logs count (AI photo verification passed).
    user = get_current_user(session, decoded_token)
    today = today_ksa()
 
    habits = session.exec(select(Habit).order_by(Habit.id)).all()
    result = []
 
    for habit in habits:
        done_dates = set(
            session.exec(
                select(HabitLog.completed_date).where(
                    HabitLog.user_id == user.id,
                    HabitLog.habit_id == habit.id,
                    HabitLog.verification_status == "verified",
                )
            ).all()
        )
 
        completed_today = today in done_dates
 
        # Streak = consecutive days ending today (or yesterday, if not done yet today,
        # so the streak doesn't look broken in the morning before the user completes it).
        day = today if completed_today else today - timedelta(days=1)
        streak = 0
        while day in done_dates:
            streak += 1
            day -= timedelta(days=1)
 
        result.append({
            "id": habit.id,
            "name": habit.name,
            "points": habit.points,
            "ai_label": habit.ai_label,
            "completed_today": completed_today,
            "streak": streak,
        })
 
    return result


# ------------------------------------------------------------------
# AI photo verification (Gemini)
# ------------------------------------------------------------------
MAX_UPLOAD_BYTES = 5 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png"}


def _already_verified_today(session: Session, user_id: int, habit_id: int) -> bool:
    return session.exec(
        select(HabitLog.id).where(
            HabitLog.user_id == user_id,
            HabitLog.habit_id == habit_id,
            HabitLog.completed_date == today_ksa(),
            HabitLog.verification_status == "verified",
        )
    ).first() is not None


# Plain `def` (not async) on purpose: FastAPI runs it in a worker thread,
# so waiting for Gemini doesn't block the other endpoints.
@app.post("/habits/{habit_id}/complete/ai")
def complete_habit_ai(
    habit_id: int,
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token),
):
    user = get_current_user(session, decoded_token)

    habit = session.get(Habit, habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")

    expected = ai_verification.expected_activity_for(habit.name)
    if expected is None:
        raise HTTPException(status_code=400, detail="This habit does not support photo verification")

    # Checked before calling Gemini so we don't waste an API call
    if _already_verified_today(session, user.id, habit.id):
        raise HTTPException(status_code=409, detail="Habit already completed today")

    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Only JPG or PNG images are allowed")
    data = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Image must be under 5 MB")

    try:
        jpeg = ai_verification.prepare_image(data)
    except ai_verification.InvalidImageError:
        raise HTTPException(status_code=415, detail="Could not read the image")

    try:
        verdict = ai_verification.analyze_photo(jpeg)
    except ai_verification.AIServiceError as e:
        # Nothing is saved, so the user can simply try again.
        logger.warning("AI verification unavailable: %s", e)
        raise HTTPException(
            status_code=503,
            detail="Photo verification is temporarily unavailable. Please try again in a minute.",
        )

    passed = ai_verification.passes(verdict, expected)

    # Re-check: two quick taps could both get this far while Gemini was thinking
    if passed and _already_verified_today(session, user.id, habit.id):
        raise HTTPException(status_code=409, detail="Habit already completed today")

    points = habit.points if passed else 0
    reason = verdict.reason.strip()[:500]

    log = HabitLog(
        habit_id=habit.id,
        user_id=user.id,
        points_earned=points,
        verification_status="verified" if passed else "rejected",
        predicted_label=verdict.detected_activity.value,
        confidence=None,
        ai_reason=f"{verdict.confidence.value}, {verdict.evidence.value}: {reason}",
    )
    session.add(log)

    if passed:
        user.total_points += points
        user.current_level = level_for_points(user.total_points)
        session.add(user)

    session.commit()
    session.refresh(log)
    session.refresh(user)

    return {
        "verification_status": log.verification_status,
        "expected_activity": expected.value,
        "predicted_label": verdict.detected_activity.value,
        # Gemini gives a level (high/medium/low), not a percentage. "confidence"
        # stays null so older app builds that expect a number keep working.
        "confidence": None,
        "confidence_level": verdict.confidence.value,
        "evidence": verdict.evidence.value,
        "reason": reason,
        "points_earned": points,
        "habit_log_id": log.id,
        "total_points": user.total_points,
        "current_level": user.current_level,
    }
