from typing import Optional
from datetime import datetime, date, timezone, timedelta
from sqlmodel import SQLModel, Field

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