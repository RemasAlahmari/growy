from typing import Optional
from sqlmodel import SQLModel, Field

class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    firebase_uid: str = Field(index=True, unique=True)
    username: str
    email: str
    total_points: int = Field(default=0)
    current_level: int = Field(default=1)
    streak_days: int = Field(default=0)