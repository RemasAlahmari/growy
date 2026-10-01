from sqlmodel import Session, select
from database import engine
from models import Habit

HABITS = [
    {"name": "Reading", "points": 10, "ai_label": "a person reading a book"},
    {"name": "Walking", "points": 10, "ai_label": "a person walking outdoors"},
    {"name": "Workout", "points": 10, "ai_label": "a person exercising or working out"},
    {"name": "Drink Water", "points": 5, "ai_label": "a glass or bottle of drinking water"},
]


def seed():
    with Session(engine) as session:
        for data in HABITS:
            exists = session.exec(select(Habit).where(Habit.name == data["name"])).first()
            if exists:
                print(f"Skipped (already exists): {data['name']}")
                continue
            session.add(Habit(**data))
            print(f"Added: {data['name']}")
        session.commit()


if __name__ == "__main__":
    seed()