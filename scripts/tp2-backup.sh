#!/bin/bash
# Backup incremental de /home con rsync + hard links (snapshots)
set -euo pipefail
DEST=/var/backups/home
KEEP=48
FECHA=$(date +%Y-%m-%d_%H%M)
LOG=/var/log/tp2-backup.log

mkdir -p "$DEST"
chmod 700 "$DEST"

LINK=()
if [ -L "$DEST/latest" ]; then
  LINK=(--link-dest="$(readlink -f "$DEST/latest")")
fi

rsync -aAXH --delete "${LINK[@]}" /home/ "$DEST/$FECHA/"
ln -sfn "$DEST/$FECHA" "$DEST/latest"

# Conservar solo los ultimos $KEEP snapshots
ls -1d "$DEST"/20* | head -n -"$KEEP" | xargs -r rm -rf

echo "$(date '+%F %T') backup OK -> $DEST/$FECHA" >> "$LOG"
