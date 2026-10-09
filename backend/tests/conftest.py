import pytest
from fastapi.testclient import TestClient
from sqlmodel import SQLModel, Session, create_engine
from sqlmodel.pool import StaticPool

from main import app
from database import get_session
from auth import verify_token
from models import User, Habit

TEST_UID = "test-user-uid"


@pytest.fixture
def session():
    # A fresh in-memory database for every test (never touches Supabase)
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        # One test user and one habit (id = 1, 10 points)
        session.add(User(firebase_uid=TEST_UID, username="tester", email="tester@example.com"))
        session.add(Habit(name="Reading", points=10, ai_label="a person reading a book"))
        session.commit()
        yield session


@pytest.fixture
def client(session):
    # Replace the real database and Firebase check with test versions
    def get_session_override():
        return session

    def verify_token_override():
        return {"uid": TEST_UID, "email": "tester@example.com"}

    app.dependency_overrides[get_session] = get_session_override
    app.dependency_overrides[verify_token] = verify_token_override
    yield TestClient(app)
    app.dependency_overrides.clear()