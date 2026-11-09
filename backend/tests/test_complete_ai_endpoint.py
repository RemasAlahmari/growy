"""End-to-end tests for POST /habits/{habit_id}/complete/ai (Gemini is mocked)."""
from fastapi.testclient import TestClient

import ai_verification
import main
from conftest import REAL_ANALYZE_PHOTO, get_user, habit_id, logs, make_jpeg, upload
from models import HabitLog

FLUTTER_KEYS = {"verification_status", "predicted_label", "confidence", "points_earned"}


# ---------- passing photos ----------
def test_walking_photo_is_verified_and_awards_points(client, db, fake_ai):
    calls = fake_ai("walking", "activity_in_progress", "high", "Feet walking on a sidewalk.")
    r = upload(client, habit_id(db, "Walking"))

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["verification_status"] == "verified"
    assert body["predicted_label"] == "walking"
    assert body["expected_activity"] == "walking"
    assert body["points_earned"] == 10
    assert body["total_points"] == 10
    assert body["current_level"] == 0
    assert body["leveled_up"] is False
    assert body["attempts_remaining"] == 3
    assert body["reason"] == "Feet walking on a sidewalk."
    assert body["confidence_level"] == "high"
    assert len(calls) == 1

    user = get_user(db)
    assert user.total_points == 10 and user.current_level == 0
    [log] = logs(db)
    assert log.verification_status == "verified"
    assert log.points_earned == 10
    assert log.predicted_label == "walking"
    assert log.ai_reason == "high, activity_in_progress: Feet walking on a sidewalk."


def test_each_habit_maps_to_its_activity(client, db, fake_ai):
    for name, activity, pts in [("Reading", "reading", 10), ("Workout", "workout", 10),
                                ("Drink Water", "drinking_water", 5)]:
        fake_ai(activity, "activity_in_progress", "medium")
        r = upload(client, habit_id(db, name))
        assert r.status_code == 200, r.text
        assert r.json()["verification_status"] == "verified", name
        assert r.json()["points_earned"] == pts
    assert get_user(db).total_points == 25


def test_level_is_recalculated(client, db, fake_ai):
    user = get_user(db)
    user.total_points = 495
    db.add(user); db.commit()
    fake_ai("walking")
    r = upload(client, habit_id(db, "Walking"))
    assert r.json()["total_points"] == 505
    assert r.json()["current_level"] == 2
    assert r.json()["leveled_up"] is True
    assert get_user(db).current_level == 2


# ---------- rejected photos ----------
def _assert_rejected(r, db):
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["verification_status"] == "rejected"
    assert body["points_earned"] == 0
    assert get_user(db).total_points == 0
    [log] = logs(db)
    assert log.verification_status == "rejected" and log.points_earned == 0


def test_object_only_is_rejected(client, db, fake_ai):
    fake_ai("reading", "object_only", "high", "A book lying on a bed, nobody is reading it.")
    r = upload(client, habit_id(db, "Reading"))
    _assert_rejected(r, db)
    assert "nobody" in r.json()["reason"]
    assert r.json()["attempts_remaining"] == 2


def test_wrong_activity_is_rejected(client, db, fake_ai):
    fake_ai("workout", "activity_in_progress", "high")
    _assert_rejected(upload(client, habit_id(db, "Walking")), db)


def test_low_confidence_is_rejected(client, db, fake_ai):
    fake_ai("walking", "activity_in_progress", "low")
    _assert_rejected(upload(client, habit_id(db, "Walking")), db)


def test_unrelated_and_unclear_are_rejected(client, db, fake_ai):
    fake_ai("unrelated", "unclear", "high", "A cat on a sofa.")
    r1 = upload(client, habit_id(db, "Reading"))
    assert r1.json()["verification_status"] == "rejected"
    fake_ai("unclear", "unclear", "low", "The photo is too dark.")
    r2 = upload(client, habit_id(db, "Reading"))
    assert r2.json()["verification_status"] == "rejected"
    assert get_user(db).total_points == 0


def test_rejected_photo_can_be_retried(client, db, fake_ai):
    hid = habit_id(db, "Walking")
    fake_ai("walking", "object_only", "high")
    assert upload(client, hid).json()["verification_status"] == "rejected"
    fake_ai("walking", "activity_in_progress", "high")
    assert upload(client, hid).json()["verification_status"] == "verified"


# ---------- 409 duplicate ----------
def test_second_completion_same_day_is_409_and_skips_gemini(client, db, fake_ai):
    hid = habit_id(db, "Walking")
    calls = fake_ai("walking")
    assert upload(client, hid).status_code == 200
    r = upload(client, hid)
    assert r.status_code == 409
    assert len(calls) == 1          # no wasted Gemini call
    assert get_user(db).total_points == 10


def test_other_users_completion_does_not_block(client, db, fake_ai):
    hid = habit_id(db, "Walking")
    other = get_user(db, "other-uid")
    db.add(HabitLog(habit_id=hid, user_id=other.id, points_earned=10, verification_status="verified"))
    db.commit()
    fake_ai("walking")
    assert upload(client, hid).status_code == 200


