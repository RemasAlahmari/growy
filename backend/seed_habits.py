from sqlmodel import Session, select
from database import engine
from models import Habit

# "ai_label" is the instruction shown in the app under "Take a clear photo showing:".
# The habit NAME decides what Gemini checks for (see HABIT_ACTIVITY in ai_verification.py),
# so keep these four names exactly as they are.
HABITS = [
    {"name": "Reading", "points": 10,
     "ai_label": "You reading, e.g. your hands holding an open book"},
    {"name": "Walking", "points": 10,
     "ai_label": "You walking outside, e.g. your feet on a sidewalk or path"},
    {"name": "Workout", "points": 10,
     "ai_label": "You exercising, e.g. lifting weights or using gym equipment"},
    {"name": "Drink Water", "points": 5,
     "ai_label": "You drinking water, e.g. your hand holding a glass or bottle"},
]


def seed():
    with Session(engine) as session:
        for data in HABITS:
            habit = session.exec(select(Habit).where(Habit.name == data["name"])).first()
            if habit is None:
                session.add(Habit(**data))
                print(f"Added: {data['name']}")
            elif habit.points != data["points"] or habit.ai_label != data["ai_label"]:
                habit.points = data["points"]
                habit.ai_label = data["ai_label"]
                session.add(habit)
                print(f"Updated: {data['name']}")
            else:
                print(f"Unchanged: {data['name']}")
        session.commit()


if __name__ == "__main__":
    seed()
