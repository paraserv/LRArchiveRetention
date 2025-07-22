#!/bin/bash
# Throttled NAS data generator - safe version without ZFS monitoring

TARGET_GB=${1:-3072}
ROOT_PATH="/share/LRArchives/TestData"
AVG_FILE_SIZE_MB=35
FILES_PER_FOLDER=75

# Safety parameters
MAX_WRITE_RATE_MB=500  # Conservative 500 MB/s limit
SYNC_EVERY_GB=20       # Sync every 20GB
PAUSE_EVERY_FOLDERS=50 # Brief pause every 50 folders
FOLDER_DELAY_MS=100    # 100ms between folders

echo "Throttled NAS Data Generator"
echo "============================"
echo "Target: ${TARGET_GB} GB"
echo "Max write rate: ${MAX_WRITE_RATE_MB} MB/s"
echo "Safety features: Periodic sync, micro-delays, rate limiting"
echo

# Calculate requirements
TOTAL_FILES_NEEDED=$((TARGET_GB * 1024 / AVG_FILE_SIZE_MB))
FOLDERS_NEEDED=$((TOTAL_FILES_NEEDED / FILES_PER_FOLDER))
EXISTING_FOLDERS=$(cd "$ROOT_PATH" 2>/dev/null && ls -1 | wc -l || echo 0)
EXISTING_SIZE_GB=$(cd "$ROOT_PATH" 2>/dev/null && du -s . | awk '{print int($1/1024/1024)}' || echo 0)

echo "Existing: ${EXISTING_FOLDERS} folders, ${EXISTING_SIZE_GB} GB"
echo "Need to generate: $((TARGET_GB - EXISTING_SIZE_GB)) GB more"
echo "Will create approximately $((FOLDERS_NEEDED - EXISTING_FOLDERS)) more folders"
echo

# Create smaller random data source for better performance
RANDOM_FILE="/tmp/random_source_$$"
echo "Creating 50MB random data source..."
dd if=/dev/urandom of="$RANDOM_FILE" bs=1M count=50 2>/dev/null

cd "$ROOT_PATH" || exit 1

START_TIME=$(date +%s)
TOTAL_BYTES=0
FOLDER_COUNT=$EXISTING_FOLDERS
LAST_SYNC_BYTES=0
FOLDERS_SINCE_PAUSE=0

# Timestamp generation
get_timestamp() {
    DAYS_AGO=$((RANDOM % 1095))
    CURRENT_EPOCH=$(date +%s)
    FOLDER_EPOCH=$((CURRENT_EPOCH - (DAYS_AGO * 86400)))
    DATESTR=$(date -d "@$FOLDER_EPOCH" +%Y%m%d 2>/dev/null || echo "20250101")
    TICKS="${FOLDER_EPOCH}0000000"
    echo "${DATESTR}_1_1_1_${TICKS}"
}

# Rate-limited progress display
show_progress() {
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    GB_WRITTEN=$((TOTAL_BYTES / 1024 / 1024 / 1024))
    TOTAL_GB=$((EXISTING_SIZE_GB + GB_WRITTEN))
    
    if [ $ELAPSED -gt 0 ]; then
        RATE_MB=$((TOTAL_BYTES / 1024 / 1024 / ELAPSED))
        REMAINING_GB=$((TARGET_GB - TOTAL_GB))
        
        if [ $RATE_MB -gt 0 ]; then
            ETA_SEC=$((REMAINING_GB * 1024 / RATE_MB))
            ETA_MIN=$((ETA_SEC / 60))
            ETA_STR="${ETA_MIN}m"
        else
            ETA_STR="calculating"
        fi
        
        printf "\rProgress: %d/%d folders | %d GB/%d GB | %d MB/s | ETA: %s    " \
            "$FOLDER_COUNT" "$FOLDERS_NEEDED" "$TOTAL_GB" "$TARGET_GB" "$RATE_MB" "$ETA_STR"
    fi
}

# Main generation loop with safety features
echo "Starting throttled generation..."
echo
RATE_CHECK_START=$START_TIME
RATE_CHECK_BYTES=0

