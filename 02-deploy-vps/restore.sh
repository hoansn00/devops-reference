#!/usr/bin/env bash
# Restore a database dump produced by backup.sh.
#
#   ./restore.sh /opt/backups/db-2026-08-20-0300.sql.gz            # dry run into a scratch DB
#   ./restore.sh /opt/backups/db-2026-08-20-0300.sql.gz --live     # overwrite the real database
#
# Default is the DRY RUN, deliberately. It restores into a throwaway database so
# you can prove the backup is valid without touching production. Run it monthly.
# --live is destructive and asks for confirmation.

set -euo pipefail

DUMP="${1:?usage: restore.sh <dump.sql.gz> [--live]}"
MODE="${2:-dry}"
APP_DIR="${APP_DIR:-/opt/app}"

[ -f "$DUMP" ] || { echo "no such file: $DUMP" >&2; exit 1; }
gzip -t "$DUMP" || { echo "dump is corrupt: $DUMP" >&2; exit 1; }

cd "$APP_DIR"
# shellcheck disable=SC1091
set -a; . ./.env; set +a

if [ "$MODE" = "--live" ]; then
  echo "This OVERWRITES database '${POSTGRES_DB}' on $(hostname)."
  echo "Everything currently in it will be replaced by $DUMP."
  read -r -p "Type the database name to confirm: " confirm
  [ "$confirm" = "${POSTGRES_DB}" ] || { echo "aborted"; exit 1; }

  # Take a safety dump first. Restoring the wrong file is a real mistake, and
  # this is the difference between an inconvenience and a disaster.
  SAFETY="/opt/backups/pre-restore-$(date -u +%F-%H%M).sql.gz"
  mkdir -p /opt/backups
  docker compose exec -T db pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
      --clean --if-exists --no-owner | gzip -9 > "$SAFETY"
  echo "safety dump: $SAFETY"

  gzip -dc "$DUMP" | docker compose exec -T db \
      psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
  echo "restored into ${POSTGRES_DB}"
else
  SCRATCH="restore_check_$(date -u +%s)"
  echo "dry run into scratch database ${SCRATCH} — production untouched"

  docker compose exec -T db createdb -U "${POSTGRES_USER}" "$SCRATCH"
  trap 'docker compose exec -T db dropdb -U "${POSTGRES_USER}" --if-exists "$SCRATCH" >/dev/null 2>&1 || true' EXIT

  gzip -dc "$DUMP" | docker compose exec -T db \
      psql -q -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "$SCRATCH" >/dev/null

  echo "tables restored:"
  docker compose exec -T db psql -U "${POSTGRES_USER}" -d "$SCRATCH" -At -c \
    "select count(*) from information_schema.tables where table_schema='public';"

  docker compose exec -T db psql -U "${POSTGRES_USER}" -d "$SCRATCH" -c \
    "select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 10;"

  echo
  echo "Dump is valid and replayable. Scratch database dropped."
  echo "Note the row counts above — a technically valid dump of an empty database"
  echo "is still a useless backup."
fi
