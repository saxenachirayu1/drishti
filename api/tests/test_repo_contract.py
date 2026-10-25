"""
The backend contract.

Every backend must answer the same calls with the same shapes, or swapping one
in breaks routers that never knew which backend they had. These tests run the
contract against InMemoryRepo now and are the first thing to point at A's real
Supabase project (see INTEGRATION.md).
"""
import os

os.environ["RUN_SCHEDULER"] = "0"

import inspect

import pytest
from shapely.geometry import Point

from app.repo import (
    REPO_METHODS,
    InMemoryRepo,
    SupabaseRepo,
    build_repo,
    get_repo,
    reset_repo,
    set_repo,
)


@pytest.mark.parametrize("backend", [InMemoryRepo, SupabaseRepo],
                         ids=["memory", "supabase"])
@pytest.mark.parametrize("method", REPO_METHODS)
def test_backend_implements_the_method(backend, method):
    """A missing method here is a backend that will fail at runtime, not import."""
    assert callable(getattr(backend, method, None)), \
        f"{backend.__name__} is missing {method}()"


@pytest.mark.parametrize("method", REPO_METHODS)
def test_backends_agree_on_the_signature(method):
    """
    The two backends must take the same arguments. This is the check that
    would have caught ward_containing() taking (lon, lat) on one side and a
    shapely Point on the other.
    """
    mem = inspect.signature(getattr(InMemoryRepo, method))
    sup = inspect.signature(getattr(SupabaseRepo, method))
    assert list(mem.parameters) == list(sup.parameters), (
        f"{method}(): memory takes {list(mem.parameters)}, "
        f"supabase takes {list(sup.parameters)}")


# --- behaviour the routers rely on -----------------------------------------
def test_sites_come_back_with_a_shapely_centroid(repo):
    """Ward mapping and report matching both call .distance()/.contains()."""
    for site in repo.list_sites():
        assert hasattr(site["centroid"], "distance")


def test_upsert_site_inserts_then_merges(repo):
    repo.upsert_site({"id": "site-new", "city_id": "indore",
                      "centroid": Point(75.80, 22.65), "area_m2": 100,
                      "status": "active"})
    assert repo.get_site("site-new")["area_m2"] == 100

    repo.upsert_site({"id": "site-new", "area_m2": 250})
    merged = repo.get_site("site-new")
    assert merged["area_m2"] == 250
    assert merged["city_id"] == "indore", "upsert dropped a field it was not given"
    assert len([s for s in repo.list_sites() if s["id"] == "site-new"]) == 1


def test_upsert_detection_and_fire_event_are_idempotent(repo):
    det = {"id": "det-x", "site_id": "site-1", "area_m2": 10, "confidence": 0.5}
    repo.upsert_detection(det)
    repo.upsert_detection(det)
    assert len([d for d in repo.list_detections("site-1") if d["id"] == "det-x"]) == 1

    ev = {"id": "fe-x", "site_id": "site-1", "frp": 1.0}
    repo.upsert_fire_event(ev)
    repo.upsert_fire_event(ev)
    assert len([e for e in repo.list_fire_events("site-1") if e["id"] == "fe-x"]) == 1


def test_ward_containing_takes_a_point(repo):
    ward = repo.ward_containing(Point(75.80, 22.65), city_id="indore")
    assert ward["id"] == "w-ind-12"


# --- the swap seam itself ---------------------------------------------------
def test_set_repo_swaps_the_backend_and_gives_the_old_one_back():
    class Fake(InMemoryRepo):
        pass

    fake = Fake()
    previous = set_repo(fake)
    try:
        assert get_repo() is fake
    finally:
        set_repo(previous)
    assert get_repo() is not fake


def test_reset_repo_rebuilds_from_settings():
    reset_repo()
    first = get_repo()
    assert isinstance(first, InMemoryRepo)   # offline by default
    reset_repo()
    assert get_repo() is not first


def test_build_repo_honours_the_forced_backend(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "REPO_BACKEND", "memory")
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", "key")
    assert isinstance(build_repo(), InMemoryRepo), \
        "REPO_BACKEND=memory must win over the keys being present"
