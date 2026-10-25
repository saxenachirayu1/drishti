"""
Shared test setup.

Two things every test module wants, defined once here so adding a test file
(or a whole area of tests, as A's and B's work lands) needs no boilerplate:

  * the scheduler off, so tests do not race a background job;
  * a fresh seeded database per module, so modules cannot leak state into each
    other. Without this the suite only passes in alphabetical order - a test
    that ingests a site would break another module's "there are 3 sites".
"""
import os
import tempfile

# ---------------------------------------------------------------------------
# SAFETY: the tests must never touch a real database.
#
# app/config.py calls load_dotenv(), so a developer .env holding A's Supabase
# service-role key would otherwise be picked up here and the suite would read
# and WRITE A's live project - `env -u SUPABASE_URL` does not help, because the
# values come off disk. These are set before app.config is imported, so the
# in-memory backend is forced no matter what .env says.
#
# To test against a real project, do it deliberately in a separate script with
# set_repo(SupabaseRepo()), never by relaxing this.
# ---------------------------------------------------------------------------
os.environ["REPO_BACKEND"] = "memory"
os.environ["SUPABASE_URL"] = ""
os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""
os.environ["SUPABASE_SERVICE_KEY"] = ""
os.environ["SUPABASE_JWT_SECRET"] = ""
os.environ["AUTH_BYPASS"] = "1"
os.environ["PIPELINE_WEBHOOK_URL"] = ""

os.environ.setdefault("RUN_SCHEDULER", "0")
# Keep generated PDFs out of the repo's out/ directory.
os.environ.setdefault("PDF_OUT_DIR", tempfile.mkdtemp(prefix="drishti-test-pdf-"))

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.repo import reset_repo


@pytest.fixture(scope="module")
def client():
    """A client over a freshly seeded database.

    Entering TestClient runs the app's lifespan, which is what assigns sites to
    wards - so the reset has to happen before, not after.
    """
    reset_repo()
    with TestClient(app) as c:
        yield c
    reset_repo()


@pytest.fixture
def repo():
    """A fresh repo for tests that talk to the data layer directly."""
    from app.repo import InMemoryRepo

    return InMemoryRepo()


@pytest.fixture(autouse=True)
def _never_touch_a_real_database():
    """Fail loudly if a test ever ends up on the Supabase backend."""
    from app.config import settings
    from app.repo import InMemoryRepo, get_repo

    assert settings.REPO_BACKEND == "memory", (
        "tests must run on the in-memory backend; REPO_BACKEND="
        f"{settings.REPO_BACKEND!r}")
    assert isinstance(get_repo(), InMemoryRepo), (
        f"tests are pointed at {type(get_repo()).__name__}, not InMemoryRepo")
    yield
