from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from models import Room

# The app has no "create group" screen yet, so these groups are added at startup
# (only the missing ones; edits made in the database are kept).
# Names, descriptions and codes come from the Groups screen design.
# A goal is "earn goal_target XP together this calendar month"; a verified
# habit is worth 5-10 XP, so the targets are sized for a handful of members.
ROOMS = [
    {"name": "10K Steps Squad", "category": "Health", "icon_key": "run", "code": "STEPS10",
     "description": "Walk, run or hike your way to 10,000 steps a day with friends who keep you honest.",
     "goal_title": "Earn 1,000 XP together this month", "goal_target": 1000},
    {"name": "Study Together", "category": "Study", "icon_key": "book", "code": "STUDY24",
     "description": "Daily reading and focused study sessions. Snap your desk, earn XP, climb the board.",
     "goal_title": "Earn 900 XP as a group this month", "goal_target": 900},
    {"name": "Hydration Heroes", "category": "Health", "icon_key": "water", "code": "WATER8",
     "description": "Eight glasses a day, every day. Small habit, big difference."},
    {"name": "Morning Runners", "category": "Health", "icon_key": "run", "code": "GROWY1",
     "description": "Early runs before the heat. Share your route, keep your streak.",
     "goal_title": "Earn 600 XP together this month", "goal_target": 600},
    {"name": "Exam Prep Circle", "category": "Study", "icon_key": "book", "code": "EXAM50",
     "description": "Focused study sessions for midterms and finals. Quiet, steady, consistent."},
    {"name": "Mindful Mornings", "category": "Health", "icon_key": "mind", "code": "CALM30",
     "description": "A calm start: stretch, breathe and eat a healthy breakfast before the day begins."},
    {"name": "Book Club Readers", "category": "Study", "icon_key": "book", "code": "READ20",
     "description": "Twenty pages a day adds up to a book a month.",
     "goal_title": "Earn 500 XP together this month", "goal_target": 500},
]


def ensure_rooms(session: Session) -> list[str]:
    """Adds any default group that is missing (matched by name). Returns a report."""
    report = []
    for data in ROOMS:
        exists = session.exec(select(Room.id).where(Room.name == data["name"])).first()
        if exists is None:
            session.add(Room(**data))
            report.append(f"Added: {data['name']}")
        else:
            report.append(f"Unchanged: {data['name']}")
    try:
        session.commit()
    except IntegrityError:
        # Another server process added the same default groups at the same moment.
        session.rollback()
        report.append("Skipped: already added by another server process")
    return report


if __name__ == "__main__":
    from database import engine

    with Session(engine) as s:
        for line in ensure_rooms(s):
            print(line)
