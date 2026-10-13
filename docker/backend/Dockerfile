FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libcairo2 \
        libffi8 \
        libgdk-pixbuf-2.0-0 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Include templates, locales, Swagger assets and worker entry points alongside the API.
COPY hesabixAPI/ ./

RUN pip install --upgrade pip setuptools wheel \
    && pip install -e .

RUN mkdir -p /var/lib/hesabix/files \
    && useradd --system --uid 10001 --create-home --home-dir /home/hesabix hesabix \
    && chown -R hesabix:hesabix /app /var/lib/hesabix

USER 10001:10001

EXPOSE 8000

CMD ["/bin/sh", "-c", "python -m alembic -c alembic.ini upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS:-2}"]
