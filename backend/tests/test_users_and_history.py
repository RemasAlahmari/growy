"""Tests for the user, profile, history and health endpoints used by Home, Me and Habits."""
from datetime import date, datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlmodel import select

import main
from auth import verify_token
from conftest import TEST_UID, get_user, habit_id, upload
from leveling import xp_progress
from models import Habit, HabitLog, User, today_ksa
from seed_habits import HABITS, ensure_habits
from streaks import longest_streak


def as_user(uid, email="new@example.com", name=None):
    token = {"uid": uid, "email": email}
    if name:
        token["name"] = name
    main.app.dependency_overrides[verify_token] = lambda: token


# ---------- POST /users/sync ----------
def test_sync_creates_user_with_username_and_gender(client, db):
    as_user("new-uid", "sara@example.com")
    r = client.post("/users/sync", params={"username": "Sara", "gender": "female"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["username"] == "Sara"
    assert body["gender"] == "female"
    assert body["email"] == "sara@example.com"
    assert body["total_points"] == 0 and body["current_level"] == 0
    assert get_user(db, "new-uid").gender == "female"


def test_sync_after_login_without_username_creates_missing_row(client, db):
    # The account exists in Firebase but not in our database (e.g. backend was down on Sign Up)
    as_user("orphan-uid", "noura.m+test@example.com")
    r = client.post("/users/sync")
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "nouramtest"
    # ...and Home works right after
    assert client.get("/users/me").status_code == 200
    assert client.get("/habits/today").status_code == 200


def test_sync_is_idempotent_and_keeps_username(client, db):
    r1 = client.post("/users/sync", params={"username": "changed"})
    r2 = client.post("/users/sync")
    assert r1.json()["username"] == "tester" == r2.json()["username"]
    assert db.exec(select(User).where(User.firebase_uid == TEST_UID)).all().__len__() == 1


def test_sync_fills_gender_for_existing_user(client, db):
    assert client.post("/users/sync", params={"gender": "male"}).json()["gender"] == "male"
    assert get_user(db).gender == "male"


def test_sync_rejects_unknown_gender(client):
    assert client.post("/users/sync", params={"gender": "robot"}).status_code == 422


def test_short_email_gets_padded_username(client):
    as_user("short-uid", "ab@example.com")
    assert client.post("/users/sync").json()["username"] == "abuser"


# ---------- GET /users/me ----------
def test_me_returns_everything_home_and_me_need(client):
    body = client.get("/users/me").json()
    for key in ["id", "username", "display_name", "email", "gender", "total_points",
                "current_level", "xp_into_level", "xp_for_next_level", "streak_days",
                "longest_streak", "today_points", "habits_completed", "photos_verified"]:
        assert key in body, key
    assert body["display_name"] == "tester"  # falls back to username
    assert body["xp_into_level"] == 0 and body["xp_for_next_level"] == 100


def test_me_after_verified_photo(client, db):
    upload(client, habit_id(db, "Reading"))
    body = client.get("/users/me").json()
    assert body["total_points"] == 10
    assert body["today_points"] == 10
    assert body["streak_days"] == 1
    assert body["longest_streak"] == 1
    assert body["habits_completed"] == 1 and body["photos_verified"] == 1
    assert body["xp_into_level"] == 10 and body["xp_for_next_level"] == 100


def test_me_level_is_calculated_from_points(client, db):
    # A row saved with a wrong level (e.g. by an older formula) is shown correctly
    user = get_user(db)
    user.total_points, user.current_level = 10, 1
    db.add(user); db.commit()
    assert client.get("/users/me").json()["current_level"] == 0


def test_unknown_user_gets_404_with_hint(client):
    as_user("nobody-uid")
    r = client.get("/users/me")
    assert r.status_code == 404
    assert "/users/sync" in r.json()["detail"]


# ---------- PUT /users/me ----------
def test_update_profile(client, db):
    r = client.put("/users/me", json={"username": "New_Name", "display_name": "  Sara A  "})
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "new_name"
    assert r.json()["display_name"] == "Sara A"
    assert get_user(db).username == "new_name"


def test_update_profile_username_taken_is_409(client):
    r = client.put("/users/me", json={"username": "OTHER"})
    assert r.status_code == 409


def test_update_profile_keeps_own_username(client):
    assert client.put("/users/me", json={"username": "Tester"}).status_code == 200


def test_update_profile_invalid_username_is_422(client):
    assert client.put("/users/me", json={"username": "a b"}).status_code == 422
    assert client.put("/users/me", json={"username": "ab"}).status_code == 422


def test_empty_display_name_falls_back_to_username(client):
    r = client.put("/users/me", json={"display_name": "   "})
    assert r.json()["display_name"] == "tester"


# ---------- GET /habit-logs ----------
def test_habit_logs_for_current_month(client, db):
    upload(client, habit_id(db, "Reading"))
    month = today_ksa().strftime("%Y-%m")
    r = client.get("/habit-logs", params={"month": month})
    assert r.status_code == 200, r.text
    [log] = r.json()
    assert log["habit_name"] == "Reading"
    assert log["category"] == "Study"
    assert log["points_earned"] == 10
    # The verified photo is saved and can be downloaded from its address
    assert log["image_url"].startswith("/photos/") and log["image_url"].endswith(".jpg")
    photo = client.get(log["image_url"])
    assert photo.status_code == 200
    assert photo.headers["content-type"] == "image/jpeg"
    assert log["completed_at"].endswith("Z")
    datetime.fromisoformat(log["completed_at"].replace("Z", "+00:00"))  # valid timestamp


def test_habit_logs_only_verified_and_only_that_month(client, db):
    user = get_user(db)
    walking = habit_id(db, "Walking")
    db.add(HabitLog(habit_id=walking, user_id=user.id, points_earned=0,
                    verification_status="rejected"))
    db.add(HabitLog(habit_id=walking, user_id=user.id, points_earned=10,
                    verification_status="verified", completed_date=date(2025, 1, 15),
                    completed_at=datetime(2025, 1, 15, 9, 0, tzinfo=timezone.utc)))
    db.commit()
    assert client.get("/habit-logs", params={"month": today_ksa().strftime("%Y-%m")}).json() == []
    [log] = client.get("/habit-logs", params={"month": "2025-01"}).json()
    assert log["category"] == "Health"
    assert log["completed_at"].startswith("2025-01-15T09:00:00")


def test_habit_logs_other_users_are_hidden(client, db):
    other = get_user(db, "other-uid")
    db.add(HabitLog(habit_id=habit_id(db, "Reading"), user_id=other.id, points_earned=10,
                    verification_status="verified"))
    db.commit()
    assert client.get("/habit-logs", params={"month": today_ksa().strftime("%Y-%m")}).json() == []


def test_habit_logs_bad_month_is_422(client):
    assert client.get("/habit-logs", params={"month": "2026-13"}).status_code == 422
    assert client.get("/habit-logs", params={"month": "October"}).status_code == 422


def test_habit_logs_december(client):
    assert client.get("/habit-logs", params={"month": "2025-12"}).status_code == 200


# ---------- health & CORS ----------
def test_health_reports_database_and_ai(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["database_type"] == "sqlite"  # the tests use an in-memory SQLite database
    assert body["database"] == "ok"
    assert "ai_configured" in body


def test_cors_allows_flutter_web_on_localhost(client):
    r = client.options(
        "/users/me",
        headers={
            "Origin": "http://localhost:53124",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] == "http://localhost:53124"


def test_cors_blocks_unknown_websites(client):
    r = client.options(
        "/users/me",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in r.headers


def test_missing_token_is_401(engine):
    main.app.dependency_overrides.clear()
    assert TestClient(main.app).get("/users/me").status_code == 401


# ---------- helpers ----------
def test_ensure_habits_adds_missing_without_overwriting(db):
    reading = db.exec(select(Habit).where(Habit.name == "Reading")).one()
    report = ensure_habits(db)
    names = {h.name for h in db.exec(select(Habit)).all()}
    assert {h["name"] for h in HABITS} <= names
    assert reading.ai_label == "label for Reading"  # a team's own edits are kept at startup
    assert "Unchanged: Reading" in report


def test_ensure_habits_update_mode_refreshes_labels(db):
    ensure_habits(db, update_existing=True)
    reading = db.exec(select(Habit).where(Habit.name == "Reading")).one()
    assert reading.ai_label == HABITS[0]["ai_label"]


def test_longest_streak():
    d = date(2026, 10, 10)
    days = {d, d - timedelta(days=1), d - timedelta(days=2), d - timedelta(days=5)}
    assert longest_streak(days) == 3
    assert longest_streak(set()) == 0


def test_xp_progress():
    assert xp_progress(0) == (0, 100)
    assert xp_progress(99) == (99, 100)
    assert xp_progress(100) == (0, 400)
    assert xp_progress(950) == (450, 1000)
    assert xp_progress(3000) == (0, None)
    assert xp_progress(5000) == (2000, None)
