FROM python:3.15.0-slim-bookworm AS build

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build
COPY services/worker/requirements.txt ./
RUN python -m venv /venv && /venv/bin/pip install --upgrade pip && /venv/bin/pip install -r requirements.txt

FROM python:3.15.0-slim-bookworm

ENV PATH="/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WORKER_METRICS_PORT=9101

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=build /venv /venv
COPY --chown=app:app shared/voting_common ./voting_common
COPY --chown=app:app services/worker/worker.py ./

USER 10001

EXPOSE 9101

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9101/metrics', timeout=2)"]

CMD ["opentelemetry-instrument", "python", "-u", "worker.py"]
