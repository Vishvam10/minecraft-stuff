#!/bin/bash
set +e

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${RCLONE_REMOTE:=gdrive:mc-backups}"
: "${DISCORD_WEBHOOK_URL:=}"
: "${DISCORD_USERNAME:=Minecraft Restore Bot}"
: "${DEBUG:=false}"

PAGE_SIZE=5
[[ ${DEBUG,,} == true ]] && set -x

START_TIME=$(date +%s)
RESTORE_STATUS="Failure"
RESTORE_PATH="None"
LOG_CONTENT=""

echo
echo "======================================"
echo " Minecraft Interactive Restore Tool"
echo "======================================"
echo

# -----------------------------
# Check if data folder already exists
# -----------------------------
mkdir -p "$SRC_DIR"

if [[ "$(ls -A "$SRC_DIR")" ]]; then
    echo "⚠️  Data folder $SRC_DIR already contains files."
    read -rp "Do you want to remove its contents and continue? Type YES to confirm: " REMOVE_CONFIRM
    if [[ "$REMOVE_CONFIRM" != "YES" ]]; then
        echo "Restore aborted."
        exit 1
    else
        echo "[restore] Clearing existing data..."
        rm -rf "$SRC_DIR"/*
    fi
fi

# -----------------------------
# Gather backups
# -----------------------------
echo "[restore] Scanning local backups..."
mapfile -t LOCAL_BACKUPS < <(ls -1t "$DEST_DIR"/*.tar.zst 2>/dev/null)

echo "[restore] Scanning GDrive backups..."
mapfile -t REMOTE_BACKUPS < <(
    rclone lsf "$RCLONE_REMOTE" --files-only \
    | grep '\.tar\.zst$' | sort -r
)

TOTAL_LOCAL=${#LOCAL_BACKUPS[@]}
TOTAL_REMOTE=${#REMOTE_BACKUPS[@]}

if [[ $TOTAL_LOCAL -eq 0 && $TOTAL_REMOTE -eq 0 ]]; then
    echo "[restore] No backups found"
    exit 1
fi

# -----------------------------
# Interactive menu
# -----------------------------
PAGE=0
while true; do
    clear
    echo "Available Backups (page $((PAGE+1)))"
    echo "--------------------------------------"

    START=$((PAGE * PAGE_SIZE))
    END=$((START + PAGE_SIZE))
    INDEX=1

    for ((i=START; i<END; i++)); do
        if [[ $i -lt $TOTAL_LOCAL ]]; then
            FILE="${LOCAL_BACKUPS[$i]}"
            echo " $INDEX) [LOCAL ] $(basename "$FILE")"
        elif [[ $((i - TOTAL_LOCAL)) -lt $TOTAL_REMOTE ]]; then
            FILE="${REMOTE_BACKUPS[$((i - TOTAL_LOCAL))]}"
            echo " $INDEX) [GDRIVE] $FILE"
        fi
        ((INDEX++))
    done

    echo
    echo "n) Next page    p) Previous page"
    echo "q) Quit"
    echo
    read -rp "Select a backup: " CHOICE

    case "$CHOICE" in
        q) exit 0 ;;
        n)
            (( (PAGE+1)*PAGE_SIZE < TOTAL_LOCAL+TOTAL_REMOTE )) && ((PAGE++))
            continue
            ;;
        p)
            (( PAGE > 0 )) && ((PAGE--))
            continue
            ;;
        [1-5])
            SELECTED_INDEX=$((START + CHOICE - 1))
            break
            ;;
        *)
            continue
            ;;
    esac
done

# -----------------------------
# Resolve selection
# -----------------------------
if [[ $SELECTED_INDEX -lt $TOTAL_LOCAL ]]; then
    RESTORE_SOURCE="${LOCAL_BACKUPS[$SELECTED_INDEX]}"
    SOURCE_TYPE="LOCAL"
else
    TMP_DIR=$(mktemp -d)
    REMOTE_INDEX=$((SELECTED_INDEX - TOTAL_LOCAL))
    FILE="${REMOTE_BACKUPS[$REMOTE_INDEX]}"
    echo "[restore] Downloading $FILE from GDrive..."
    rclone copy "$RCLONE_REMOTE/$FILE" "$TMP_DIR"
    RESTORE_SOURCE="$TMP_DIR/$FILE"
    SOURCE_TYPE="GDRIVE"
fi

echo
echo "[DEBUG] Backup source: $RESTORE_SOURCE"
echo "[DEBUG] Destination folder: $SRC_DIR"
echo "[DEBUG] Contents of backup (top 20 files):"
zstd -dc "$RESTORE_SOURCE" | tar -tf - | head -20

# Detect the top-level folder in the tar (if any)
TOP_LEVEL_FOLDER=$(zstd -dc "$RESTORE_SOURCE" | tar -tf - | head -1 | cut -d/ -f1)
WORLD_PATH="$SRC_DIR/$TOP_LEVEL_FOLDER"

# -----------------------------
# Confirm restore
# -----------------------------
echo
echo "⚠️  This will restore backup into: $WORLD_PATH"
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" != "YES" ]] && { echo "Restore cancelled."; exit 1; }

# -----------------------------
# Restore
# -----------------------------
# Ensure world folder exists
mkdir -p "$WORLD_PATH"

echo "[restore] Restoring backup..."
zstd -dc "$RESTORE_SOURCE" | tar -xf - -C "$SRC_DIR"
TAR_STATUS=$?

if [[ $TAR_STATUS -eq 0 ]]; then
    RESTORE_STATUS="Success"
    RESTORE_PATH="$RESTORE_SOURCE"
    LOG_CONTENT="Restored from $SOURCE_TYPE backup into $WORLD_PATH"
else
    LOG_CONTENT="Restore failed (tar exit $TAR_STATUS)"
fi

# -----------------------------
# Timing
# -----------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
RESTORE_TIME="$((DURATION/60)) mins $((DURATION%60)) sec"

# -----------------------------
# Discord notification
# -----------------------------
COLOR=16711680
ICON="🔴"
[[ "$RESTORE_STATUS" == "Success" ]] && COLOR=65280 && ICON="🟢"

PAYLOAD=$(cat <<EOF
{
  "username": "$DISCORD_USERNAME",
  "embeds": [
    {
      "title": "$ICON Minecraft Restore Status",
      "color": $COLOR,
      "fields": [
        {
          "name": "Restore Details",
          "value": "Status: $RESTORE_STATUS\nTime: $RESTORE_TIME\nBackup path: $RESTORE_PATH\nRestored world folder: $WORLD_PATH\n\n$LOG_CONTENT"
        }
      ]
    }
  ]
}
EOF
)

[[ -n "$DISCORD_WEBHOOK_URL" ]] && \
  curl -s -H "Content-Type: application/json" \
       -X POST -d "$PAYLOAD" "$DISCORD_WEBHOOK_URL"

# -----------------------------
# Cleanup
# -----------------------------
[[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"

echo
echo "✅ Restore completed with status: $RESTORE_STATUS"
echo "Restored world folder: $WORLD_PATH"
