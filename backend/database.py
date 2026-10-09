import os
from dotenv import load_dotenv
from sqlmodel import create_engine, SQLModel, Session
from models import User  # importing models registers all tables for create_all

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_engine(
    DATABASE_URL,
    echo=False,           # set to True to print every SQL query (useful for debugging)
    pool_pre_ping=True,   # check a connection is alive before using it
    pool_recycle=300,     # replace connections older than 5 minutes
)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session