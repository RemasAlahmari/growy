from typing import Optional
from datetime import datetime, date, timezone, timedelta
from sqlalchemy import BigInteger
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
    streak_days: int = Field(default=0)


class Habit(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(unique=True)
    points: int
    ai_label: str  # candidate label used for CLIP matching


class HabitLog(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    habit_id: int = Field(foreign_key="habit.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    completed_at: datetime = Field(default_factory=now_utc)
    completed_date: date = Field(default_factory=today_ksa)
    points_earned: int
    verification_status: str = Field(default="pending")
    predicted_label: Optional[str] = None
    confidence: Optional[float] = None


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