FROM python:3.11-slim

# libgeos for shapely; the Noto font so Hindi complaint PDFs render (C-17)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgeos-dev fonts-noto-devanagari && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY fonts ./fonts

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
