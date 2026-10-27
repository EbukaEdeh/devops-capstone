FROM python:3.12.16-slim-bookworm AS build

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build
COPY services/result/requirements.txt ./
RUN python -m venv /venv && /venv/bin/pip install --upgrade pip && /venv/bin/pip install -r requirements.txt

FROM python:3.12.16-slim-bookworm

ENV PATH="/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=build /venv /venv
COPY --chown=app:app shared/voting_common ./voting_common
COPY --chown=app:app services/result/app.py ./
COPY --chown=app:app services/result/templates ./templates
COPY --chown=app:app services/result/static ./static

USER 10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"]

CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
