"""
Shared test setup. Run from the backend folder:  pytest -v

- Uses an in-memory SQLite database (your Supabase data is never touched).
- Skips Firebase: requests are treated as coming from a fake logged-in user.
- Never calls Gemini: each test decides what the "AI" answers.
"""
import io
import os
import sys

# Must happen BEFORE the app is imported (load_dotenv never overrides these)
os.environ["DATABASE_URL"] = "sqlite://"
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

import ai_verification
import main
from auth import verify_token
from database import get_session
from models import Habit, HabitLog, User

TEST_UID = "test-firebase-uid"


@pytest.fixture()
def engine():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(eng)
    with Session(eng) as s:
        s.add(User(firebase_uid=TEST_UID, username="tester", email="t@example.com"))
        s.add(User(firebase_uid="other-uid", username="other", email="o@example.com"))
        for name, pts in [("Reading", 10), ("Walking", 10), ("Workout", 10), ("Drink Water", 5), ("Meditation", 10)]:
            s.add(Habit(name=name, points=pts, ai_label=f"label for {name}"))
        s.commit()
    return eng


@pytest.fixture()
def db(engine):
    with Session(engine) as s:
        yield s


@pytest.fixture()
def client(db):
    # The endpoint and the test share one session (pattern from the SQLModel docs)
    main.app.dependency_overrides[get_session] = lambda: db
    main.app.dependency_overrides[verify_token] = lambda: {"uid": TEST_UID, "email": "t@example.com"}
    # No "with": startup (Supabase + Firebase init) is deliberately not run in tests
    yield TestClient(main.app)
    main.app.dependency_overrides.clear()


@pytest.fixture()
def fake_ai(monkeypatch):
    """Call fake_ai("walking", "activity_in_progress", "high") to choose the AI's answer."""
    calls = []

    def set_answer(activity="walking", evidence="activity_in_progress", confidence="high",
                   reason="A person walking outdoors.", error=None):
        def _analyze(jpeg_bytes):
            calls.append(jpeg_bytes)
            if error is not None:
                raise error
            return ai_verification.Verdict(
                detected_activity=activity, evidence=evidence,
                confidence=confidence, reason=reason,
            )
        monkeypatch.setattr(ai_verification, "analyze_photo", _analyze)
        return calls

    return set_answer


def make_jpeg(size=(800, 600), color=(90, 140, 90)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "JPEG")
    return buf.getvalue()


def habit_id(db, name):
    return db.exec(select(Habit.id).where(Habit.name == name)).one()


def upload(client, hid, data=None, content_type="image/jpeg", filename="photo.jpg"):
    data = make_jpeg() if data is None else data
    return client.post(f"/habits/{hid}/complete/ai", files={"file": (filename, data, content_type)})


def get_user(db, uid=TEST_UID):
    db.expire_all()
    return db.exec(select(User).where(User.firebase_uid == uid)).one()


def logs(db):
    db.expire_all()
    return db.exec(select(HabitLog)).all()
