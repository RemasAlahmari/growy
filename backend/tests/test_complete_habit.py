from sqlmodel import select
from models import User, HabitLog, today_ksa


def upload_photo(client, habit_id=1, content_type="image/png"):
    # Sends a fake photo, like the Flutter app does (field name "file")
    return client.post(
        f"/habits/{habit_id}/complete/ai",
        files={"file": ("photo.png", b"fake image bytes", content_type)},
    )


def add_rejected_attempts(session, count):
    # Simulates earlier rejected photos today for the test user (id 1) on habit 1
    for _ in range(count):
        session.add(HabitLog(
            habit_id=1,
            user_id=1,
            completed_date=today_ksa(),
            points_earned=0,
            verification_status="rejected",
        ))
    session.commit()


def test_first_completion_succeeds_and_adds_points(client):
    response = upload_photo(client)

    assert response.status_code == 200
    data = response.json()
    assert data["verification_status"] == "verified"
    assert data["points_earned"] == 10
    assert data["total_points"] == 10
    assert data["current_level"] == 0
    assert data["leveled_up"] is False


def test_second_completion_same_day_is_blocked(client):
    upload_photo(client)
    response = upload_photo(client)

    assert response.status_code == 409

    # Points were added only once
    me = client.get("/users/me").json()
    assert me["total_points"] == 10


def test_blocked_after_three_rejected_attempts(client, session):
    add_rejected_attempts(session, 3)

    response = upload_photo(client)

    assert response.status_code == 429


def test_two_rejected_attempts_still_allow_completion(client, session):
    add_rejected_attempts(session, 2)

    response = upload_photo(client)

    assert response.status_code == 200
    assert response.json()["attempts_remaining"] == 1


def test_non_image_file_is_rejected(client):
    response = upload_photo(client, content_type="application/pdf")

    assert response.status_code == 415


def test_unknown_habit_returns_404(client):
    response = upload_photo(client, habit_id=999)

    assert response.status_code == 404


def test_reaching_100_points_levels_up(client, session):
    user = session.exec(select(User)).first()
    user.total_points = 95
    session.add(user)
    session.commit()

    response = upload_photo(client)

    data = response.json()
    assert data["total_points"] == 105
    assert data["current_level"] == 1
    assert data["leveled_up"] is True