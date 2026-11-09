import logging
import os
import re
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, text, update
from sqlalchemy.exc import IntegrityError
from sqlmodel import SQLModel, Session, select, Field

import ai_verification
import groups
import photos
from auth import verify_token, init_firebase, login_check_mode
from database import create_db_and_tables, database_kind, get_session, engine
from deps import get_current_user
from leveling import calculate_level, xp_progress
from models import User, Habit, Avatar, HabitLog, today_ksa
from seed_groups import ensure_rooms
from seed_habits import ensure_habits
from streaks import count_streak, longest_streak

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("growy")

MAX_COLOR_VALUE = 0xFFFFFFFF  # largest possible Flutter Color.value
MAX_REJECTED_ATTEMPTS = 3
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
PROGRESS_DAYS = 7

USERNAME_PATTERN = re.compile(r"^[a-zA-Z0-9_]{3,20}$")  # same rule as Edit Profile in the app
GENDER_VALUES = {"male": "male", "boy": "male", "female": "female", "girl": "female"}

# Category of each habit ("Study" or "Health"): shown on the Habits history page,
# and used by the app to match habits to groups (a group's category).
HABIT_CATEGORY = {"reading": "Study"}  # every other habit is "Health"


def habit_category(habit_name: str) -> str:
    return HABIT_CATEGORY.get(habit_name.strip().lower(), "Health")


class AvatarUpdate(SQLModel):
    # The body the Flutter app sends (same keys as CharacterConfig.toJson())
    skin: int = Field(ge=0, le=MAX_COLOR_VALUE)
    hair: int = Field(ge=0, le=MAX_COLOR_VALUE)
    shirt: int = Field(ge=0, le=MAX_COLOR_VALUE)
    pants: int = Field(ge=0, le=MAX_COLOR_VALUE)
    shoes: int = Field(ge=0, le=MAX_COLOR_VALUE)


class ProfileUpdate(SQLModel):
    # The body of PUT /users/me (Edit Profile). Every field is optional.
    username: Optional[str] = None
    display_name: Optional[str] = None
    gender: Optional[str] = None


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
    with Session(engine) as session:
        for line in ensure_habits(session):  # adds the 4 default habits if they are missing
            if line.startswith("Added"):
                logger.info("Habit %s", line)
        for line in ensure_rooms(session):  # adds the default groups if they are missing
            if line.startswith("Added"):
                logger.info("Group %s", line)
    try:
        init_firebase()
    except Exception:
        logger.error(
            "Firebase login checks could not start. Check FIREBASE_PROJECT_ID in backend/.env, "
            "or the service-account key in FIREBASE_SERVICE_ACCOUNT / FIREBASE_CREDENTIALS if you set one."
        )
        raise
    if ai_verification.is_configured():
        logger.info("AI verification ready (model: %s)", ai_verification.model_name())
    else:
        logger.warning("GEMINI_API_KEY is not set: photo verification will return 503 until you add it to backend/.env")
    yield
    # (code after yield would run when the server stops)


app = FastAPI(lifespan=lifespan)


def _cors_settings() -> dict:
    # The phone apps don't need CORS; only Flutter Web running in a browser does.
    # By default any localhost / 127.0.0.1 port is allowed (Flutter Web picks a random port).
    # For a deployed web app, list its address in CORS_ORIGINS (comma-separated).
    origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
    return {
        "allow_origins": origins,
        "allow_origin_regex": r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        "allow_credentials": False,  # the app sends a Bearer token, not cookies
        "allow_methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        "allow_headers": ["Authorization", "Content-Type"],
    }


app.add_middleware(CORSMiddleware, **_cors_settings())
app.include_router(groups.router)
app.include_router(photos.router)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
def _verified_dates(session: Session, user_id: int) -> set:
    return set(
        session.exec(
            select(HabitLog.completed_date).where(
                HabitLog.user_id == user_id,
                HabitLog.verification_status == "verified",
            ).distinct()
        ).all()
    )


