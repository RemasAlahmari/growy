"""Unit tests for ai_verification.py (no network, no database)."""
import io
import json

import pytest
from PIL import Image

import ai_verification as ai
from leveling import level_for_points


def V(activity, evidence="activity_in_progress", confidence="high", reason="r"):
    return ai.Verdict(detected_activity=activity, evidence=evidence, confidence=confidence, reason=reason)


# ---------- decision rule ----------
@pytest.mark.parametrize("verdict, expected, result", [
    (V("walking"), ai.Activity.walking, True),
    (V("walking", confidence="medium"), ai.Activity.walking, True),
    (V("walking", confidence="low"), ai.Activity.walking, False),
    (V("walking", evidence="object_only"), ai.Activity.walking, False),
    (V("walking", evidence="unclear"), ai.Activity.walking, False),
    (V("workout"), ai.Activity.walking, False),
    (V("unrelated"), ai.Activity.reading, False),
    (V("unclear"), ai.Activity.reading, False),
])
def test_passes(verdict, expected, result):
    assert ai.passes(verdict, expected) is result


def test_expected_activity_for_habit_names():
    assert ai.expected_activity_for("Reading") == ai.Activity.reading
    assert ai.expected_activity_for(" walking ") == ai.Activity.walking
    assert ai.expected_activity_for("WORKOUT") == ai.Activity.workout
    assert ai.expected_activity_for("Drink Water") == ai.Activity.drinking_water
    assert ai.expected_activity_for("Meditation") is None


# ---------- image preparation ----------
def _img_bytes(size, fmt="JPEG", mode="RGB", exif_orientation=None):
    img = Image.new(mode, size, (200, 100, 50) if mode == "RGB" else None)
    buf = io.BytesIO()
    if exif_orientation:
        exif = Image.Exif(); exif[0x0112] = exif_orientation
        img.save(buf, fmt, exif=exif.tobytes())
    else:
        img.save(buf, fmt)
    return buf.getvalue()


def test_large_image_is_resized_to_jpeg():
    out = ai.prepare_image(_img_bytes((3000, 2000)))
    img = Image.open(io.BytesIO(out))
    assert img.format == "JPEG" and max(img.size) == 1024


def test_png_with_transparency_becomes_rgb_jpeg():
    out = ai.prepare_image(_img_bytes((400, 400), fmt="PNG", mode="RGBA"))
    img = Image.open(io.BytesIO(out))
    assert img.format == "JPEG" and img.mode == "RGB"


def test_phone_rotation_is_applied():
    # Orientation 6 = "rotate 90°": a 400x300 sensor image should come out 300x400
    out = ai.prepare_image(_img_bytes((400, 300), exif_orientation=6))
    assert Image.open(io.BytesIO(out)).size == (300, 400)


@pytest.mark.parametrize("data", [b"", b"not an image", _img_bytes((500, 500))[:200]])
def test_bad_images_raise(data):
    with pytest.raises(ai.InvalidImageError):
        ai.prepare_image(data)


# ---------- Gemini call (fake client, no network) ----------
class _FakeResponse:
    def __init__(self, parsed=None, text=None, block_reason=None):
        self.parsed, self.text = parsed, text
        self.prompt_feedback = type("PF", (), {"block_reason": block_reason})() if block_reason else None


class _FakeClient:
    def __init__(self, response=None, error=None):
        self.kwargs, self._response, self._error = None, response, error
        self.models = self

    def generate_content(self, **kwargs):
        self.kwargs = kwargs
        if self._error:
            raise self._error
        return self._response


def _use(monkeypatch, fake):
    monkeypatch.setattr(ai, "_get_client", lambda: fake)
    return fake


def test_gemini_request_is_configured_correctly(monkeypatch):
    from google.genai import types
    monkeypatch.setenv("GEMINI_MODEL", "gemini-test-model")
    fake = _use(monkeypatch, _FakeClient(_FakeResponse(parsed=V("walking"))))

    verdict = ai.analyze_photo(b"jpeg-bytes")

    assert verdict.detected_activity == ai.Activity.walking
    assert fake.kwargs["model"] == "gemini-test-model"
    cfg = fake.kwargs["config"]
    assert isinstance(cfg, types.GenerateContentConfig)
    assert cfg.response_mime_type == "application/json"
    assert cfg.response_schema is ai.Verdict
    assert "object by itself is NOT proof" in cfg.system_instruction
    image_part = fake.kwargs["contents"][0]
    assert image_part.inline_data.mime_type == "image/jpeg"
    assert image_part.inline_data.data == b"jpeg-bytes"


def test_text_json_fallback(monkeypatch):
    text = json.dumps({"detected_activity": "reading", "evidence": "object_only",
                       "confidence": "high", "reason": "Book on a bed."})
    _use(monkeypatch, _FakeClient(_FakeResponse(parsed=None, text=text)))
    v = ai.analyze_photo(b"x")
    assert v.detected_activity == ai.Activity.reading and v.evidence == ai.Evidence.object_only


def test_garbage_answer_is_service_error(monkeypatch):
    _use(monkeypatch, _FakeClient(_FakeResponse(parsed=None, text="I think it's walking")))
    with pytest.raises(ai.AIServiceError):
        ai.analyze_photo(b"x")


def test_blocked_image_is_rejected_not_error(monkeypatch):
    _use(monkeypatch, _FakeClient(_FakeResponse(block_reason="SAFETY")))
    v = ai.analyze_photo(b"x")
    assert ai.passes(v, ai.Activity.walking) is False


def test_timeout_is_service_error(monkeypatch):
    _use(monkeypatch, _FakeClient(error=TimeoutError("slow")))
    with pytest.raises(ai.AIServiceError):
        ai.analyze_photo(b"x")


def test_rate_limit_is_service_error(monkeypatch):
    from google.genai import errors
    try:
        err = errors.ClientError(429, {"error": {"code": 429, "message": "quota", "status": "RESOURCE_EXHAUSTED"}})
    except TypeError:
        pytest.skip("google-genai changed the APIError constructor")
    _use(monkeypatch, _FakeClient(error=err))
    with pytest.raises(ai.AIServiceError):
        ai.analyze_photo(b"x")


def test_verdict_schema_is_accepted_by_the_sdk():
    # Builds the real request config locally (no network); fails if the SDK rejects the schema
    from google.genai import types
    types.GenerateContentConfig(response_mime_type="application/json", response_schema=ai.Verdict)


def test_missing_key_is_service_error(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setattr(ai, "_client", None)
    with pytest.raises(ai.AIServiceError):
        ai._get_client()


def test_default_model(monkeypatch):
    monkeypatch.delenv("GEMINI_MODEL", raising=False)
    assert ai.model_name() == ai.DEFAULT_MODEL


# ---------- leveling ----------
@pytest.mark.parametrize("points, level", [(0, 1), (499, 1), (500, 2), (1499, 2), (1500, 3), (2999, 3), (3000, 4), (99999, 4)])
def test_level_for_points(points, level):
    assert level_for_points(points) == level
