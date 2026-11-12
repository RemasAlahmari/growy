"""Groups: discover, join, join by code, dismiss/undo, leave, leaderboard, goals."""
from datetime import datetime, timedelta, timezone

from sqlmodel import select

import main
from auth import verify_token
from conftest import TEST_UID, get_user, habit_id, upload
from models import HabitLog, Room, RoomMember
from seed_groups import ROOMS, ensure_rooms


def seed(db):
    ensure_rooms(db)
    return {r.name: r.id for r in db.exec(select(Room)).all()}


def as_other():
    main.app.dependency_overrides[verify_token] = lambda: {"uid": "other-uid", "email": "o@example.com"}


def as_tester():
    main.app.dependency_overrides[verify_token] = lambda: {"uid": TEST_UID, "email": "t@example.com"}


GROUP_KEYS = {"id", "room_name", "description", "category", "icon_key", "room_code",
              "member_count", "is_joined", "user_rank", "user_points", "goal"}


def test_seed_adds_default_groups_once(db):
    ensure_rooms(db)
    report = ensure_rooms(db)
    assert all(line.startswith("Unchanged") for line in report)
    assert len(db.exec(select(Room)).all()) == len(ROOMS)


def test_discover_lists_all_groups_for_new_user(client, db):
    seed(db)
    groups = client.get("/groups/discover").json()
    assert len(groups) == len(ROOMS)
    g = groups[0]
    assert GROUP_KEYS <= g.keys()
    assert g["is_joined"] is False
    assert g["room_code"] is None  # invite codes are only shown to members
    assert client.get("/groups/mine").json() == []


def test_join_moves_group_to_mine(client, db):
    ids = seed(db)
    r = client.post(f"/groups/{ids['Study Together']}/join")
    assert r.status_code == 200, r.text
    g = r.json()
    assert g["is_joined"] is True
    assert g["room_code"] == "STUDY24"
    assert g["member_count"] == 1
    assert g["user_rank"] == 1 and g["user_points"] == 0
    assert [x["room_name"] for x in client.get("/groups/mine").json()] == ["Study Together"]
    assert all(x["room_name"] != "Study Together" for x in client.get("/groups/discover").json())


def test_join_twice_is_safe(client, db):
    ids = seed(db)
    client.post(f"/groups/{ids['Study Together']}/join")
    r = client.post(f"/groups/{ids['Study Together']}/join")
    assert r.status_code == 200
    assert r.json()["member_count"] == 1


def test_join_by_code_is_case_insensitive(client, db):
    seed(db)
    r = client.post("/groups/join", json={"room_code": "  read20 "})
    assert r.status_code == 200, r.text
    assert r.json()["room_name"] == "Book Club Readers"


def test_join_by_unknown_code_is_404(client, db):
    seed(db)
    r = client.post("/groups/join", json={"room_code": "NOPE99"})
    assert r.status_code == 404
    assert client.post("/groups/join", json={"room_code": "   "}).status_code == 422


def test_join_unknown_group_is_404(client, db):
    seed(db)
    assert client.post("/groups/9999/join").status_code == 404


def test_dismiss_and_undo(client, db):
    ids = seed(db)
    gid = ids["Morning Runners"]
    assert client.post(f"/groups/{gid}/dismiss").status_code == 200
    assert all(g["id"] != gid for g in client.get("/groups/discover").json())
    assert client.post(f"/groups/{gid}/dismiss").status_code == 200  # twice is fine
    assert client.delete(f"/groups/{gid}/dismiss").status_code == 200
    assert any(g["id"] == gid for g in client.get("/groups/discover").json())


def test_joining_a_dismissed_group_by_code_works(client, db):
    ids = seed(db)
    client.post(f"/groups/{ids['Morning Runners']}/dismiss")
    r = client.post("/groups/join", json={"room_code": "GROWY1"})
    assert r.json()["is_joined"] is True