def get_user_streak(session: Session, user_id: int) -> int:
    # Days in a row with at least one verified habit (any habit).
    return count_streak(_verified_dates(session, user_id), today_ksa())


def _count_verified(session: Session, user_id: int) -> int:
    return session.exec(
        select(func.count()).select_from(HabitLog).where(
            HabitLog.user_id == user_id,
            HabitLog.verification_status == "verified",
        )
    ).one()


def _normalize_gender(value: Optional[str]) -> Optional[str]:
    if value is None or not value.strip():
        return None
    gender = GENDER_VALUES.get(value.strip().lower())
    if gender is None:
        raise HTTPException(status_code=422, detail="gender must be 'male' or 'female'")
    return gender


def _clean_handle(text: str) -> str:
    # Keeps only the characters a username may contain (same rule as Edit Profile).
    clean = re.sub(r"[^a-zA-Z0-9_]", "", text or "")[:20]
    if len(clean) < 3:
        clean = (clean + "user")[:20]
    return clean


def _default_username(decoded_token: dict) -> str:
    # Used when a user logs in but has no row yet (for example, the account was
    # created while the backend was down). Built from the email, e.g. "sara_99".
    email = decoded_token.get("email") or ""
    base = decoded_token.get("name") or email.split("@")[0]
    return _clean_handle(base).lower()


def _username_taken(session: Session, username: str, exclude_user_id: Optional[int] = None) -> bool:
    query = select(User.id).where(func.lower(User.username) == username.lower())
    if exclude_user_id is not None:
        query = query.where(User.id != exclude_user_id)
    return session.exec(query).first() is not None


def _unique_username(session: Session, base: str) -> str:
    # "sara" -> "sara" if free, otherwise "sara2", "sara3"... (max 20 characters).
    candidate, n = base, 2
    while _username_taken(session, candidate):
        suffix = str(n)
        candidate = base[: 20 - len(suffix)] + suffix
        n += 1
    return candidate


def _new_user_names(session: Session, typed: Optional[str], decoded_token: dict) -> tuple[str, Optional[str]]:
    """(username, display_name) for a new account.

    Sign Up accepts any text as the username, but Edit Profile only accepts
    3-20 letters, numbers or underscores, and usernames must be unique. So the
    username is made valid and unique here; when that changes what the user
    typed, the typed text is kept as their display name.
    """
    typed = (typed or "").strip()
    if not typed:
        return _unique_username(session, _default_username(decoded_token)), None
    if USERNAME_PATTERN.match(typed):
        base = typed
    else:
        cleaned = re.sub(r"[^a-zA-Z0-9_]", "", typed)
        base = _clean_handle(cleaned) if cleaned else _default_username(decoded_token)
    username = _unique_username(session, base)
    display_name = None if username == typed else typed[:50]
    return username, display_name


def _iso_utc(value: datetime) -> str:
    # Database timestamps are stored in UTC without a timezone; send them with "Z".
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def user_profile(session: Session, user: User) -> dict:
    # Everything Home and Me need about the logged-in user.
    # The level is calculated from the points, so it always matches the progress bars.
    verified_dates = _verified_dates(session, user.id)
    today = today_ksa()
    today_points = session.exec(
        select(func.coalesce(func.sum(HabitLog.points_earned), 0)).where(
            HabitLog.user_id == user.id,
            HabitLog.completed_date == today,
            HabitLog.verification_status == "verified",
        )
    ).one()
    habits_completed = _count_verified(session, user.id)
    xp_into_level, xp_for_next_level = xp_progress(user.total_points)
    photo = photos.profile_photo(session, user.id)

    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
        "email": user.email,
        "gender": user.gender,
        # Relative address ("/photos/<token>.jpg"); null when there is no photo.
        "profile_image_url": photos.photo_url(photo.token) if photo else None,
        "total_points": user.total_points,
        "current_level": calculate_level(user.total_points),
        "xp_into_level": xp_into_level,
        "xp_for_next_level": xp_for_next_level,
        "streak_days": count_streak(verified_dates, today),
        "longest_streak": longest_streak(verified_dates),
        "today_points": today_points,
        "habits_completed": habits_completed,
        # Every completed habit was verified with a photo.
        "photos_verified": habits_completed,
        "groups_joined": groups.groups_joined(session, user.id),
    }


