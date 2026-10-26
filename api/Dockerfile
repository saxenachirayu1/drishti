FROM python:3.11-slim

# libgeos for shapely; the Noto font so Hindi complaint PDFs render (C-17)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgeos-dev fonts-noto-devanagari && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY fonts ./fonts

# Hosts inject the port they want the service on: Hugging Face Spaces uses
# 7860, Code Engine and Cloud Run 8080, Render and Koyeb set $PORT. Default to
# 8000 so a plain `docker run` still behaves as the README says.
ENV PORT=8000
EXPOSE 8000

# Shell form so $PORT is expanded at start-up rather than taken literally.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT}