while [ $FOLDER_COUNT -lt $FOLDERS_NEEDED ]; do
    FOLDER_NAME=$(get_timestamp)
    mkdir -p "$FOLDER_NAME" 2>/dev/null
    
    # Generate files in this folder
    FILE_COUNT=$((50 + RANDOM % 51))
    FOLDER_BYTES=0
    
    for i in $(seq 1 $FILE_COUNT); do
        FILE_SIZE_MB=$((20 + RANDOM % 31))
        TIMESTR=$(printf "%02d%02d%02d" $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)))
        RANDNUM=$((1000 + RANDOM % 9000))
        FILENAME="${FOLDER_NAME:0:8}_${TIMESTR}_${RANDNUM}.lca"
        
        # Write file
        dd if="$RANDOM_FILE" of="$FOLDER_NAME/$FILENAME" bs=1M count="$FILE_SIZE_MB" 2>/dev/null
        
        FOLDER_BYTES=$((FOLDER_BYTES + FILE_SIZE_MB * 1024 * 1024))
    done
    
    TOTAL_BYTES=$((TOTAL_BYTES + FOLDER_BYTES))
    RATE_CHECK_BYTES=$((RATE_CHECK_BYTES + FOLDER_BYTES))
    FOLDER_COUNT=$((FOLDER_COUNT + 1))
    FOLDERS_SINCE_PAUSE=$((FOLDERS_SINCE_PAUSE + 1))
    
    # Rate limiting check every folder
    CURRENT_TIME=$(date +%s)
    RATE_CHECK_ELAPSED=$((CURRENT_TIME - RATE_CHECK_START))
    if [ $RATE_CHECK_ELAPSED -gt 0 ]; then
        CURRENT_RATE=$((RATE_CHECK_BYTES / 1024 / 1024 / RATE_CHECK_ELAPSED))
        if [ $CURRENT_RATE -gt $MAX_WRITE_RATE_MB ]; then
            # Calculate required delay
            REQUIRED_TIME=$(echo "scale=3; $RATE_CHECK_BYTES / 1024 / 1024 / $MAX_WRITE_RATE_MB" | bc)
            DELAY=$(echo "scale=3; $REQUIRED_TIME - $RATE_CHECK_ELAPSED" | bc)
            if (( $(echo "$DELAY > 0" | bc) )); then
                sleep "$DELAY"
            fi
        fi
        
        # Reset rate check every 10 seconds
        if [ $RATE_CHECK_ELAPSED -gt 10 ]; then
            RATE_CHECK_START=$CURRENT_TIME
            RATE_CHECK_BYTES=0
        fi
    fi
    
    # Brief pause between folders (100ms)
    perl -e "select(undef, undef, undef, 0.1);" 2>/dev/null || sleep 0.1
    
    # Longer pause every 50 folders
    if [ $FOLDERS_SINCE_PAUSE -ge $PAUSE_EVERY_FOLDERS ]; then
        echo -e "\n[$(date '+%H:%M:%S')] Brief pause after $FOLDERS_SINCE_PAUSE folders..."
        sleep 2
        FOLDERS_SINCE_PAUSE=0
    fi
    
    # Periodic sync
    BYTES_SINCE_SYNC=$((TOTAL_BYTES - LAST_SYNC_BYTES))
    if [ $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024)) -ge $SYNC_EVERY_GB ]; then
        echo -e "\n[$(date '+%H:%M:%S')] Syncing after $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024))GB..."
        sync
        sleep 1
        LAST_SYNC_BYTES=$TOTAL_BYTES
        echo "Sync complete, continuing..."
    fi
    
    # Progress update every 5 folders
    if [ $((FOLDER_COUNT % 5)) -eq 0 ]; then
        show_progress
    fi
    
    # Check if target reached
    CURRENT_TOTAL_GB=$((EXISTING_SIZE_GB + TOTAL_BYTES / 1024 / 1024 / 1024))
    if [ $CURRENT_TOTAL_GB -ge $TARGET_GB ]; then
        echo -e "\nTarget size reached!"
        break
    fi
done

# Final sync
echo -e "\n\nPerforming final sync..."
sync
sleep 2

# Cleanup
rm -f "$RANDOM_FILE"

# Final stats
echo
FINAL_TIME=$(date +%s)
TOTAL_TIME=$((FINAL_TIME - START_TIME))
FINAL_GB=$((TOTAL_BYTES / 1024 / 1024 / 1024))
if [ $TOTAL_TIME -gt 0 ]; then
    FINAL_RATE=$((TOTAL_BYTES / 1024 / 1024 / TOTAL_TIME))
else
    FINAL_RATE=0
fi

echo "=== GENERATION COMPLETE ==="
echo "New folders created: $((FOLDER_COUNT - EXISTING_FOLDERS))"
echo "New data generated: ${FINAL_GB} GB"
echo "Total time: $((TOTAL_TIME / 60)) minutes"
echo "Average rate: ${FINAL_RATE} MB/s (throttled)"
echo "Total data in TestData: $(du -sh "$ROOT_PATH" 2>/dev/null | cut -f1)"
echo
echo "Storage usage:"
df -h "$ROOT_PATH"