# ------------------------------------------------------------------
# Health
# ------------------------------------------------------------------
@app.get("/health")
def health_check(session: Session = Depends(get_session)):
    # Quick check for developers: is the server up, can it reach the database,
    # and is the AI key set? (Never returns the key itself.)
    try:
        session.exec(text("SELECT 1"))
        database = "ok"
    except Exception as e:
        logger.warning("Health check: database unreachable: %s", e)
        database = "unreachable"
    return {
        "status": "ok",
        "database": database,
        "database_type": database_kind(),
        "login_check": login_check_mode(),
        "ai_configured": ai_verification.is_configured(),
        "ai_model": ai_verification.model_name(),
    }


# ------------------------------------------------------------------
# Users
# ------------------------------------------------------------------
@app.post("/users/sync")
def sync_user(
    username: Optional[str] = None,
    gender: Optional[str] = None,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Makes sure the logged-in Firebase user has a row in our database.
    # Called on Sign Up (with username + gender) and after every Login (without them).
    # Safe to call any number of times.
    firebase_uid = decoded_token["uid"]
    email = decoded_token.get("email", "") or ""
    gender = _normalize_gender(gender)

    user = session.exec(
        select(User).where(User.firebase_uid == firebase_uid)
    ).first()

    if user is None:
        clean_username, display_name = _new_user_names(session, username, decoded_token)
        user = User(
            firebase_uid=firebase_uid,
            username=clean_username,
            display_name=display_name,
            email=email,
            gender=gender,
        )
        session.add(user)
        try:
            session.commit()
        except IntegrityError:
            # Two sync calls for the same account at the same moment (e.g. Sign Up
            # and an automatic retry): the other one created the row first.
            session.rollback()
            user = session.exec(select(User).where(User.firebase_uid == firebase_uid)).first()
            if user is None:
                raise
            return user_profile(session, user)
        session.refresh(user)
        logger.info("Created user %s (%s)", user.id, user.username)
    else:
        changed = False
        if gender and user.gender != gender:
            user.gender = gender
            changed = True
        if email and user.email != email:  # e.g. the email was changed in Firebase
            user.email = email
            changed = True
        if changed:
            session.add(user)
            session.commit()
            session.refresh(user)

    return user_profile(session, user)


@app.get("/users/me")
def get_me(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Everything the Home header and the Me page need: name, points, level, streaks...
    user = get_current_user(session, decoded_token)
    return user_profile(session, user)


@app.put("/users/me")
def update_me(
    data: ProfileUpdate,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Edit Profile: change username, display name or gender. 409 if the username is taken.
    user = get_current_user(session, decoded_token)

    if data.username is not None:
        clean = data.username.strip()
        if not USERNAME_PATTERN.match(clean):
            raise HTTPException(
                status_code=422,
                detail="Username must be 3-20 letters, numbers or underscores.",
            )
        clean = clean.lower()
        if _username_taken(session, clean, exclude_user_id=user.id):
            raise HTTPException(status_code=409, detail="That username is taken.")
        user.username = clean

    if data.display_name is not None:
        name = data.display_name.strip()[:50]
        user.display_name = name or None

    if data.gender is not None:
        user.gender = _normalize_gender(data.gender)

    session.add(user)
    session.commit()
    session.refresh(user)
    return user_profile(session, user)


@app.post("/users/me/photo")
def upload_profile_photo(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # Me page: set or replace the profile photo (stored as a 640 px JPEG).
    user = get_current_user(session, decoded_token)
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Only JPEG, PNG, or WEBP images are allowed.")
    image_bytes = file.file.read(MAX_IMAGE_SIZE + 1)
    if len(image_bytes) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="Image is too large (max 5 MB).")
    try:
        jpeg = ai_verification.prepare_image(image_bytes)
    except ai_verification.InvalidImageError:
        raise HTTPException(status_code=415, detail="Could not read the image.")

    old = photos.profile_photo(session, user.id)
    if old:
        session.delete(old)
        session.flush()
    photos.save_photo(session, user.id, "profile", jpeg)
    session.commit()
    return user_profile(session, user)


@app.delete("/users/me/photo")
def delete_profile_photo(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    user = get_current_user(session, decoded_token)
    old = photos.profile_photo(session, user.id)
    if old:
        session.delete(old)
        session.commit()
    return user_profile(session, user)


@app.get("/users/me/avatar")
def get_my_avatar(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    user = get_current_user(session, decoded_token)

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
    user = get_current_user(session, decoded_token)

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


# ------------------------------------------------------------------
# Habits
# ------------------------------------------------------------------
@app.get("/habits")
def get_habits(
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    habits = session.exec(select(Habit).order_by(Habit.id)).all()
    return habits


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

        result.append({
            "id": habit.id,
            "name": habit.name,
            "points": habit.points,
            "ai_label": habit.ai_label,
            # "Study" or "Health": same rule as the Habits history. The app uses it
            # for "My habits" and to match habits to the user's groups.
            "category": habit_category(habit.name),
            "completed_today": today in done_dates,
            "streak": count_streak(done_dates, today),
        })

    return result


@app.get("/habit-logs")
def get_habit_logs(
    month: str = Query(..., pattern=r"^\d{4}-\d{2}$", description="Calendar month, e.g. 2026-10"),
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token)
):
    # The Habits page history: this user's verified completions in one month, newest first.
    user = get_current_user(session, decoded_token)
    year, mon = int(month[:4]), int(month[5:7])
    if not 1 <= mon <= 12:
        raise HTTPException(status_code=422, detail="month must look like 2026-10")
    start = date(year, mon, 1)
    end = date(year + 1, 1, 1) if mon == 12 else date(year, mon + 1, 1)

    rows = session.exec(
        select(HabitLog, Habit)
        .join(Habit, Habit.id == HabitLog.habit_id)
        .where(
            HabitLog.user_id == user.id,
            HabitLog.verification_status == "verified",
            HabitLog.completed_date >= start,
            HabitLog.completed_date < end,
        )
        .order_by(HabitLog.completed_at.desc())
    ).all()
    tokens = photos.tokens_for_logs(session, [log.id for log, _ in rows])

    return [
        {
            "id": log.id,
            "habit_id": habit.id,
            "habit_name": habit.name,
            "category": habit_category(habit.name),
            "completed_at": _iso_utc(log.completed_at),
            "points_earned": log.points_earned,
            # Relative address of the saved verification photo ("" for older logs).
            "image_url": photos.photo_url(tokens.get(log.id)) or "",
        }
        for log, habit in rows
    ]


# ------------------------------------------------------------------
# AI photo verification (Gemini)
# ------------------------------------------------------------------
def _already_verified_today(session: Session, user_id: int, habit_id: int) -> bool:
    return session.exec(
        select(HabitLog.id).where(
            HabitLog.user_id == user_id,
            HabitLog.habit_id == habit_id,
            HabitLog.completed_date == today_ksa(),
            HabitLog.verification_status == "verified",
        )
    ).first() is not None


def _rejected_today(session: Session, user_id: int, habit_id: int) -> int:
    return session.exec(
        select(func.count()).select_from(HabitLog).where(
            HabitLog.user_id == user_id,
            HabitLog.habit_id == habit_id,
            HabitLog.completed_date == today_ksa(),
            HabitLog.verification_status == "rejected",
        )
    ).one()


# Plain `def` (not async) on purpose: FastAPI runs it in a worker thread,
# so waiting for Gemini doesn't block the other endpoints.
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

    expected = ai_verification.expected_activity_for(habit.name)
    if expected is None:
        raise HTTPException(status_code=400, detail="This habit does not support photo verification.")

    # 2. Block if this habit is already completed today (before calling Gemini)
    if _already_verified_today(session, user.id, habit.id):
        raise HTTPException(status_code=409, detail="This habit is already completed today.")

    # 3. Block if the user used all rejected attempts today
    rejected_count = _rejected_today(session, user.id, habit.id)
    if rejected_count >= MAX_REJECTED_ATTEMPTS:
        raise HTTPException(status_code=429, detail="No attempts left for this habit today. Try again tomorrow.")

    # 4. Check the uploaded file is an image and not too large
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Only JPEG, PNG, or WEBP images are allowed.")
    image_bytes = file.file.read(MAX_IMAGE_SIZE + 1)
    if len(image_bytes) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="Image is too large (max 5 MB).")

    try:
        jpeg = ai_verification.prepare_image(image_bytes)
    except ai_verification.InvalidImageError:
        raise HTTPException(status_code=415, detail="Could not read the image.")

    # 5. Ask Gemini what the photo shows. If Gemini is down, nothing is saved
    #    and the attempt does not count, so the user can simply try again.
    try:
        verdict = ai_verification.analyze_photo(jpeg)
    except ai_verification.AIServiceError as e:
        logger.warning("AI verification unavailable: %s", e)
        raise HTTPException(
            status_code=503,
            detail="Photo verification is temporarily unavailable. Please try again in a minute.",
        )

    is_verified = ai_verification.passes(verdict, expected)

    # Re-check: two quick taps could both get this far while Gemini was thinking
    if is_verified and _already_verified_today(session, user.id, habit.id):
        raise HTTPException(status_code=409, detail="This habit is already completed today.")

    reason = verdict.reason.strip()[:500]

    # 6. Save this attempt (verified or rejected)
    log = HabitLog(
        habit_id=habit.id,
        user_id=user.id,
        completed_date=today_ksa(),
        points_earned=habit.points if is_verified else 0,
        verification_status="verified" if is_verified else "rejected",
        predicted_label=verdict.detected_activity.value,
        confidence=None,
        ai_reason=f"{verdict.confidence.value}, {verdict.evidence.value}: {reason}",
    )
    session.add(log)
    if is_verified:
        session.flush()  # gives the log its id
        photos.save_photo(session, user.id, "verification", jpeg, habit_log_id=log.id)

    # 7. On success: add the points and recalculate the level.
    #    The addition happens inside the database (total_points = total_points + X),
    #    so two habits verified at the same moment can't overwrite each other's points.
    previous_level = calculate_level(user.total_points)
    if is_verified:
        session.exec(
            update(User)
            .where(User.id == user.id)
            .values(total_points=User.total_points + habit.points)
        )
    session.commit()
    session.refresh(user)
    new_level = calculate_level(user.total_points)
    if user.current_level != new_level:
        user.current_level = new_level
        session.add(user)
        session.commit()
        session.refresh(user)
    session.refresh(log)

    if is_verified:
        attempts_remaining = MAX_REJECTED_ATTEMPTS - rejected_count
    else:
        attempts_remaining = MAX_REJECTED_ATTEMPTS - (rejected_count + 1)

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
        "points_earned": log.points_earned,
        "attempts_remaining": attempts_remaining,
        "habit_log_id": log.id,
        "total_points": user.total_points,
        "current_level": user.current_level,
        "leveled_up": user.current_level > previous_level,
    }


# ------------------------------------------------------------------
# Progress
# ------------------------------------------------------------------
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

    return {
        "total_points": user.total_points,
        "current_level": calculate_level(user.total_points),
        "streak_days": get_user_streak(session, user.id),
        "total_habits_completed": _count_verified(session, user.id),
        "last_7_days": last_7_days,
    }
