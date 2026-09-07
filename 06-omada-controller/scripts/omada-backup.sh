#!/usr/bin/env bash
# Omada controller backup. Plain mongodump + tar, no vendor agent.
# Omada runs its OWN mongod on 27217 (see properties/omada.properties),
# not the system service on 27017 - dumping 27017 would back up nothing.
set -euo pipefail
DEST=/opt/omada-backups
KEEP_DAYS=7
PORT=27217
APP=/opt/tplink/EAPController
TS=$(date -u +%Y%m%d-%H%M%S)

mkdir -p "$DEST"
mongodump --quiet --port "$PORT" --db omada      --archive="$DEST/omada-$TS.archive"      --gzip
mongodump --quiet --port "$PORT" --db omada_data --archive="$DEST/omada_data-$TS.archive" --gzip
tar czf "$DEST/omada-conf-$TS.tar.gz" -C "$APP" properties keystore 2>/dev/null || \
tar czf "$DEST/omada-conf-$TS.tar.gz" -C "$APP" properties

find "$DEST" -type f -mtime +"$KEEP_DAYS" -delete
printf '%s  backup ok  %s\n' "$(date -u +%FT%TZ)" "$(du -sh "$DEST" | cut -f1)" >> "$DEST/backup.log"
