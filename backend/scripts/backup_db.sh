#!/usr/bin/env bash
# Nightly Postgres dump. Run from the repo root on the server, e.g. via cron:
#   0 3 * * * cd /home/ubuntu/app && backend/scripts/backup_db.sh
# Set OCI_BUCKET to also upload to Object Storage (needs the `oci` CLI configured).
set -euo pipefail

DIR="${BACKUP_DIR:-$HOME/backups}"
mkdir -p "$DIR"
FILE="$DIR/gcc_$(date +%F).sql.gz"

docker compose -f docker-compose.prod.yml exec -T db pg_dump -U gcc gcc | gzip > "$FILE"

if [ -n "${OCI_BUCKET:-}" ]; then
  oci os object put --bucket-name "$OCI_BUCKET" --file "$FILE" --force
fi

# Keep 14 days locally.
find "$DIR" -name 'gcc_*.sql.gz' -mtime +14 -delete
