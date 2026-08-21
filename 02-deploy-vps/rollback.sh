#!/usr/bin/env bash
# Return to the last image that passed its health check.
#
#   ./rollback.sh                                       # last known good
#   ./rollback.sh registry.example.com/myapp:9f3c1ab     # a specific tag
#
# This works only because every image is tagged by commit SHA. If you deploy
# ":latest" there is no previous artifact to point at, and this script has
# nothing to do.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/app}"
HEALTH_URL="${HEALTH_URL:-https://example.com/health}"
cd "$APP_DIR"

TARGET="${1:-$(cat .last_good 2>/dev/null || true)}"
if [ -z "$TARGET" ]; then
  echo "No .last_good recorded and no tag given." >&2
  echo "Available locally:" >&2
  docker image ls --format '  {{.Repository}}:{{.Tag}}  ({{.CreatedSince}})' | head -20 >&2
  exit 1
fi

echo "rolling back to $TARGET"
echo "IMAGE=$TARGET" > .env.image
docker compose pull app 2>/dev/null || true   # may already be local
docker compose up -d app

for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
    echo "rollback healthy after ${i}s"
    echo "$TARGET" > .current
    exit 0
  fi
  sleep 1
done

echo "Rollback target is ALSO unhealthy. The problem is probably not the image —" >&2
echo "check the database, disk space, and env vars:" >&2
echo "  docker compose logs --tail 100 app" >&2
echo "  df -h; df -i; free -h" >&2
exit 1
