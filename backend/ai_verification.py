"""
AI photo verification with the Gemini API (vision-language model).

How it works:
  1. The photo is cleaned up (rotation fixed, resized, re-encoded as JPEG).
  2. Gemini classifies WHAT ACTIVITY the photo shows. It is NOT told which habit
     the user claimed, so it can't be "talked into" agreeing.
  3. Gemini must answer in a fixed JSON shape (the Verdict model below).
  4. The backend compares the answer with the habit using `passes()`.

Configuration (in backend/.env):
  GEMINI_API_KEY   your key from https://aistudio.google.com/apikey
  GEMINI_MODEL     optional, defaults to DEFAULT_MODEL below
"""
import io
import logging
import os
from enum import Enum
from typing import Optional

from PIL import Image, ImageOps
from pydantic import BaseModel, Field, ValidationError

logger = logging.getLogger("growy.ai")

DEFAULT_MODEL = "gemini-3.5-flash-lite"
REQUEST_TIMEOUT_MS = 30_000   # Flutter waits up to 60 s, so fail well before that
MAX_SIDE_PX = 1024            # same size the Flutter app resizes to
MAX_PIXELS = 40_000_000       # refuse absurdly large images ("decompression bombs")


# ------------------------------------------------------------------
# Structured answer that Gemini must return
# ------------------------------------------------------------------
class Activity(str, Enum):
    reading = "reading"
    walking = "walking"
    workout = "workout"
    drinking_water = "drinking_water"
    unrelated = "unrelated"
    unclear = "unclear"


class Evidence(str, Enum):
    activity_in_progress = "activity_in_progress"
    object_only = "object_only"
    unclear = "unclear"


class Confidence(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"


class Verdict(BaseModel):
    detected_activity: Activity
    evidence: Evidence
    confidence: Confidence
    reason: str = Field(description="One short sentence explaining the decision.")


SYSTEM_PROMPT = """You verify photos for a habit-tracking app. A user submits a photo as proof that they did a habit. Judge the ACTIVITY, not just the objects in the photo.

Classify the photo into exactly ONE detected_activity:
- reading: a person reading a book, for example their hands holding an open book, or a book open on their lap while they read.
- walking: a person walking outdoors, for example a first-person view of their own feet or legs on a sidewalk, street, path or park.
- workout: a person exercising, for example lifting weights, using gym equipment, or doing exercises on a mat.
- drinking_water: a person drinking water, or holding a glass or bottle of plain or infused water in their hand.
- unrelated: the photo does not show any of the activities above.
- unclear: the photo is too dark, blurry, cropped or ambiguous to judge.

Walking vs workout: walking on a street, sidewalk or path is "walking" even if the person wears sports clothes or sneakers. "workout" needs exercise equipment being used or an exercise movement.

evidence:
- activity_in_progress: a person, or their own hands/feet/legs seen from a first-person view, is clearly doing the activity.
- object_only: the related object is visible but nobody is doing the activity, for example a book lying on a bed, dumbbells on the floor, a glass standing on a table, an empty gym.
- unclear: you cannot tell.

An object by itself is NOT proof of the activity. If you are not sure, choose unclear or unrelated rather than guessing.

confidence: high, medium or low.
reason: one short, friendly sentence the user will see, explaining what you saw."""


# ------------------------------------------------------------------
# Habit -> expected activity
# ------------------------------------------------------------------
# Matched on the habit's name (case-insensitive). If you add a new habit,
# add it here AND describe it in SYSTEM_PROMPT above.
HABIT_ACTIVITY = {
    "reading": Activity.reading,
    "walking": Activity.walking,
    "workout": Activity.workout,
    "drink water": Activity.drinking_water,
}


def expected_activity_for(habit_name: str) -> Optional[Activity]:
    return HABIT_ACTIVITY.get(habit_name.strip().lower())


# ------------------------------------------------------------------
# Errors the endpoint turns into HTTP status codes
# ------------------------------------------------------------------
class InvalidImageError(Exception):
    """The upload is not a readable image -> HTTP 415."""


class AIServiceError(Exception):
    """Gemini could not be reached / answered badly -> HTTP 503, nothing saved."""


# ------------------------------------------------------------------
# Image preparation
# ------------------------------------------------------------------
def prepare_image(data: bytes) -> bytes:
    """Validates the upload and returns a clean JPEG (rotation fixed, max 1024 px)."""
    if not data:
        raise InvalidImageError("Empty file")
    try:
        with Image.open(io.BytesIO(data)) as probe:
            width, height = probe.size
            if width * height > MAX_PIXELS:
                raise InvalidImageError("Image dimensions are too large")
            probe.verify()  # checks the file isn't truncated/corrupt

        # verify() leaves the image unusable, so open it again to process it
        with Image.open(io.BytesIO(data)) as img:
            img = ImageOps.exif_transpose(img)  # phone photos store rotation separately
            img = img.convert("RGB")
            img.thumbnail((MAX_SIDE_PX, MAX_SIDE_PX))
            out = io.BytesIO()
            img.save(out, format="JPEG", quality=85)
            return out.getvalue()
    except InvalidImageError:
        raise
    except Exception as e:  # PIL raises many different error types
        raise InvalidImageError("Not a readable image") from e


# ------------------------------------------------------------------
# Decision rule
# ------------------------------------------------------------------
def passes(verdict: Verdict, expected: Activity) -> bool:
    return (
        verdict.detected_activity == expected
        and verdict.evidence == Evidence.activity_in_progress
        and verdict.confidence != Confidence.low
    )


# ------------------------------------------------------------------
# Gemini call
# ------------------------------------------------------------------
_client = None


def model_name() -> str:
    return os.getenv("GEMINI_MODEL", "").strip() or DEFAULT_MODEL


def is_configured() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip())


