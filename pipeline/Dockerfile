# Pipeline worker for IBM Cloud Code Engine (or docker compose locally).
# CPU image: runs detection with a Prithvi checkpoint on CPU (slow) or the spectral baseline.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

COPY pyproject.toml ./
COPY drishti_pipeline ./drishti_pipeline
COPY configs ./configs
RUN pip install --no-cache-dir ".[geo,db]"

# To run Prithvi inside the container, install the train extra and mount the checkpoint:
#   RUN pip install --no-cache-dir ".[train]"
#   docker run -v $PWD/outputs:/models -e DRISHTI_CHECKPOINT=/models/best.ckpt ...

USER nobody
ENTRYPOINT ["drishti-pipeline"]
CMD ["worker"]
