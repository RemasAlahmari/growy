import logging
import os

from dotenv import load_dotenv
from sqlalchemy import text
from sqlmodel import create_engine, SQLModel, Session

import models  # noqa: F401  (registers every table so create_all() knows about them)

load_dotenv()

logger = logging.getLogger("growy.db")

DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_engine(DATABASE_URL, echo=True)


def create_db_and_tables():
    SQLModel.metadata.create_all(engine)
    add_missing_columns()


def add_missing_columns():
    # create_all() creates missing TABLES but never adds new COLUMNS to tables
    # that already exist. These statements are safe to run on every startup:
    # "IF NOT EXISTS" makes them do nothing once the column is there.
    if engine.dialect.name != "postgresql":
        return
    statements = [
        "ALTER TABLE habitlog ADD COLUMN IF NOT EXISTS ai_reason VARCHAR",
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
