#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

WITH_OBSERVABILITY=false
OPEN_BROWSER=false
for arg in "$@"; do
  case "$arg" in
    --with-observability) WITH_OBSERVABILITY=true ;;
    --open) OPEN_BROWSER=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -f .env ]; then
  umask 077
  cat > .env <<EOF
# Generated locally. Never commit this file.
POSTGRES_USER=voting
POSTGRES_DB=voting
POSTGRES_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)
EOF
  echo "Created .env with random local-only credentials."
fi

docker info >/dev/null
FILES=(-f compose.yaml)
if [ "$WITH_OBSERVABILITY" = true ]; then
  FILES+=(-f compose.observability.yaml)
fi

docker compose "${FILES[@]}" up -d --build

echo "Waiting for services..."
for _ in $(seq 1 90); do
  if curl -fsS http://localhost:8080/readyz >/dev/null 2>&1 \
     && curl -fsS http://localhost:8081/readyz >/dev/null 2>&1; then
    echo "Voting App is ready"
    echo "  Vote:    http://localhost:8080"
    echo "  Results: http://localhost:8081"
    if [ "$WITH_OBSERVABILITY" = true ]; then
      echo "  Grafana: http://localhost:3000"
      echo "  Jaeger:  http://localhost:16686"
    fi
    if [ "$OPEN_BROWSER" = true ]; then command -v xdg-open >/dev/null && xdg-open http://localhost:8080 || true; fi
    exit 0
  fi
  sleep 2
done

docker compose "${FILES[@]}" ps
echo "Services did not become ready. Check: docker compose logs --tail=100" >&2
exit 1
