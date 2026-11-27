"""IT-NFR4-03: photo addresses can't be guessed.

The app's image widgets can't send the login token, so the address of a photo
(/photos/<token>.jpg) is the secret. The token must be long and random.
"""
import re

from sqlmodel import select

from conftest import habit_id, make_jpeg, upload
from models import Photo

MIN_TOKEN_LENGTH = 32
PHOTO_URL = re.compile(r"^/photos/([A-Za-z0-9_-]+)\.jpg$")


def token_from(url):
    match = PHOTO_URL.match(url or "")
    assert match, f"Not a photo address: {url!r}"
    return match.group(1)


def test_photo_token_in_image_url_is_long_and_random(client, db, fake_ai):
    # 1. A verified habit photo is saved with a token
    r = upload(client, habit_id(db, "Reading"))
    assert r.status_code == 200, r.text
    [verification] = db.exec(select(Photo).where(Photo.kind == "verification")).all()
    verification_token = verification.token

    # 2. A profile photo: its token is inside profile_image_url
    r = client.post("/users/me/photo",
                    files={"file": ("me.jpg", make_jpeg((800, 600)), "image/jpeg")})
    assert r.status_code == 200, r.text
    profile_token = token_from(r.json()["profile_image_url"])

    # Both tokens are long enough, and they are different
    for token in (verification_token, profile_token):
        assert len(token) >= MIN_TOKEN_LENGTH, f"Token too short ({len(token)}): {token}"
    assert verification_token != profile_token

    # The address built from the token opens the photo
    assert client.get(f"/photos/{verification_token}.jpg").status_code == 200