"""The "no accounts needed" setup: local SQLite file and Firebase project-ID mode."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi import HTTPException
from firebase_admin import auth as fb_auth

import auth

BACKEND = Path(__file__).resolve().parents[1]


@pytest.fixture()
def clean_firebase_env(monkeypatch, tmp_path):
    for name in ("FIREBASE_SERVICE_ACCOUNT", "FIREBASE_CREDENTIALS", "FIREBASE_PROJECT_ID"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setattr(auth, "LOCAL_KEY_FILE", tmp_path / "no-such-key.json")


def test_no_key_uses_project_id(clean_firebase_env):
    cred, options, source = auth.load_firebase_credentials()
    assert isinstance(cred, auth._ProjectIdOnly)
    assert options == {"projectId": "growy-4036d"}
    assert "project ID" in source


def test_project_id_can_be_changed(clean_firebase_env, monkeypatch):
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "other-project")
    _, options, _ = auth.load_firebase_credentials()
    assert options == {"projectId": "other-project"}


def test_missing_key_file_falls_back_to_project_id(clean_firebase_env, monkeypatch):
    monkeypatch.setenv("FIREBASE_CREDENTIALS", "does-not-exist.json")
    cred, _, _ = auth.load_firebase_credentials()
    assert isinstance(cred, auth._ProjectIdOnly)


def test_key_from_env_is_preferred(clean_firebase_env, monkeypatch):
    sentinel = object()
    monkeypatch.setattr(auth.credentials, "Certificate", lambda info: sentinel)
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT", json.dumps({"type": "service_account"}))
    cred, options, source = auth.load_firebase_credentials()
    assert cred is sentinel and options == {} and source == "FIREBASE_SERVICE_ACCOUNT"


def test_certificate_download_failure_is_503(monkeypatch):
    monkeypatch.setattr(auth, "init_firebase", lambda: None)

    def offline(token):
        raise fb_auth.CertificateFetchError("no internet", cause=None)

    monkeypatch.setattr(auth.auth, "verify_id_token", offline)
    with pytest.raises(HTTPException) as e:
        auth.verify_token("Bearer abc")
    assert e.value.status_code == 503


def test_bad_token_is_401(monkeypatch):
    monkeypatch.setattr(auth, "init_firebase", lambda: None)

    def bad(token):
        raise ValueError("bad token")

    monkeypatch.setattr(auth.auth, "verify_id_token", bad)
    with pytest.raises(HTTPException) as e:
        auth.verify_token("Bearer abc")
    assert e.value.status_code == 401


def test_empty_database_url_uses_local_sqlite_file(tmp_path):
    # Fresh interpreter so database.py is imported with DATABASE_URL empty.
    env = dict(os.environ, DATABASE_URL="")
    code = (
        "import database, sys;"
        "print(database.database_kind());"
        "print(database.LOCAL_DB_FILE)"
    )
    out = subprocess.run([sys.executable, "-c", code], cwd=BACKEND, env=env,
                         capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    kind, path = out.stdout.split()
    assert kind == "sqlite"
    assert Path(path) == BACKEND / "growy_local.db"
