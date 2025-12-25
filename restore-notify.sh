#!/bin/bash

set +e

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${RCLONE_REMOTE:=gdrive:mc-backups}"
: "${DISCORD_WEBHOOK_URL:=}"
: "${DISCORD_USERNAME:=Minecraft Restore Bot}"
: "${DEBUG:=false}"

if [[ ${DEBUG,,} = true ]]; then
    set -x  
fi

START_TIME=$(date +%s)
RESTORE_STATUS="Failure"
RESTORE_PATH="None"
LOG_CONTENT=""

echo "[restore-notify] Triggered at $(date)"

# -----------------------------
# Determine source
# -----------------------------
LATEST_LOCAL=$(ls -1t "$DEST_DIR"/*.tar.zst 2>/dev/null | head -n1 || true)

if [[ -f "$LATEST_LOCAL" ]]; then
    RESTORE_SOURCE="$LATEST_LOCAL"
    echo "[restore-notify] Using local backup: $LATEST_LOCAL"
else
    echo "[restore-notify] No local backups found. Trying GDrive..."
    TMP_DIR=$(mktemp -d)
    LATEST_REMOTE=$(rclone lsf "$RCLONE_REMOTE" --max-age 0 --files-only -R | grep '\.tar\.zst$' | sort -r | head -n1 || true)
    if [[ -n "$LATEST_REMOTE" ]]; then
        echo "[restore-notify] Found remote backup: $LATEST_REMOTE"
        rclone copy "$RCLONE_REMOTE/$LATEST_REMOTE" "$TMP_DIR"
        RESTORE_SOURCE="$TMP_DIR/$LATEST_REMOTE"
    else
        LOG_CONTENT="No backups available locally or on GDrive."
        echo "[restore-notify] $LOG_CONTENT"
        RESTORE_SOURCE=""
    fi
fi

# -----------------------------
# Perform restore
# -----------------------------
if [[ -n "$RESTORE_SOURCE" ]] && [[ -f "$RESTORE_SOURCE" ]]; then
    tar xf "$RESTORE_SOURCE" -C "$SRC_DIR"
    RESTORE_STATUS="Success"
    RESTORE_PATH="$RESTORE_SOURCE"
    LOG_CONTENT="Restore completed successfully from $RESTORE_SOURCE"
else
    LOG_CONTENT="Restore failed: no valid backup found."
fi

# -----------------------------
# Backup time
# -----------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINS=$(((DURATION % 3600) / 60))
SECS=$((DURATION % 60))
RESTORE_TIME="${HOURS} hrs ${MINS} mins ${SECS} sec"

# -----------------------------
# Status & color
# -----------------------------
if [[ "$RESTORE_STATUS" == "Success" ]]; then
    STATUS_ICON="🟢"
    COLOR=65280
    STATUS_TEXT="Success"
else
    STATUS_ICON="🔴"
    COLOR=16711680
    STATUS_TEXT="Failure"
fi

# -----------------------------
# Discord notification
# -----------------------------
PAYLOAD=$(cat <<EOF
{
  "username": "$DISCORD_USERNAME",
  "embeds": [
    {
      "title": "$STATUS_ICON Minecraft Restore Status : $STATUS_TEXT",
      "color": $COLOR,
      "fields": [
        {
          "name": "Restore Log",
          "value": "Restore Status   : $RESTORE_STATUS\nRestore Path     : $RESTORE_PATH\nRestore Time     : $RESTORE_TIME\n\nRecent Logs:\n\`\`\`$LOG_CONTENT\`\`\`"
        }
      ]
    }
  ]
}
EOF
)

if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    curl -s -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "$DISCORD_WEBHOOK_URL"
    echo "[restore-notify] Discord notification sent with status: $STATUS_TEXT"
else
    echo "[restore-notify] Discord webhook not configured. Skipping notification."
fi

# -----------------------------
# Cleanup temp dir if used
# -----------------------------
if [[ -n "${TMP_DIR:-}" ]] && [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
fi
