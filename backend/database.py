import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import text
from sqlmodel import create_engine, SQLModel, Session

import models  # noqa: F401  (importing models registers every table for create_all)

load_dotenv()

logger = logging.getLogger("growy.db")

# Local test database used when DATABASE_URL is empty: backend/growy_local.db (git-ignored).
LOCAL_DB_FILE = Path(__file__).parent / "growy_local.db"

DATABASE_URL = (os.getenv("DATABASE_URL") or "").strip()
_echo = os.getenv("SQL_ECHO", "").lower() in ("1", "true", "yes")  # print every SQL query

if DATABASE_URL:
    engine = create_engine(
        DATABASE_URL,
        echo=_echo,
        pool_pre_ping=True,   # check a connection is alive before using it
        pool_recycle=300,     # replace connections older than 5 minutes
    )
else:
    # No Supabase string: keep everything in a local file so the app can be
    # tried without any account. Delete growy_local.db to start fresh.
    logger.warning(
        "DATABASE_URL is empty: using the local test database %s. "
        "Put the Supabase connection string in backend/.env to use the shared database.",
        LOCAL_DB_FILE,
    )
    engine = create_engine(
        f"sqlite:///{LOCAL_DB_FILE.as_posix()}",
        echo=_echo,
        connect_args={"check_same_thread": False},  # FastAPI uses several threads
    )


def database_kind() -> str:
    """"postgresql" (Supabase) or "sqlite" (local test file)."""
    return engine.dialect.name


def create_db_and_tables():
    SQLModel.metadata.create_all(engine)
    add_missing_columns()


def add_missing_columns():
    # create_all() creates missing TABLES but never adds new COLUMNS to tables
    # that already exist. These statements are safe to run on every startup:
    # "IF NOT EXISTS" makes them do nothing once the column is there.
    # ("user" is quoted because USER is a reserved word in PostgreSQL.)
    if engine.dialect.name != "postgresql":
        return
    statements = [
        "ALTER TABLE habitlog ADD COLUMN IF NOT EXISTS ai_reason VARCHAR",
        'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS gender VARCHAR',
        'ALTER TABLE "user" ADD COLUMN IF NOT EXISTS display_name VARCHAR',
    ]
    try:
        with engine.begin() as conn:
            for sql in statements:
                conn.execute(text(sql))
    except Exception:
        logger.exception("Could not add missing columns; run them manually in the Supabase SQL editor")
        raise


def get_session():
    with Session(engine) as session:
        yield session
