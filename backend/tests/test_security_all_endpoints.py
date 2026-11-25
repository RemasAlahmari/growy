"""
IT-NFR3-07 (Student 1): every protected endpoint rejects a request without a login token.

The endpoint list is read from the app's own API description (the same one /docs uses),
so endpoints added later are checked automatically. Only the endpoints in PUBLIC may
answer without a token.

Like test_missing_token_is_401, this file does NOT use the `client` fixture,
because that fixture fakes the login.
"""
import re

import pytest
from fastapi.testclient import TestClient

import ai_verification
import main
from database import get_session

# Public by design:
#  - /health: lets the team and Render check that the server is up (no user data).
#  - /photos/{token}.jpg: image widgets can't send the login token, so the long random
#    token in the address is the secret (see photos.py; tested under NFR4).
PUBLIC = {
    ("GET", "/health"),
    ("GET", "/photos/{token}.jpg"),
}


def all_endpoints():
    """Every (METHOD, path) pair in the API, including groups.py and photos.py routes."""
    paths = main.app.openapi()["paths"]
    return sorted((method.upper(), path) for path, ops in paths.items() for method in ops)


PROTECTED = [e for e in all_endpoints() if e not in PUBLIC]


def fill_path(path):
    """Puts a sample id into the path: /groups/{group_id}/join -> /groups/1/join"""
    return re.sub(r"\{[^}]+\}", "1", path)


@pytest.fixture()
def anonymous_client(db, monkeypatch):
    """A client with NO fake login, using the in-memory test database."""
    main.app.dependency_overrides.clear()
    main.app.dependency_overrides[get_session] = lambda: db
    # Gemini must never be reached without a login.
    monkeypatch.setattr(
        ai_verification, "analyze_photo",
        lambda jpeg_bytes: pytest.fail("Gemini was called without a login"),
    )
    yield TestClient(main.app)
    main.app.dependency_overrides.clear()


def test_endpoint_list_includes_every_router():
    """Checks the test itself: endpoints from main.py, groups.py and photos.py are all found."""
    endpoints = set(all_endpoints())
    assert ("GET", "/users/me") in endpoints
    assert ("POST", "/groups") in endpoints
    assert ("GET", "/photos/{token}.jpg") in endpoints
    assert len(PROTECTED) >= 21


@pytest.mark.parametrize("method,path", PROTECTED, ids=[f"{m} {p}" for m, p in PROTECTED])
def test_protected_endpoint_without_token_is_401(anonymous_client, method, path):
    response = anonymous_client.request(method, fill_path(path))
    assert response.status_code == 401, f"{method} {path} returned {response.status_code}: {response.text}"