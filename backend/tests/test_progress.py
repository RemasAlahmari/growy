def upload_photo(client, habit_id=1):
    return client.post(
        f"/habits/{habit_id}/complete/ai",
        files={"file": ("photo.png", b"fake image bytes", "image/png")},
    )


def test_progress_for_new_user_is_all_zeros(client):
    data = client.get("/progress").json()

    assert data["total_points"] == 0
    assert data["total_habits_completed"] == 0
    assert len(data["last_7_days"]) == 7
    assert all(day["points"] == 0 for day in data["last_7_days"])


def test_progress_counts_today_completion(client):
    upload_photo(client)

    data = client.get("/progress").json()
    today = data["last_7_days"][-1]  # the last day in the list is today

    assert data["total_points"] == 10
    assert data["total_habits_completed"] == 1
    assert today["points"] == 10
    assert today["habits_completed"] == 1