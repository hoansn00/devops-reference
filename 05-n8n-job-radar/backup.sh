#!/usr/bin/env bash
# Daily backup: pg_dump + n8n data volume. Keeps 7 days. Run from the compose directory via cron.
set -euo pipefail
cd "$(dirname "$0")"
BK=./backups; mkdir -p "$BK"
TS=$(date +%Y%m%d-%H%M%S)
docker compose exec -T postgres pg_dump -U n8n -d n8n --no-owner | gzip > "$BK/n8n-db-$TS.sql.gz"
docker run --rm -v "$(basename "$PWD")_n8n_data":/src:ro -v "$PWD/$BK":/dst alpine \
  tar czf "/dst/n8n-data-$TS.tar.gz" -C /src .
find "$BK" -type f -mtime +7 -delete
ls -lh "$BK" | tail -n +2
