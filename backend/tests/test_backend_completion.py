"""Backend gaps found in the Nov 2026 review: Sign Up usernames, avatar saving,
the habit list, health details, safe points updates and safe startup seeding."""
import io
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

import main
from auth import verify_token
from conftest import TEST_UID, get_user, habit_id, make_jpeg, upload
from models import Avatar, Habit, Room, User
from seed_groups import ROOMS, ensure_rooms
from seed_habits import HABITS, ensure_habits


def as_user(uid, email="new@example.com"):
    main.app.dependency_overrides[verify_token] = lambda: {"uid": uid, "email": email}


def sign_up(client, uid, username, email="new@example.com"):
    as_user(uid, email)
    r = client.post("/users/sync", params={"username": username, "gender": "female"})
    assert r.status_code == 200, r.text
    return r.json()


# ---------- Sign Up usernames ----------
def test_valid_unique_username_is_kept_exactly(client):
    body = sign_up(client, "u1", "Noura_1")
    assert body["username"] == "Noura_1"
    assert body["display_name"] == "Noura_1"  # falls back to the username


def test_username_with_spaces_becomes_a_valid_handle_and_keeps_the_typed_name(client):
    body = sign_up(client, "u2", "Sara Ahmed")
    assert body["username"] == "SaraAhmed"
    assert body["display_name"] == "Sara Ahmed"


def test_arabic_username_uses_the_email_and_keeps_the_typed_name(client):
    body = sign_up(client, "u3", "سارة", email="sara.k@example.com")
    assert body["username"] == "sarak"
    assert body["display_name"] == "سارة"


def test_taken_username_gets_a_number(client):
    # "tester" already exists (conftest); the check ignores upper/lower case.
    assert sign_up(client, "u4", "tester")["username"] == "tester2"
    assert sign_up(client, "u5", "TESTER")["username"] == "TESTER3"
    body = sign_up(client, "u6", "tester")
    assert body["username"] == "tester4"
    assert body["display_name"] == "tester"


def test_long_taken_username_stays_within_20_characters(client):
    first = sign_up(client, "u7", "abcdefghijklmnopqrst")
    second = sign_up(client, "u8", "abcdefghijklmnopqrst")
    assert first["username"] == "abcdefghijklmnopqrst"
    assert second["username"] == "abcdefghijklmnopqrs2"


def test_edit_profile_works_right_after_sign_up_with_a_duplicate_name(client):
    # Before the fix, two users called "tester" both got 409 from Edit Profile.
    body = sign_up(client, "u9", "tester")
    r = client.put("/users/me", json={"display_name": "New Name", "username": body["username"]})
    assert r.status_code == 200, r.text
    assert r.json()["display_name"] == "New Name"


def test_login_without_username_avoids_taken_names(client, db):
    db.add(User(firebase_uid="x", username="nouramtest", email="other@example.com"))
    db.commit()
    as_user("orphan", "noura.m+test@example.com")
    assert client.post("/users/sync").json()["username"] == "nouramtest2"


def test_second_sync_for_same_account_does_not_create_a_duplicate(client, db):
    sign_up(client, "dup", "Lama")
    as_user("dup")
    assert client.post("/users/sync", params={"username": "Other"}).json()["username"] == "Lama"
    assert len(db.exec(select(User).where(User.firebase_uid == "dup")).all()) == 1


# ---------- Avatar ----------
def test_avatar_defaults_then_save_and_load(client, db):
    r = client.get("/users/me/avatar")
    assert r.status_code == 200
    defaults = r.json()
    assert set(defaults) == {"skin", "hair", "shirt", "pants", "shoes"}
    assert db.exec(select(Avatar)).all() == []  # reading the defaults saves nothing

    colours = {"skin": 0xFFF5D0B0, "hair": 0xFF000000, "shirt": 0xFF123456,
               "pants": 0xFF3A506B, "shoes": 0xFFFFFFFF}
    r = client.put("/users/me/avatar", json=colours)
    assert r.status_code == 200 and r.json() == colours
    assert client.get("/users/me/avatar").json() == colours

    colours["shirt"] = 0xFF654321  # saving again updates the same row
    client.put("/users/me/avatar", json=colours)
    assert client.get("/users/me/avatar").json()["shirt"] == 0xFF654321
    assert len(db.exec(select(Avatar)).all()) == 1


def test_avatar_rejects_bad_colours(client):
    good = {"skin": 1, "hair": 1, "shirt": 1, "pants": 1, "shoes": 1}
    assert client.put("/users/me/avatar", json={**good, "hair": -1}).status_code == 422
    assert client.put("/users/me/avatar", json={**good, "hair": 0x1FFFFFFFF}).status_code == 422
    missing = dict(good)
    del missing["shoes"]
    assert client.put("/users/me/avatar", json=missing).status_code == 422


def test_avatar_is_per_user(client):
    colours = {"skin": 1, "hair": 2, "shirt": 3, "pants": 4, "shoes": 5}
    client.put("/users/me/avatar", json=colours)
    as_user("other-uid", "o@example.com")
    assert client.get("/users/me/avatar").json() != colours


def test_gender_from_avatar_screen(client, db):
    # AvatarService.saveGender sends "boy" / "girl"
    assert client.put("/users/me", json={"gender": "girl"}).json()["gender"] == "female"
    assert client.put("/users/me", json={"gender": "boy"}).json()["gender"] == "male"
    assert get_user(db).gender == "male"


