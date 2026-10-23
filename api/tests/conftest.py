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
