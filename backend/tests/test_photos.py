"""Profile photos and saved verification photos."""
import io

from PIL import Image
from sqlmodel import select

from conftest import habit_id, make_jpeg, upload
from models import Photo


def put_photo(client, data=None, content_type="image/jpeg"):
    data = make_jpeg((1200, 900)) if data is None else data
    return client.post("/users/me/photo", files={"file": ("me.jpg", data, content_type)})


def test_profile_photo_upload_replace_and_delete(client, db):
    r = put_photo(client)
    assert r.status_code == 200, r.text
    url1 = r.json()["profile_image_url"]
    assert url1.startswith("/photos/")
    img = Image.open(io.BytesIO(client.get(url1).content))
    assert max(img.size) <= 640  # stored as a small copy

    url2 = put_photo(client).json()["profile_image_url"]
    assert url2 != url1                              # new address after a change
    assert client.get(url1).status_code == 404       # old one is gone
    assert len(db.exec(select(Photo).where(Photo.kind == "profile")).all()) == 1

    r = client.delete("/users/me/photo")
    assert r.json()["profile_image_url"] is None
    assert client.get(url2).status_code == 404
    assert client.get("/users/me").json()["profile_image_url"] is None


def test_profile_photo_validation(client):
    assert put_photo(client, b"not an image").status_code == 415
    assert put_photo(client, b"x", content_type="text/plain").status_code == 415
    assert put_photo(client, b"\xff" * (5 * 1024 * 1024 + 1)).status_code == 413


def test_verified_photo_is_saved_rejected_is_not(client, db, fake_ai):
    upload(client, habit_id(db, "Reading"))                      # default fake AI: verified
    fake_ai("walking", "object_only", "high")
    upload(client, habit_id(db, "Walking"))                      # rejected
    saved = db.exec(select(Photo).where(Photo.kind == "verification")).all()
    assert len(saved) == 1
    assert saved[0].habit_log_id is not None


def test_unknown_photo_is_404(client):
    assert client.get("/photos/does-not-exist.jpg").status_code == 404
