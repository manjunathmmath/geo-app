#!/usr/bin/env bash
# Backs up the database and the uploaded files. Run from infra/prod on the VM (after chmod +x backup.sh).
# A backup that stays on the same VM does not protect against losing the VM, so set GCS_BUCKET to copy it off.
#
#   GCS_BUCKET=my-geoapp-backups ./backup.sh
#
# Nightly at 02:30 (crontab -e):  30 2 * * * cd /home/YOU/geoapp/infra/prod && GCS_BUCKET=my-geoapp-backups ./backup.sh >> /var/log/geoapp-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"

STAMP=$(date +%Y%m%d-%H%M%S)
DEST=${BACKUP_DIR:-$HOME/geoapp-backups}
KEEP_DAYS=${KEEP_DAYS:-14}
mkdir -p "$DEST"

echo "[$(date -Is)] database dump"
docker compose exec -T db pg_dump -U geoapp -d geoapp --format=custom > "$DEST/db-$STAMP.dump"

echo "[$(date -Is)] uploads archive"
docker run --rm -v geoapp_uploads:/data:ro -v "$DEST":/backup alpine \
  tar czf "/backup/uploads-$STAMP.tgz" -C /data .

if [ -n "${GCS_BUCKET:-}" ]; then
  echo "[$(date -Is)] copying to gs://$GCS_BUCKET"
  gcloud storage cp "$DEST/db-$STAMP.dump" "$DEST/uploads-$STAMP.tgz" "gs://$GCS_BUCKET/"
fi

find "$DEST" -type f -mtime +"$KEEP_DAYS" -delete
echo "[$(date -Is)] done: $DEST/db-$STAMP.dump, $DEST/uploads-$STAMP.tgz"
