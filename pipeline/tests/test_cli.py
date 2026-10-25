"""CLI and worker (C's API queues jobs in pipeline_runs; the worker runs them)."""

import json

from shapely.geometry import box

from conftest import make_stack, scene_ref
from drishti_pipeline import cli, run
from drishti_pipeline.config import Settings
from drishti_pipeline.inference import BaselinePredictor
from drishti_pipeline.store import MemoryStore


def write_labels(path, n):
    feats = [{"type": "Feature", "properties": {"label": "waste"},
              "geometry": box(73.8 + i * 0.002, 18.5, 73.801 + i * 0.002, 18.501).__geo_interface__} for i in range(n)]
    path.write_text(json.dumps({"type": "FeatureCollection", "features": feats}))


def test_labels_check_exit_code(tmp_path, capsys):
    good, bad = tmp_path / "good.geojson", tmp_path / "bad.geojson"
    write_labels(good, 150)
    write_labels(bad, 10)
    assert cli.main(["labels-check", str(good)]) == 0
    assert cli.main(["labels-check", str(bad)]) == 1
    assert "NOT met" in capsys.readouterr().out


def test_evaluate_command(tmp_path, capsys):
    p = tmp_path / "p.geojson"
    write_labels(p, 3)
    assert cli.main(["evaluate", "--pred", str(p), "--truth", str(p)]) == 0
    assert "precision 1.000" in capsys.readouterr().out


def test_worker_runs_queued_detect_job(city, monkeypatch):
    store = MemoryStore()
    rid = store.queue_run(city.id, "detect", {"start": "2026-10-01", "end": "2026-10-10"})
    s1 = scene_ref(3)
    original = run.run_detect

    def offline_detect(c, start, end, st, predictor, **kw):
        kw.update(search=lambda *a: [s1], load=lambda *a: make_stack())
        return original(c, start, end, st, predictor, **kw)

    monkeypatch.setattr(run, "run_detect", offline_detect)
    job = store.claim_next_run()
    out = cli.dispatch(job, {city.id: city}, store, Settings(), predictor_factory=lambda ck: BaselinePredictor())
    assert out["scenes_processed"] == 1 and store.runs[rid]["status"] == "done"
    assert store.claim_next_run() is None


def test_worker_rejects_unknown_jobs(city):
    store = MemoryStore()
    rid = store.queue_run(city.id, "scores")
    cli.dispatch(store.claim_next_run(), {city.id: city}, store, Settings())
    assert store.runs[rid]["status"] == "failed" and "scores" in store.runs[rid]["error"]
    rid2 = store.queue_run("nowhere", "detect")
    cli.dispatch(store.claim_next_run(), {city.id: city}, store, Settings())
    assert store.runs[rid2]["status"] == "failed"


def test_worker_once_drains_the_queue(city, monkeypatch):
    store = MemoryStore()
    seen = []
    monkeypatch.setattr(cli, "dispatch", lambda job, *a, **k: seen.append(job["kind"]))
    monkeypatch.setattr(cli, "load_cities", lambda path: {city.id: city})
    store.queue_run(city.id, "fires")
    store.queue_run(city.id, "detect")
    assert cli.main(["worker", "--once"], store=store) == 0
    assert seen == ["fires", "detect"]