# ---------- 413 / 415 ----------
def test_too_large_is_413(client, db, fake_ai):
    calls = fake_ai("walking")
    r = upload(client, habit_id(db, "Walking"), data=b"\xff" * (5 * 1024 * 1024 + 1))
    assert r.status_code == 413
    assert calls == [] and logs(db) == []


def test_wrong_content_type_is_415(client, db, fake_ai):
    calls = fake_ai("walking")
    r = upload(client, habit_id(db, "Walking"), data=b"hello", content_type="text/plain", filename="a.txt")
    assert r.status_code == 415
    assert calls == []


def test_corrupt_image_is_415(client, db, fake_ai):
    calls = fake_ai("walking")
    r = upload(client, habit_id(db, "Walking"), data=b"this is not really a jpeg")
    assert r.status_code == 415
    assert calls == [] and logs(db) == []


def test_png_is_accepted(client, db, fake_ai):
    import io
    from PIL import Image
    buf = io.BytesIO(); Image.new("RGBA", (300, 300)).save(buf, "PNG")
    fake_ai("walking")
    r = upload(client, habit_id(db, "Walking"), data=buf.getvalue(), content_type="image/png", filename="p.png")
    assert r.status_code == 200, r.text


# ---------- 503: AI unavailable ----------
def test_gemini_failure_is_503_and_saves_nothing(client, db, fake_ai):
    fake_ai(error=ai_verification.AIServiceError("rate limited"))
    r = upload(client, habit_id(db, "Walking"))
    assert r.status_code == 503
    assert logs(db) == []
    assert get_user(db).total_points == 0


def test_missing_api_key_is_503(client, db, monkeypatch):
    monkeypatch.setattr(ai_verification, "analyze_photo", REAL_ANALYZE_PHOTO)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setattr(ai_verification, "_client", None)
    r = upload(client, habit_id(db, "Walking"))
    assert r.status_code == 503
    assert logs(db) == []


# ---------- 404 / 400 ----------
def test_unknown_habit_is_404(client, db, fake_ai):
    fake_ai("walking")
    assert upload(client, 9999).status_code == 404


def test_habit_without_ai_mapping_is_400(client, db, fake_ai):
    calls = fake_ai("walking")
    assert upload(client, habit_id(db, "Meditation")).status_code == 400
    assert calls == []


# ---------- Flutter contract ----------
def test_response_matches_what_flutter_parses(client, db, fake_ai):
    fake_ai("walking")
    body = upload(client, habit_id(db, "Walking")).json()
    assert FLUTTER_KEYS <= body.keys()
    assert isinstance(body["verification_status"], str)
    assert isinstance(body["predicted_label"], str)
    assert body["confidence"] is None or isinstance(body["confidence"], (int, float))
    assert isinstance(body["points_earned"], int)
    assert isinstance(body["reason"], str)


def test_home_endpoints_see_the_verified_log(client, db, fake_ai):
    fake_ai("walking")
    upload(client, habit_id(db, "Walking"))
    me = client.get("/users/me").json()
    assert me["total_points"] == 10 and me["today_points"] == 10
    today = {h["name"]: h for h in client.get("/habits/today").json()}
    assert today["Walking"]["completed_today"] is True
    assert today["Walking"]["streak"] == 1
    assert today["Reading"]["completed_today"] is False


# ---------- auth ----------
def test_bad_authorization_header_is_401(engine):
    main.app.dependency_overrides.clear()
    r = TestClient(main.app).post(
        "/habits/1/complete/ai",
        headers={"Authorization": "Token abc"},
        files={"file": ("p.jpg", make_jpeg(), "image/jpeg")},
    )
    assert r.status_code == 401


def test_route_is_registered():
    routes = {(r.path, tuple(sorted(r.methods))) for r in main.app.routes if hasattr(r, "methods")}
    assert ("/habits/{habit_id}/complete/ai", ("POST",)) in routes


def test_health_reports_ai_config_without_leaking_key(client, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "secret-test-key")
    body = client.get("/health").json()
    assert body["ai_configured"] is True
    assert "secret-test-key" not in str(body)


def test_ai_outage_does_not_use_up_an_attempt(client, db, fake_ai):
    hid = habit_id(db, "Walking")
    for _ in range(3):
        fake_ai(error=ai_verification.AIServiceError("down"))
        assert upload(client, hid).status_code == 503
    fake_ai("walking")
    r = upload(client, hid)
    assert r.status_code == 200
    assert r.json()["verification_status"] == "verified"


def test_three_rejections_then_429(client, db, fake_ai):
    hid = habit_id(db, "Walking")
    fake_ai("walking", "object_only", "high")
    remaining = [upload(client, hid).json()["attempts_remaining"] for _ in range(3)]
    assert remaining == [2, 1, 0]
    r = upload(client, hid)
    assert r.status_code == 429
    assert len(logs(db)) == 3
