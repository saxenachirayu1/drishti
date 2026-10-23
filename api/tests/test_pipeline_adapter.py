"""The Member B trigger seam."""
import os

os.environ["RUN_SCHEDULER"] = "0"


from app.services import pipeline_adapter


def test_unwired_pipeline_reports_pending_not_started(monkeypatch):
    """Nothing configured must not claim work started."""
    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL", "")
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r1")
    assert out["status"] == "pending"
    assert out["mode"] == "none"


def test_direct_call_wins_when_implemented(monkeypatch):
    monkeypatch.setattr(pipeline_adapter, "_call_b_directly",
                        lambda payload: {"mode": "direct", "status": "started",
                                         "detail": payload["city_id"]})
    out = pipeline_adapter.trigger_pipeline("bhopal", run_id="r2")
    assert out == {"mode": "direct", "status": "started", "detail": "bhopal"}


def test_webhook_is_posted_with_the_run_details(monkeypatch):
    sent = {}

    def fake_post(payload):
        sent.update(payload)
        return {"mode": "webhook", "status": "started", "http_status": 202}

    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL",
                        "https://b.example/run")
    monkeypatch.setattr(pipeline_adapter, "_post_webhook", fake_post)
    out = pipeline_adapter.trigger_pipeline("indore", date_from="2026-10-01",
                                            date_to="2026-10-20", run_id="r3")
    assert out["status"] == "started"
    assert sent == {"city_id": "indore", "date_from": "2026-10-01",
                    "date_to": "2026-10-20", "run_id": "r3"}


def test_unreachable_b_is_reported_not_raised(monkeypatch):
    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL",
                        "http://127.0.0.1:1/nope")
    out = pipeline_adapter.trigger_pipeline("indore", run_id="r4")
    assert out["status"] == "failed"
    assert "error" in out


def test_run_endpoint_records_the_run_even_when_b_is_unwired(client, monkeypatch):
    monkeypatch.setattr(pipeline_adapter.settings, "PIPELINE_WEBHOOK_URL", "")
    monkeypatch.setattr("app.auth.settings.DEV_ROLE", "admin")
    r = client.post("/pipeline/run", json={"city_id": "indore"}).json()
    assert r["status"] == "pending"
    stored = client.get(f"/pipeline/runs/{r['run_id']}").json()
    assert stored["city_id"] == "indore"
