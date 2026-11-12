from typing import Optional
from datetime import datetime, date, timezone, timedelta
from sqlalchemy import BigInteger, LargeBinary, UniqueConstraint
from sqlmodel import SQLModel, Field

# توقيت السعودية (UTC+3)
KSA_TZ = timezone(timedelta(hours=3))


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def today_ksa() -> date:
    return datetime.now(KSA_TZ).date()


class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    firebase_uid: str = Field(index=True, unique=True)
    username: str
    email: str
    total_points: int = Field(default=0)
    current_level: int = Field(default=0)
    # Not used: the streak is calculated from HabitLog on every request (see get_user_streak).
    streak_days: int = Field(default=0)
    # "male" / "female", chosen on Sign Up. Decides the boy/girl avatar.
    # Existing databases get these two columns automatically at startup (see database.py).
    gender: Optional[str] = None
    # Name shown on the Me page (Edit Profile). Falls back to username when empty.
    display_name: Optional[str] = None


class Habit(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True)
    points: int
    # Instruction shown in the app under "Take a clear photo showing:".
    # (Gemini doesn't use it; the expected activity comes from the habit name,
    # see HABIT_ACTIVITY in ai_verification.py.)
    ai_label: str


class HabitLog(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    habit_id: int = Field(foreign_key="habit.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    completed_at: datetime = Field(default_factory=now_utc)
    completed_date: date = Field(default_factory=today_ksa)
    points_earned: int
    verification_status: str = Field(default="pending")
    predicted_label: Optional[str] = None   # the activity the AI detected, e.g. "walking"
    confidence: Optional[float] = None      # unused with Gemini (kept for old rows)
    # Why the AI accepted/rejected the photo, e.g. "high, activity_in_progress: Feet walking on a sidewalk."
    # Existing databases get this column automatically at startup (see database.py).
    ai_reason: Optional[str] = None


class Avatar(SQLModel, table=True):
    # One avatar per user. Colors are stored as Flutter Color.value numbers (ARGB),
    # which are too big for a normal INTEGER, so BigInteger is used.
    # Defaults match CharacterConfig.defaultConfig() in the Flutter app.
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", unique=True)
    skin: int = Field(default=0xFFF5D0B0, sa_type=BigInteger)
    hair: int = Field(default=0xFF8B5E3C, sa_type=BigInteger)
    shirt: int = Field(default=0xFFFF8FA3, sa_type=BigInteger)
    pants: int = Field(default=0xFF3A506B, sa_type=BigInteger)
    shoes: int = Field(default=0xFFFFFFFF, sa_type=BigInteger)


# ------------------------------------------------------------------
# Groups ("rooms"). New tables: created automatically at startup.
# ------------------------------------------------------------------
class Room(SQLModel, table=True):
    # A group users can join. The app has no "create group" screen, so the
    # default groups are added at startup (see seed_groups.py).
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True)
    description: str = ""
    category: str = "Health"              # "Study" or "Health"
    icon_key: str = "run"                 # "run", "book", "water" or "mind" (picks the app icon)
    code: str = Field(unique=True, index=True)  # invite code, stored in UPPERCASE
    # Optional monthly group goal: "earn goal_target XP together this month".
    goal_title: Optional[str] = None
    goal_target: Optional[int] = None
    created_at: datetime = Field(default_factory=now_utc)


class RoomMember(SQLModel, table=True):
    # A user in a group. Only XP earned after joined_at counts in that group.
    __table_args__ = (UniqueConstraint("room_id", "user_id"),)
    id: Optional[int] = Field(default=None, primary_key=True)
    room_id: int = Field(foreign_key="room.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    joined_at: datetime = Field(default_factory=now_utc)


class RoomDismissal(SQLModel, table=True):
    # A group the user hid from "Groups to join" ("Not interested").
    __table_args__ = (UniqueConstraint("room_id", "user_id"),)
    id: Optional[int] = Field(default=None, primary_key=True)
    room_id: int = Field(foreign_key="room.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True)


# ------------------------------------------------------------------
# Photos (stored in the database, no paid storage service needed)
# ------------------------------------------------------------------
class Photo(SQLModel, table=True):
    # A small JPEG (max 640 px): a verified habit photo or a profile photo.
    # Served at GET /photos/{token}.jpg. The token is long and random, so the
    # address can't be guessed; anyone who has the address can open the photo.
    id: Optional[int] = Field(default=None, primary_key=True)
    token: str = Field(unique=True, index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    kind: str                              # "verification" or "profile"
    habit_log_id: Optional[int] = Field(default=None, foreign_key="habitlog.id", index=True)
    data: bytes = Field(sa_type=LargeBinary)
    created_at: datetime = Field(default_factory=now_utc)
