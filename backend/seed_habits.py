from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

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


def ensure_habits(session: Session, update_existing: bool = False) -> list[str]:
    """Adds any of the default habits that are missing.

    The server calls this at startup (update_existing=False), so a new or empty
    database always has habits for the Home screen. Running this file by hand
    (update_existing=True) also refreshes the points and photo instructions.
    Returns one line per habit describing what happened.
    """
    report = []
    for data in HABITS:
        habit = session.exec(select(Habit).where(Habit.name == data["name"])).first()
        if habit is None:
            session.add(Habit(**data))
            report.append(f"Added: {data['name']}")
        elif update_existing and (habit.points != data["points"] or habit.ai_label != data["ai_label"]):
            habit.points = data["points"]
            habit.ai_label = data["ai_label"]
            session.add(habit)
            report.append(f"Updated: {data['name']}")
        else:
            report.append(f"Unchanged: {data['name']}")
    try:
        session.commit()
    except IntegrityError:
        # Another server process added the same default habits at the same moment.
        session.rollback()
        report.append("Skipped: already added by another server process")
    return report


def seed():
    from database import engine  # imported here so main.py can import HABITS cheaply

    with Session(engine) as session:
        for line in ensure_habits(session, update_existing=True):
            print(line)


if __name__ == "__main__":
    seed()
