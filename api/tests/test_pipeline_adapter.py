"""
The Member B trigger seam.

B's worker polls `pipeline_runs` for status 'queued' and claims the oldest, so
triggering a run means writing that row - no service call, and a run survives
the worker being down.
"""
import pytest

from app.repo import get_repo
from app.services import pipeline_adapter


def test_trigger_queues_a_row_for_bs_worker(client):
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r-queue", kind="detect")
    assert out["status"] == "queued"

    row = get_repo().get_run("r-queue")
    assert row["city_id"] == "indore"
    assert row["kind"] == "detect"
    assert row["status"] == "queued", "B's worker only claims rows marked queued"
    assert row["queued_at"], "claim_next_run orders by queued_at"
    assert row["started_at"] is None, "started_at is B's to set when it claims"


def test_dates_are_passed_as_params_b_reads(client):
    pipeline_adapter.trigger_pipeline("indore", run_id="r-params", kind="detect",
                                      date_from="2026-10-01", date_to="2026-10-20")
    params = get_repo().get_run("r-params")["params"]
    assert params == {"start": "2026-10-01", "end": "2026-10-20"}


def test_no_dates_means_empty_params_so_b_uses_its_defaults(client):
    pipeline_adapter.trigger_pipeline("indore", run_id="r-nodates")
    assert get_repo().get_run("r-nodates")["params"] == {}


@pytest.mark.parametrize("kind", ["detect", "fires"])
def test_both_kinds_b_handles_are_accepted(client, kind):
    out = pipeline_adapter.trigger_pipeline("indore", run_id=f"r-{kind}", kind=kind)
    assert out["status"] == "queued"
    assert get_repo().get_run(f"r-{kind}")["kind"] == kind


def test_a_kind_b_cannot_handle_is_rejected_without_queueing(client):
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r-bad", kind="train")
    assert out["status"] == "rejected"
    assert get_repo().get_run("r-bad") is None, "a bad kind must not leave a row behind"


def test_optional_webhook_is_called_after_the_row_is_queued(client, monkeypatch):
    sent = {}
    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL",
                        "https://b.example/run")
    monkeypatch.setattr(pipeline_adapter, "_post_webhook",
                        lambda payload: sent.update(payload) or {"notified": True})
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r-hook")
    assert out["notified"] is True
    assert sent["run_id"] == "r-hook"
    assert get_repo().get_run("r-hook")["status"] == "queued", "row queued regardless"


def test_unreachable_webhook_does_not_lose_the_queued_row(client, monkeypatch):
    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL",
                        "http://127.0.0.1:1/nope")
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r-down")
    assert out["notified"] is False and "error" in out
    assert get_repo().get_run("r-down")["status"] == "queued"


# --- the endpoint ----------------------------------------------------------
def test_run_endpoint_queues_and_reports_status(client, monkeypatch):
    monkeypatch.setattr("app.auth.settings.DEV_ROLE", "admin")
    r = client.post("/pipeline/run", json={"city_id": "indore", "kind": "detect"}).json()
    assert r["status"] == "queued"
    stored = client.get(f"/pipeline/runs/{r['run_id']}").json()
    assert stored["city_id"] == "indore" and stored["status"] == "queued"


def test_run_endpoint_rejects_a_kind_b_cannot_handle(client, monkeypatch):
    monkeypatch.setattr("app.auth.settings.DEV_ROLE", "admin")
    r = client.post("/pipeline/run", json={"city_id": "indore", "kind": "train"})
    assert r.status_code == 400
    assert r.json()["detail"]["error"]["code"] == "bad_kind"


def test_unknown_run_is_a_404_not_an_error_shaped_200(client, monkeypatch):
    monkeypatch.setattr("app.auth.settings.DEV_ROLE", "admin")
    assert client.get("/pipeline/runs/nope").status_code == 404


def test_runs_can_be_listed_by_status(client, monkeypatch):
    monkeypatch.setattr("app.auth.settings.DEV_ROLE", "admin")
    client.post("/pipeline/run", json={"city_id": "indore"})
    rows = client.get("/pipeline/runs", params={"status": "queued"}).json()
    assert rows and all(r["status"] == "queued" for r in rows)
