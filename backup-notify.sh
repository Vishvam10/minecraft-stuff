#!/bin/bash

# Called by mc-backup as POST_BACKUP_SCRIPT_FILE
set +euo pipefail

BACKUP_DIR="/backups"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:mc-backups}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK_URL}"
DISCORD_USER="${DISCORD_USERNAME:-Minecraft Backup Bot}"

MAX_LOG_LINES=50

echo "[backup-notify] Triggered at $(date)"

# -----------------------------
# Local Backup
# -----------------------------
LOCAL_STATUS="Success"
LOCAL_PATH="None"
TAR_SIZE="N/A"
BACKUP_TIME="0 hrs 0 mins 0 sec"

START_TIME=$(date +%s)

TAR_FILE=$(ls -1t "$BACKUP_DIR"/*.tar.zst 2>/dev/null | head -n1 || true)
if [ -f "$TAR_FILE" ]; then
    LOCAL_PATH="$TAR_FILE"
    TAR_SIZE=$(du -m "$TAR_FILE" | awk '{print $1 " MB"}')
else
    LOCAL_STATUS="Failure"
fi

# -----------------------------
# GDrive Backup
# -----------------------------
GDRIVE_STATUS="Success"
GDRIVE_PATH="None"
GDRIVE_LOG_CONTENT=""

if [ "$LOCAL_STATUS" = "Success" ]; then
    # Simplified rclone copy, no progress
    if rclone copy "$TAR_FILE" "$RCLONE_REMOTE" --quiet; then
        GDRIVE_PATH="$RCLONE_REMOTE/$(basename "$TAR_FILE")"
        GDRIVE_LOG_CONTENT="GDrive upload succeeded."
    else
        GDRIVE_STATUS="Failure"
        GDRIVE_LOG_CONTENT="Rclone failed. Check container logs."
    fi
else
    GDRIVE_STATUS="Failure"
    GDRIVE_LOG_CONTENT="Skipped GDrive upload due to local backup failure."
fi

# -----------------------------
# Backup time
# -----------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINS=$(((DURATION % 3600) / 60))
SECS=$((DURATION % 60))
BACKUP_TIME="${HOURS} hrs ${MINS} mins ${SECS} sec"

# -----------------------------
# Overall Status
# -----------------------------
if [ "$LOCAL_STATUS" = "Success" ] && [ "$GDRIVE_STATUS" = "Success" ]; then
    STATUS_ICON="🟢"
    STATUS_TEXT="Success"
    COLOR=65280
else
    STATUS_ICON="🔴"
    STATUS_TEXT="Failure"
    COLOR=16711680
fi

# -----------------------------
# Send Discord Notification
# -----------------------------
PAYLOAD=$(cat <<EOF
{
  "username": "$DISCORD_USER",
  "embeds": [
    {
      "title": "$STATUS_ICON Minecraft Backup Status : $STATUS_TEXT",
      "color": $COLOR,
      "fields": [
        {
          "name": "Backup Log",
          "value": "Local Backup Status : $LOCAL_STATUS\nBackup Local Path : $LOCAL_PATH\n\nGDrive Backup Status : $GDRIVE_STATUS\nBackup GDrive Path : $GDRIVE_PATH\n\nTar File Size : $TAR_SIZE\nBackup Time : $BACKUP_TIME\n\nRecent GDrive Logs:\n\`\`\`$GDRIVE_LOG_CONTENT\`\`\`"
        }
      ]
    }
  ]
}
EOF
)

curl -s -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "$DISCORD_WEBHOOK"

echo "[backup-notify] Discord notification sent with status: $STATUS_TEXT"
