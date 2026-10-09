from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import SQLModel, Session, select, Field
from database import create_db_and_tables, get_session
from models import User, Habit, Avatar, HabitLog, today_ksa
from auth import verify_token
from leveling import calculate_level
from datetime import timedelta
from sqlalchemy import func
MAX_COLOR_VALUE = 0xFFFFFFFF  # largest possible Flutter Color.value
MAX_REJECTED_ATTEMPTS = 3
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
PROGRESS_DAYS = 7


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


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Runs once when the server starts
    create_db_and_tables()
    yield
    # (code after yield would run when the server stops)


app = FastAPI(lifespan=lifespan)

# Allow the Flutter web app to call this backend from the browser
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # for local development only; restrict this before deploying
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


@app.post("/habits/{habit_id}/complete/ai")
def complete_habit_ai(
    habit_id: int,
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # 1. Find the user from the token and the habit from the URL
    user = get_current_user(session, decoded_token)

    habit = session.get(Habit, habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found.")

    today = today_ksa()

    # 2. Block if this habit is already completed today
    already_verified = session.exec(
        select(HabitLog).where(
            HabitLog.user_id == user.id,
            HabitLog.habit_id == habit.id,
            HabitLog.completed_date == today,
            HabitLog.verification_status == "verified",
        )
    ).first()
    if already_verified:
        raise HTTPException(status_code=409, detail="This habit is already completed today.")

    # 3. Block if the user used all rejected attempts today
    rejected_count = session.exec(
        select(func.count()).select_from(HabitLog).where(
            HabitLog.user_id == user.id,
            HabitLog.habit_id == habit.id,
            HabitLog.completed_date == today,
            HabitLog.verification_status == "rejected",
        )
    ).one()
    if rejected_count >= MAX_REJECTED_ATTEMPTS:
        raise HTTPException(status_code=429, detail="No attempts left for this habit today. Try again tomorrow.")

    # 4. Check the uploaded file is an image and not too large
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Only JPEG, PNG, or WEBP images are allowed.")
    image_bytes = file.file.read(MAX_IMAGE_SIZE + 1)
    if len(image_bytes) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="Image is too large (max 5 MB).")

    # 5. Verify the image
    # TODO (AI teammate): replace these three lines with the real CLIP verification
    is_verified = True
    predicted_label = habit.ai_label
    confidence = 1.0

    # 6. Save this attempt (verified or rejected)
    log = HabitLog(
        habit_id=habit.id,
        user_id=user.id,
        completed_date=today,
        points_earned=habit.points if is_verified else 0,
        verification_status="verified" if is_verified else "rejected",
        predicted_label=predicted_label,
        confidence=confidence,
    )
    session.add(log)

    # 7. On success: add the points and recalculate the level
    previous_level = user.current_level
    if is_verified:
        user.total_points += habit.points
        user.current_level = calculate_level(user.total_points)
        session.add(user)

    session.commit()
    session.refresh(user)

    if is_verified:
        attempts_remaining = MAX_REJECTED_ATTEMPTS - rejected_count
    else:
        attempts_remaining = MAX_REJECTED_ATTEMPTS - (rejected_count + 1)

    return {
        "verification_status": log.verification_status,
        "predicted_label": predicted_label,
        "confidence": confidence,
        "points_earned": log.points_earned,
        "attempts_remaining": attempts_remaining,
        "total_points": user.total_points,
        "current_level": user.current_level,
        "leveled_up": user.current_level > previous_level,
    }


@app.get("/progress")
def get_progress(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Stats for the Progress screen: totals + points and habits per day for the last 7 days.
    user = get_current_user(session, decoded_token)
    today = today_ksa()
    start_date = today - timedelta(days=PROGRESS_DAYS - 1)

    # One query: total points and number of completed habits, grouped by day
    rows = session.exec(
        select(
            HabitLog.completed_date,
            func.sum(HabitLog.points_earned),
            func.count(),
        ).where(
            HabitLog.user_id == user.id,
            HabitLog.verification_status == "verified",
            HabitLog.completed_date >= start_date,
        ).group_by(HabitLog.completed_date)
    ).all()
    per_day = {day: (points, count) for day, points, count in rows}

    # Fill in all 7 days, using 0 for days with no completions
    last_7_days = []
    for i in range(PROGRESS_DAYS):
        day = start_date + timedelta(days=i)
        points, count = per_day.get(day, (0, 0))
        last_7_days.append({
            "date": day.isoformat(),
            "points": points,
            "habits_completed": count,
        })

    total_habits_completed = session.exec(
        select(func.count()).select_from(HabitLog).where(
            HabitLog.user_id == user.id,
            HabitLog.verification_status == "verified",
        )
    ).one()

    return {
        "total_points": user.total_points,
        "current_level": user.current_level,
        "total_habits_completed": total_habits_completed,
        "last_7_days": last_7_days,
    }