# ---------- Habits ----------
def test_habit_list(client):
    r = client.get("/habits")
    assert r.status_code == 200
    assert [h["name"] for h in r.json()][:4] == ["Reading", "Walking", "Workout", "Drink Water"]
    assert {"id", "name", "points", "ai_label"} <= r.json()[0].keys()


def test_unknown_habit_is_404(client):
    assert upload(client, 9999).status_code == 404


def test_habit_without_ai_mapping_is_400(client, db):
    # "Meditation" exists in the test database but Gemini has no rule for it.
    assert upload(client, habit_id(db, "Meditation")).status_code == 400


def test_level_up_is_reported_and_saved(client, db):
    user = get_user(db)
    user.total_points = 95
    db.add(user)
    db.commit()
    body = upload(client, habit_id(db, "Reading")).json()
    assert body["total_points"] == 105
    assert body["current_level"] == 1 and body["leveled_up"] is True
    assert get_user(db).current_level == 1


# ---------- Health ----------
def test_health_reports_how_logins_are_checked(client):
    body = client.get("/health").json()
    assert body["login_check"] in ("service_account", "error") or body["login_check"].startswith("project_id:")


# ---------- Points can't be lost when two habits are verified at once ----------
ACTIVITY = {"Reading": "reading", "Walking": "walking", "Workout": "workout", "Drink Water": "drinking_water"}


def test_parallel_verifications_add_all_points(tmp_path, monkeypatch):
    import threading

    import ai_verification
    from database import get_session
    from fastapi.testclient import TestClient

    # A real file database; every request gets its own session, like the running server.
    engine = create_engine(f"sqlite:///{tmp_path / 'race.db'}", connect_args={"check_same_thread": False})
    SQLModel.metadata.create_all(engine)
    with Session(engine) as s:
        s.add(User(firebase_uid=TEST_UID, username="tester", email="t@example.com"))
        ensure_habits(s)
        habits = {h.id: h.name for h in s.exec(select(Habit)).all()}

    def own_session():
        with Session(engine) as s:
            yield s

    barrier = threading.Barrier(len(habits))
    # Each habit's photo has its own width, so the fake AI knows which habit it is.
    width = {hid: 200 + 10 * i for i, hid in enumerate(habits)}
    activity_for_width = {width[hid]: ACTIVITY[name] for hid, name in habits.items()}

    def slow_ai(jpeg):
        # Every request has already read the user's points; all wait here together.
        barrier.wait(timeout=10)
        w = Image.open(io.BytesIO(jpeg)).size[0]
        return ai_verification.Verdict(detected_activity=activity_for_width[w],
                                       evidence="activity_in_progress", confidence="high", reason="ok")

    monkeypatch.setattr(ai_verification, "analyze_photo", slow_ai)
    main.app.dependency_overrides[get_session] = own_session
    main.app.dependency_overrides[verify_token] = lambda: {"uid": TEST_UID, "email": "t@example.com"}
    client = TestClient(main.app)

    def verify(hid):
        return upload(client, hid, data=make_jpeg((width[hid], 150)))

    try:
        with ThreadPoolExecutor(len(habits)) as pool:
            results = list(pool.map(verify, habits))
    finally:
        main.app.dependency_overrides.clear()

    assert all(r.status_code == 200 for r in results), [r.text for r in results]
    with Session(engine) as s:
        assert s.exec(select(User)).one().total_points == sum(h["points"] for h in HABITS)


# ---------- Startup seeding is safe with several server processes ----------
class _SeesNothing:
    """Wraps a session so its lookups find nothing, like a second server process
    that checked for the default rows just before the first one saved them."""

    def __init__(self, session):
        self._s = session

    def exec(self, statement):
        class _Empty:
            def first(self):
                return None
        return _Empty()

    def __getattr__(self, name):
        return getattr(self._s, name)


def test_seeding_at_the_same_time_as_another_process_does_not_crash():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as s:
        ensure_rooms(s)
        ensure_habits(s)
    with Session(engine) as late:
        assert "Skipped" in ensure_rooms(_SeesNothing(late))[-1]
        assert "Skipped" in ensure_habits(_SeesNothing(late))[-1]
    with Session(engine) as s:
        assert len(s.exec(select(Room)).all()) == len(ROOMS)
        assert len(s.exec(select(Habit)).all()) == len(HABITS)


# ---------- Habit categories (used by "My habits" and group habits on Home) ----------
def test_today_habits_include_category(client):
    habits = {h["name"]: h for h in client.get("/habits/today").json()}
    assert habits["Reading"]["category"] == "Study"
    assert {habits[n]["category"] for n in ("Walking", "Workout", "Drink Water")} == {"Health"}
    # every field the app already read is still there
    assert {"id", "name", "points", "ai_label", "completed_today", "streak"} <= habits["Reading"].keys()


def test_group_categories_match_habit_categories(client, db):
    # A group needs every habit with its category, so both must use the same two values.
    ensure_rooms(db)
    group_categories = {g["category"] for g in client.get("/groups/discover").json()}
    habit_categories = {h["category"] for h in client.get("/habits/today").json()}
    assert group_categories == {"Study", "Health"}
    assert habit_categories <= {"Study", "Health"}
