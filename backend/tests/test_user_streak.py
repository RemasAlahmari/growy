from datetime import timedelta
from models import HabitLog, today_ksa


def add_verified_log(session, days_ago, habit_id=1):
    # Simulates a verified completion some days ago for the test user (id 1)
    session.add(HabitLog(
        habit_id=habit_id,
        user_id=1,
        completed_date=today_ksa() - timedelta(days=days_ago),
        points_earned=10,
        verification_status="verified",
    ))
    session.commit()


def test_new_user_has_zero_streak(client):
    assert client.get("/users/me").json()["streak_days"] == 0


def test_three_days_in_a_row_gives_streak_3(client, session):
    add_verified_log(session, days_ago=0)
    add_verified_log(session, days_ago=1)
    add_verified_log(session, days_ago=2)

    assert client.get("/users/me").json()["streak_days"] == 3
    assert client.get("/progress").json()["streak_days"] == 3


def test_two_habits_same_day_count_as_one_day(client, session):
    add_verified_log(session, days_ago=0, habit_id=1)
    add_verified_log(session, days_ago=0, habit_id=1)

    assert client.get("/users/me").json()["streak_days"] == 1