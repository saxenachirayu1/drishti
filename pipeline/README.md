# pipeline/ (Member B)

Turns Sentinel-2 imagery into dumpsite records in Supabase, and keeps a fire layer on top.

```
STAC search -> cloud mask -> 6-band stack -> 224 px tiles -> Prithvi (or baseline) -> polygons
    -> match to existing sites -> sites, detections, thumbnails      (detect)
NASA FIRMS + Open-Meteo -> fire events linked to sites -> fire-risk score   (fires)
```

## Layout

| Path | What | Requirements |
| --- | --- | --- |
| `drishti_pipeline/stac.py` | Find scenes under 20% cloud, skip ones already stored | B-01 |
| `drishti_pipeline/cloudmask.py` | SCL cloud/shadow mask, skip tiles over 30% masked | B-02 |
| `drishti_pipeline/bands.py` | 6-band stack (B02 B03 B04 B8A B11 B12), offset fix, normalisation | B-03 |
| `drishti_pipeline/tiling.py` | Overlapping 224 px tiles with geo-reference; seamless stitching | B-04 |
| `drishti_pipeline/composite.py` | Monthly cloud-free median composites | B-05 |
| `drishti_pipeline/labels.py`, `labels/README.md` | Label format, mask rasterising, leak-free spatial split | B-06, B-07 |
| `drishti_pipeline/dataset.py` | Writes training tiles in TerraTorch's layout | B-07 |
| `training/prithvi_dumpsite.yaml`, `notebooks/train_colab.ipynb` | Prithvi-EO-2.0 fine-tuning config and Colab notebook | B-08 |
| `drishti_pipeline/evaluation.py` | Pixel IoU, site precision/recall, spectral baseline, false-positive breakdown | B-09, B-10, N-25 |
| `drishti_pipeline/inference.py` | Runs the model over a scene; Prithvi or baseline predictor | B-12 |
| `drishti_pipeline/polygonize.py` | Threshold, drop < 900 m², simplify, mean confidence | B-13 |
| `drishti_pipeline/tracking.py` | One id per dump across scenes; cleared candidates after 2 clear misses | B-14, B-15 |
| `drishti_pipeline/thumbnails.py` | RGB thumbnail with site outline | B-16 |
| `drishti_pipeline/water.py` | OpenStreetMap water features, 200 m test | B-17 |
| `drishti_pipeline/store.py` | Supabase reads/writes (and an in-memory twin for tests), safe re-runs | B-18 |
| `drishti_pipeline/firms.py`, `weather.py`, `risk.py` | FIRMS fires, 500 m linking, Open-Meteo, fire-risk score, backfill | B-19 to B-22 |
| `drishti_pipeline/run.py`, `cli.py` | Jobs, CLI, worker for the API's queue | all |

The database side is described in [`docs/pipeline-db-contract.md`](../docs/pipeline-db-contract.md).

## Set up

```bash
cd pipeline
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev,geo,db]"      # add ,train on a GPU machine
pytest -q                            # 60 offline tests, no keys needed
```

Environment (see the root `.env.example`): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `FIRMS_MAP_KEY`, optional `DRISHTI_CHECKPOINT`.

## Everyday commands

```bash
drishti-pipeline labels-check labels/pune.geojson                 # B-06 target check
drishti-pipeline build-dataset --city Pune --start 2026-01-01 --end 2026-04-30 --scenes 3
terratorch fit -c training/prithvi_dumpsite.yaml                   # on Colab GPU
drishti-pipeline detect --city Pune --checkpoint outputs/prithvi_dumpsite/checkpoints/best.ckpt
drishti-pipeline fires --city Pune                                 # daily
drishti-pipeline backfill-fires --city Pune --months 12            # once
drishti-pipeline worker                                            # in Code Engine: runs queued jobs
```

Without `--checkpoint`, `detect` uses the spectral baseline, so the app gets real (rougher) detections before the model is trained.

## Before training

- Confirm `PRITHVI_MEANS` / `PRITHVI_STDS` in `config.py` against the checkpoint's `config.json` on Hugging Face. The training YAML must use the same numbers (a test checks they match).
- Check the YAML against the TerraTorch example config of the version you install: field names move between releases.
