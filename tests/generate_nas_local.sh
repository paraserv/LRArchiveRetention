#!/bin/bash
# Ultra-fast local NAS data generator using dd and minimal overhead

TARGET_GB=${1:-3072}
ROOT_PATH="/share/LRArchives/TestData"
AVG_FILE_SIZE_MB=35
FILES_PER_FOLDER=75

# Calculate requirements
TOTAL_FILES_NEEDED=$((TARGET_GB * 1024 / AVG_FILE_SIZE_MB))
FOLDERS_NEEDED=$((TOTAL_FILES_NEEDED / FILES_PER_FOLDER))
EXISTING_FOLDERS=$(cd "$ROOT_PATH" 2>/dev/null && ls -1 | wc -l || echo 0)
EXISTING_SIZE_GB=$(cd "$ROOT_PATH" 2>/dev/null && du -s . | awk '{print int($1/1024/1024)}' || echo 0)

echo "Target: ${TARGET_GB} GB"
echo "Existing: ${EXISTING_FOLDERS} folders, ${EXISTING_SIZE_GB} GB"
echo "Need to generate: $((TARGET_GB - EXISTING_SIZE_GB)) GB more"
echo "Folders needed: $((FOLDERS_NEEDED - EXISTING_FOLDERS)) more"
echo

# Create random data source (reuse from /dev/urandom)
RANDOM_FILE="/tmp/random_source_$$"
echo "Creating random data source..."
dd if=/dev/urandom of="$RANDOM_FILE" bs=1M count=100 2>/dev/null

cd "$ROOT_PATH" || exit 1

START_TIME=$(date +%s)
TOTAL_BYTES=0
FOLDER_COUNT=$EXISTING_FOLDERS

# Generate timestamp in format similar to LogRhythm
get_timestamp() {
    # Generate date between 0-1095 days ago
    DAYS_AGO=$((RANDOM % 1095))
    if [ -x /usr/bin/date ]; then
        DATE_CMD="date"
    else
        DATE_CMD="date"
    fi
    
    # QTS date command is limited, so we'll use epoch math
    CURRENT_EPOCH=$(date +%s)
    FOLDER_EPOCH=$((CURRENT_EPOCH - (DAYS_AGO * 86400)))
    
    # Format: YYYYMMDD
    DATESTR=$(date -d "@$FOLDER_EPOCH" +%Y%m%d 2>/dev/null || date -r $FOLDER_EPOCH +%Y%m%d 2>/dev/null || echo "20250101")
    
    # Approximate .NET ticks (simplified)
    TICKS="${FOLDER_EPOCH}0000000"
    
    echo "${DATESTR}_1_1_1_${TICKS}"
}

# Progress reporting
show_progress() {
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    GB_WRITTEN=$((TOTAL_BYTES / 1024 / 1024 / 1024))
    TOTAL_GB=$((EXISTING_SIZE_GB + GB_WRITTEN))
    
    if [ $ELAPSED -gt 0 ]; then
        RATE_MB=$((TOTAL_BYTES / 1024 / 1024 / ELAPSED))
        FOLDERS_PER_SEC=$(echo "scale=2; ($FOLDER_COUNT - $EXISTING_FOLDERS) / $ELAPSED" | bc 2>/dev/null || echo "0")
        
        # ETA calculation
        if [ $FOLDER_COUNT -gt $EXISTING_FOLDERS ]; then
            REMAINING_GB=$((TARGET_GB - TOTAL_GB))
            if [ $RATE_MB -gt 0 ]; then
                ETA_SEC=$((REMAINING_GB * 1024 / RATE_MB))
                ETA_MIN=$((ETA_SEC / 60))
                ETA_STR="${ETA_MIN} minutes"
            else
                ETA_STR="calculating..."
            fi
        else
            ETA_STR="calculating..."
        fi
        
        printf "\rProgress: %d/%d folders | %d GB/%d GB | Rate: %d MB/s | ETA: %s    " \
            "$FOLDER_COUNT" "$FOLDERS_NEEDED" "$TOTAL_GB" "$TARGET_GB" "$RATE_MB" "$ETA_STR"
    fi
}

# Main generation loop
echo "Starting ultra-fast generation..."
while [ $FOLDER_COUNT -lt $FOLDERS_NEEDED ]; do
    FOLDER_NAME=$(get_timestamp)
    mkdir -p "$FOLDER_NAME" 2>/dev/null
    
    # Generate files in this folder
    FILE_COUNT=$((50 + RANDOM % 51))  # 50-100 files
    for i in $(seq 1 $FILE_COUNT); do
        # Generate file size (20-50 MB)
        FILE_SIZE_MB=$((20 + RANDOM % 31))
        
        # Generate filename with timestamp
        TIMESTR=$(printf "%02d%02d%02d" $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)))
        RANDNUM=$((1000 + RANDOM % 9000))
        FILENAME="${FOLDER_NAME:0:8}_${TIMESTR}_${RANDNUM}.lca"
        
        # Ultra-fast file creation using dd
        dd if="$RANDOM_FILE" of="$FOLDER_NAME/$FILENAME" bs=1M count=$FILE_SIZE_MB 2>/dev/null
        
        TOTAL_BYTES=$((TOTAL_BYTES + FILE_SIZE_MB * 1024 * 1024))
    done
    
    FOLDER_COUNT=$((FOLDER_COUNT + 1))
    
    # Show progress every 10 folders
    if [ $((FOLDER_COUNT % 10)) -eq 0 ]; then
        show_progress
    fi
    
    # Check if we've reached target size
    CURRENT_TOTAL_GB=$((EXISTING_SIZE_GB + TOTAL_BYTES / 1024 / 1024 / 1024))
    if [ $CURRENT_TOTAL_GB -ge $TARGET_GB ]; then
        echo
        echo "Target size reached!"
        break
    fi
done

# Cleanup
rm -f "$RANDOM_FILE"

# Final stats
echo
FINAL_TIME=$(date +%s)
TOTAL_TIME=$((FINAL_TIME - START_TIME))
FINAL_GB=$((TOTAL_BYTES / 1024 / 1024 / 1024))
FINAL_RATE=$((TOTAL_BYTES / 1024 / 1024 / TOTAL_TIME))

echo "=== GENERATION COMPLETE ==="
echo "New folders created: $((FOLDER_COUNT - EXISTING_FOLDERS))"
echo "New data generated: ${FINAL_GB} GB"
echo "Total time: $((TOTAL_TIME / 60)) minutes"
echo "Average rate: ${FINAL_RATE} MB/s"
echo "Total data in TestData: $(du -sh "$ROOT_PATH" | cut -f1)"