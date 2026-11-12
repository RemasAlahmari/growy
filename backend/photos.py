"""Photos stored in the database (free; no paid storage service).

- Verified habit photos: a 640 px copy is saved, shown in the Habits history.
- Profile photos: POST/DELETE /users/me/photo (in main.py) use these helpers.

Each photo gets a long random token and is served at GET /photos/{token}.jpg.
The app's image widgets can't send the login token, so the address itself is the
secret: it can't be guessed, but anyone who has it can open the photo.
"""
import io
import secrets
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from PIL import Image
from sqlmodel import Session, select

from database import get_session
from models import Photo

router = APIRouter(tags=["photos"])

THUMB_SIDE_PX = 640
THUMB_QUALITY = 75


def make_thumbnail(jpeg_bytes: bytes, side: int = THUMB_SIDE_PX) -> bytes:
    """A smaller JPEG copy (the input is already a clean JPEG from prepare_image)."""
    with Image.open(io.BytesIO(jpeg_bytes)) as img:
        img = img.convert("RGB")
        img.thumbnail((side, side))
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=THUMB_QUALITY)
        return out.getvalue()


def photo_url(token: Optional[str]) -> Optional[str]:
    # Relative path; the app adds its backend address in front.
    return f"/photos/{token}.jpg" if token else None


def save_photo(session: Session, user_id: int, kind: str, jpeg_bytes: bytes,
               habit_log_id: Optional[int] = None) -> str:
    """Adds a photo to the session (the caller commits). Returns its token."""
    token = secrets.token_urlsafe(24)
    session.add(Photo(
        token=token,
        user_id=user_id,
        kind=kind,
        habit_log_id=habit_log_id,
        data=make_thumbnail(jpeg_bytes),
    ))
    return token


def profile_photo(session: Session, user_id: int) -> Optional[Photo]:
    return session.exec(
        select(Photo).where(Photo.user_id == user_id, Photo.kind == "profile")
    ).first()


def tokens_for_logs(session: Session, log_ids: list[int]) -> dict[int, str]:
    if not log_ids:
        return {}
    rows = session.exec(
        select(Photo.habit_log_id, Photo.token).where(Photo.habit_log_id.in_(log_ids))
    ).all()
    return {log_id: token for log_id, token in rows}


@router.get("/photos/{token}.jpg")
def get_photo(token: str, session: Session = Depends(get_session)):
    photo = session.exec(select(Photo).where(Photo.token == token)).first()
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found.")
    # The token changes whenever the photo changes, so it can be cached for long.
    return Response(
        content=photo.data,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=86400"},
    )