def _get_client():
    global _client
    if _client is None:
        api_key = os.getenv("GEMINI_API_KEY", "").strip()
        if not api_key:
            raise AIServiceError("GEMINI_API_KEY is not set in backend/.env")
        from google import genai
        from google.genai import types

        _client = genai.Client(
            api_key=api_key,
            http_options=types.HttpOptions(timeout=REQUEST_TIMEOUT_MS),
        )
    return _client


def _blocked_verdict() -> Verdict:
    return Verdict(
        detected_activity=Activity.unclear,
        evidence=Evidence.unclear,
        confidence=Confidence.low,
        reason="This photo couldn't be analysed. Please try a different photo.",
    )


def analyze_photo(jpeg_bytes: bytes) -> Verdict:
    """Asks Gemini what activity the photo shows. Raises AIServiceError on any API problem."""
    from google.genai import errors, types

    client = _get_client()
    try:
        response = client.models.generate_content(
            model=model_name(),
            contents=[
                types.Part.from_bytes(data=jpeg_bytes, mime_type="image/jpeg"),
                "Classify this habit photo.",
            ],
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=Verdict,
            ),
        )
    except errors.APIError as e:
        logger.warning("Gemini API error %s: %s", getattr(e, "code", "?"), e)
        raise AIServiceError(f"Gemini API error {getattr(e, 'code', '')}") from e
    except Exception as e:  # timeouts, network problems
        logger.warning("Gemini request failed: %r", e)
        raise AIServiceError("Could not reach Gemini") from e

    # Gemini refused to look at the image (safety filter) -> treat as a rejected photo
    feedback = getattr(response, "prompt_feedback", None)
    if feedback is not None and getattr(feedback, "block_reason", None):
        logger.info("Gemini blocked the image: %s", feedback.block_reason)
        return _blocked_verdict()

    parsed = getattr(response, "parsed", None)
    if isinstance(parsed, Verdict):
        return parsed
    try:
        return Verdict.model_validate_json(response.text or "")
    except (ValidationError, ValueError, TypeError) as e:
        logger.warning("Gemini returned an unexpected answer: %r", getattr(response, "text", None))
        raise AIServiceError("Gemini returned an unexpected answer") from e
