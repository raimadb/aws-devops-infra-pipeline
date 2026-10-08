import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from config import settings
from database import Base, engine
from main import app

SAFE_HOSTS = {"localhost", "127.0.0.1", "postgres"}


@pytest.fixture
def client():
    # No `with` block, so the startup hook (and its DB call) does not run.
    return TestClient(app)


@pytest.fixture
def db_client():
    # These tests wipe the items table, so refuse to run against a real environment.
    if settings.db_host not in SAFE_HOSTS:
        pytest.fail(f"Refusing to run integration tests against {settings.db_host}")
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM items"))
    with TestClient(app) as c:
        yield c
