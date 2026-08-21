#!/usr/bin/env bash
# Nightly backup: Postgres dump + named volumes, gzipped, 7-day retention.
#
#   crontab -e
#   0 3 * * * /opt/app/backup.sh >> /var/log/backup.log 2>&1
#
# This script is only half the job. Its partner is restore.sh — run that once,
# now, before you need it. An untested backup is not a backup.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/app}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backups}"
RETAIN_DAYS="${RETAIN_DAYS:-7}"
STAMP="$(date -u +%F-%H%M)"

cd "$APP_DIR"
# shellcheck disable=SC1091
set -a; [ -f .env ] && . ./.env; set +a

mkdir -p "$BACKUP_DIR"

echo "[$(date -uIs)] backup start"

# --- database -----------------------------------------------------------------
# --clean --if-exists makes the dump replayable onto a non-empty database.
# Single transaction keeps it consistent without locking writers out.
DB_FILE="$BACKUP_DIR/db-$STAMP.sql.gz"
docker compose exec -T db pg_dump \
    -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    --clean --if-exists --no-owner \
  | gzip -9 > "$DB_FILE.partial"
mv "$DB_FILE.partial" "$DB_FILE"     # atomic: a partial file is never mistaken for a backup
echo "  db      -> $DB_FILE ($(du -h "$DB_FILE" | cut -f1))"

# --- uploads / volumes --------------------------------------------------------
if [ -d "$APP_DIR/uploads" ]; then
  UP_FILE="$BACKUP_DIR/uploads-$STAMP.tar.gz"
  tar -czf "$UP_FILE.partial" -C "$APP_DIR" uploads
  mv "$UP_FILE.partial" "$UP_FILE"
  echo "  uploads -> $UP_FILE ($(du -h "$UP_FILE" | cut -f1))"
fi

# --- config (no secrets) ------------------------------------------------------
tar -czf "$BACKUP_DIR/config-$STAMP.tar.gz" -C "$APP_DIR" \
    docker-compose.yml .env.example 2>/dev/null || true

# --- verify the dump is not empty or truncated --------------------------------
if ! gzip -t "$DB_FILE"; then
  echo "  ERROR: $DB_FILE is corrupt" >&2
  exit 1
fi
if [ "$(gzip -dc "$DB_FILE" | head -c 200 | wc -c)" -lt 100 ]; then
  echo "  ERROR: $DB_FILE looks empty" >&2
  exit 1
fi

# --- retention ----------------------------------------------------------------
find "$BACKUP_DIR" -name '*.gz' -mtime "+$RETAIN_DAYS" -delete

echo "[$(date -uIs)] backup ok"

# Backups on the same server do not survive losing the server. Copy them off:
#   rclone copy "$BACKUP_DIR" remote:app-backups --max-age 25h
