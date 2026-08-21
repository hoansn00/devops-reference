#!/usr/bin/env bash
# Pull a specific image tag and restart. Called by CI, or by hand.
#
#   ./deploy.sh registry.example.com/myapp:9f3c1ab
#
# Records the previously running tag so rollback.sh has something to return to.
# That record is the entire reason rollback is possible.

set -euo pipefail

IMAGE="${1:?usage: deploy.sh <registry/image:tag>}"
APP_DIR="${APP_DIR:-/opt/app}"
HEALTH_URL="${HEALTH_URL:-https://example.com/health}"

cd "$APP_DIR"

PREV="$(grep -E '^IMAGE=' .env.image 2>/dev/null | cut -d= -f2- || true)"
if [ -n "$PREV" ] && [ "$PREV" != "$IMAGE" ]; then
  echo "$PREV" > .last_good.candidate
fi

echo "IMAGE=$IMAGE" > .env.image
docker compose pull app
docker compose up -d app

echo "waiting for health"
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
    echo "healthy after ${i}s"
    [ -f .last_good.candidate ] && mv .last_good.candidate .last_good
    echo "$IMAGE" > .current
    docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
    exit 0
  fi
  sleep 1
done

echo "FAILED health check after 30s — rolling back" >&2
./rollback.sh
exit 1