def test_leave_group(client, db):
    ids = seed(db)
    gid = ids["Hydration Heroes"]
    client.post(f"/groups/{gid}/join")
    assert client.delete(f"/groups/{gid}/membership").status_code == 200
    assert client.get("/groups/mine").json() == []
    assert any(g["id"] == gid for g in client.get("/groups/discover").json())
    assert client.delete(f"/groups/{gid}/membership").status_code == 200  # already left


def test_leaderboard_needs_membership(client, db):
    ids = seed(db)
    assert client.get(f"/groups/{ids['Study Together']}/leaderboard").status_code == 403


def test_points_count_only_after_joining_and_rank_members(client, db):
    ids = seed(db)
    gid = ids["Study Together"]
    tester = get_user(db)
    other = get_user(db, "other-uid")

    # XP earned BEFORE joining doesn't count in the group
    db.add(HabitLog(habit_id=habit_id(db, "Walking"), user_id=tester.id, points_earned=10,
                    verification_status="verified",
                    completed_at=datetime.now(timezone.utc) - timedelta(days=2)))
    db.commit()

    client.post(f"/groups/{gid}/join")            # tester joins
    as_other()
    client.post(f"/groups/{gid}/join")            # other joins
    as_tester()

    upload(client, habit_id(db, "Reading"))       # tester verifies after joining: +10
    board = client.get(f"/groups/{gid}/leaderboard").json()
    assert [(e["display_name"], e["points"], e["rank"], e["is_me"]) for e in board] == [
        ("tester", 10, 1, True),
        ("other", 0, 2, False),
    ]
    mine = client.get("/groups/mine").json()[0]
    assert mine["user_rank"] == 1 and mine["user_points"] == 10 and mine["member_count"] == 2

    as_other()
    assert client.get(f"/groups/{gid}/leaderboard").json()[1]["is_me"] is True
    assert other.id == client.get(f"/groups/{gid}/leaderboard").json()[1]["user_id"]


def test_ties_go_to_who_joined_first(client, db):
    ids = seed(db)
    gid = ids["Study Together"]
    client.post(f"/groups/{gid}/join")
    as_other()
    client.post(f"/groups/{gid}/join")
    board = client.get(f"/groups/{gid}/leaderboard").json()
    assert [e["display_name"] for e in board] == ["tester", "other"]


def test_group_goal_counts_this_months_xp(client, db):
    ids = seed(db)
    gid = ids["Study Together"]
    client.post(f"/groups/{gid}/join")
    upload(client, habit_id(db, "Reading"))
    goal = client.get("/groups/mine").json()[0]["goal"]
    assert goal["target"] == 900
    assert goal["current"] == 10
    assert goal["title"]
    datetime.fromisoformat(goal["end_date"])  # a valid date
    no_goal = next(g for g in client.get("/groups/discover").json() if g["room_name"] == "Hydration Heroes")
    assert no_goal["goal"] is None


def test_groups_joined_on_profile(client, db):
    ids = seed(db)
    client.post(f"/groups/{ids['Study Together']}/join")
    client.post(f"/groups/{ids['Book Club Readers']}/join")
    assert client.get("/users/me").json()["groups_joined"] == 2


def test_discover_sorts_bigger_groups_first(client, db):
    ids = seed(db)
    as_other()
    client.post(f"/groups/{ids['Exam Prep Circle']}/join")
    as_tester()
    assert client.get("/groups/discover").json()[0]["room_name"] == "Exam Prep Circle"


def test_unknown_user_gets_404(client, db):
    seed(db)
    main.app.dependency_overrides[verify_token] = lambda: {"uid": "nobody", "email": "n@example.com"}
    assert client.get("/groups/mine").status_code == 404


def test_membership_rows_are_unique(db):
    ids = seed(db)
    user = get_user(db)
    db.add(RoomMember(room_id=ids["Study Together"], user_id=user.id))
    db.commit()
    db.add(RoomMember(room_id=ids["Study Together"], user_id=user.id))
    try:
        db.commit()
        raised = False
    except Exception:
        db.rollback()
        raised = True
    assert raised
