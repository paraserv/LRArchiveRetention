#!/bin/bash
# Balanced NAS data generator - faster but safe, with detailed progress

TARGET_GB=${1:-3072}
ROOT_PATH="/share/LRArchives"
LOG_FILE="/share/LRArchives/generation.log"
TEMP_DIR="/share/LRArchives/.temp"
AVG_FILE_SIZE_MB=35
FILES_PER_FOLDER=75

# Balanced parameters - faster but still safe
MAX_WRITE_RATE_MB=500       # Increased from 200 to 500 MB/s
SYNC_EVERY_GB=25            # Sync every 25 GB instead of 10
PAUSE_EVERY_FOLDERS=50      # Pause every 50 folders instead of 25
FOLDER_PAUSE_SEC=1          # Shorter pause
FILES_PER_BATCH=25          # Larger batches
BATCH_PAUSE_SEC=0.2         # Shorter batch pause

mkdir -p "$TEMP_DIR" 2>/dev/null

# Redirect output to log
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "=== Balanced NAS Data Generator ==="
echo "Started: $(date)"
echo "Target: ${TARGET_GB} GB at ${ROOT_PATH}"
echo "Speed: ${MAX_WRITE_RATE_MB} MB/s max | Sync: ${SYNC_EVERY_GB} GB | Pause: ${PAUSE_EVERY_FOLDERS} folders"
echo

# Get disk usage function
get_disk_usage_gb() {
    df -h /share/LRArchives | tail -1 | awk '{
        size=$3
        if (index(size, "T") > 0) {
            gsub(/T/, "", size)
            print int(size * 1024)
        } else if (index(size, "G") > 0) {
            gsub(/G/, "", size)
            print int(size)
        } else {
            print 0
        }
    }'
}

STARTING_GB=$(get_disk_usage_gb)
TOTAL_FOLDERS_NEEDED=$((((TARGET_GB - STARTING_GB) * 1024) / (AVG_FILE_SIZE_MB * FILES_PER_FOLDER)))

echo "Current: ${STARTING_GB} GB | Need: $((TARGET_GB - STARTING_GB)) GB | Est. folders: ${TOTAL_FOLDERS_NEEDED}"
echo

# Create random source
RANDOM_FILE="${TEMP_DIR}/random_source_$$"
echo "Creating 50MB random data source..."
dd if=/dev/urandom of="$RANDOM_FILE" bs=1M count=50 2>/dev/null

cd "$ROOT_PATH" || exit 1

START_TIME=$(date +%s)
FOLDER_COUNT=0
TOTAL_FILES=0
TOTAL_BYTES_WRITTEN=0
LAST_PROGRESS_TIME=$START_TIME
LAST_DISK_GB=$STARTING_GB
SPEED_SAMPLES=()

# Cleanup on exit
trap "rm -f $RANDOM_FILE; rmdir $TEMP_DIR 2>/dev/null" EXIT

# Timestamp generation
get_timestamp() {
    DAYS_AGO=$((RANDOM % 1095))
    CURRENT_EPOCH=$(date +%s)
    FOLDER_EPOCH=$((CURRENT_EPOCH - (DAYS_AGO * 86400)))
    DATESTR=$(date -d "@$FOLDER_EPOCH" +%Y%m%d 2>/dev/null || date -r "$FOLDER_EPOCH" +%Y%m%d 2>/dev/null || echo "20250101")
    TICKS="${FOLDER_EPOCH}0000000"
    echo "${DATESTR}_1_1_1_${TICKS}:${FOLDER_EPOCH}"
}

# Calculate average speed
calc_avg_speed() {
    local sum=0
    local count=${#SPEED_SAMPLES[@]}
    [ $count -eq 0 ] && echo 0 && return
    for speed in "${SPEED_SAMPLES[@]}"; do
        sum=$((sum + speed))
    done
    echo $((sum / count))
}

# Show detailed progress
show_progress() {
    local current_time=$(date +%s)
    local current_gb=$(get_disk_usage_gb)
    local elapsed=$((current_time - START_TIME))
    local time_since_last=$((current_time - LAST_PROGRESS_TIME))
    
    # Calculate speeds
    local gb_since_last=$((current_gb - LAST_DISK_GB))
    local instant_speed=0
    if [ $time_since_last -gt 0 ] && [ $gb_since_last -gt 0 ]; then
        instant_speed=$((gb_since_last * 1024 / time_since_last))
        SPEED_SAMPLES+=($instant_speed)
        [ ${#SPEED_SAMPLES[@]} -gt 10 ] && SPEED_SAMPLES=("${SPEED_SAMPLES[@]:1}")
    fi
    
    local avg_speed=$(calc_avg_speed)
    local overall_speed=0
    [ $elapsed -gt 0 ] && overall_speed=$(((current_gb - STARTING_GB) * 1024 / elapsed))
    
    # Calculate ETA
    local remaining_gb=$((TARGET_GB - current_gb))
    local eta_str="calculating"
    if [ $avg_speed -gt 0 ]; then
        local eta_sec=$((remaining_gb * 1024 / avg_speed))
        local eta_min=$((eta_sec / 60))
        eta_str="${eta_min}m"
    fi
    
    # Calculate rates
    local files_per_sec=0
    [ $elapsed -gt 0 ] && files_per_sec=$((TOTAL_FILES * 100 / elapsed))
    
    echo
    echo "[$(date '+%H:%M:%S')] === Progress Update ==="
    echo "Folders: ${FOLDER_COUNT}/${TOTAL_FOLDERS_NEEDED} | Files: ${TOTAL_FILES} | Files/sec: $((files_per_sec / 100)).$((files_per_sec % 100))"
    echo "Disk: ${current_gb} GB / ${TARGET_GB} GB | Generated: $((current_gb - STARTING_GB)) GB"
    echo "Speed: Instant=${instant_speed} MB/s | Avg=${avg_speed} MB/s | Overall=${overall_speed} MB/s"
    echo "ETA: ${eta_str} | Elapsed: $((elapsed / 60))m"
    echo
    
    LAST_PROGRESS_TIME=$current_time
    LAST_DISK_GB=$current_gb
}

echo "Starting balanced generation..."
echo

# Main loop
BYTES_SINCE_SYNC=0
FOLDERS_SINCE_PAUSE=0
BATCH_START_TIME=$(date +%s)

while true; do
    # Check target
    CURRENT_GB=$(get_disk_usage_gb)
    if [ $CURRENT_GB -ge $TARGET_GB ]; then
        echo "[$(date '+%H:%M:%S')] Target reached: ${CURRENT_GB} GB"
        break
    fi
    
    TIMESTAMP_INFO=$(get_timestamp)
    FOLDER_NAME="${TIMESTAMP_INFO%:*}"
    FOLDER_EPOCH="${TIMESTAMP_INFO#*:}"
    mkdir -p "$FOLDER_NAME" 2>/dev/null
    
    # Calculate touch timestamp format (YYYYMMDDHHMM.SS)
    TOUCH_TIME=$(date -d "@$FOLDER_EPOCH" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$FOLDER_EPOCH" +%Y%m%d%H%M.%S 2>/dev/null || echo "202201010000.00")
    
    FILE_COUNT=$((50 + RANDOM % 51))
    FOLDER_BYTES=0
    
    # Create files in batches
    for i in $(seq 1 $FILE_COUNT); do
        FILE_SIZE_MB=$((20 + RANDOM % 31))
        TIMESTR=$(printf "%02d%02d%02d" $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)))
        RANDNUM=$((1000 + RANDOM % 9000))
        FILENAME="${FOLDER_NAME:0:8}_${TIMESTR}_${RANDNUM}.lca"
        
        dd if="$RANDOM_FILE" of="$FOLDER_NAME/$FILENAME" bs=1M count="$FILE_SIZE_MB" 2>/dev/null
        
        # Set file modification time to match the backdated folder date
        touch -t "$TOUCH_TIME" "$FOLDER_NAME/$FILENAME" 2>/dev/null
        
        FOLDER_BYTES=$((FOLDER_BYTES + FILE_SIZE_MB * 1024 * 1024))
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # Brief pause between batches
        if [ $((i % FILES_PER_BATCH)) -eq 0 ] && [ $i -lt $FILE_COUNT ]; then
            sleep $BATCH_PAUSE_SEC
        fi
    done
    
    TOTAL_BYTES_WRITTEN=$((TOTAL_BYTES_WRITTEN + FOLDER_BYTES))
    BYTES_SINCE_SYNC=$((BYTES_SINCE_SYNC + FOLDER_BYTES))
    FOLDER_COUNT=$((FOLDER_COUNT + 1))
    FOLDERS_SINCE_PAUSE=$((FOLDERS_SINCE_PAUSE + 1))
    
    # Rate limiting - only if we're going too fast
    BATCH_TIME=$(($(date +%s) - BATCH_START_TIME))
    if [ $BATCH_TIME -gt 0 ]; then
        BATCH_RATE=$((FOLDER_BYTES / 1024 / 1024 / BATCH_TIME))
        if [ $BATCH_RATE -gt $MAX_WRITE_RATE_MB ]; then
            SLEEP_TIME=$(awk "BEGIN {print ($FOLDER_BYTES / 1024 / 1024 / $MAX_WRITE_RATE_MB) - $BATCH_TIME}")
            if [ $(awk "BEGIN {print ($SLEEP_TIME > 0.5)}") -eq 1 ]; then
                echo "[$(date '+%H:%M:%S')] Rate limit: sleeping ${SLEEP_TIME}s (was ${BATCH_RATE} MB/s)"
                sleep "$SLEEP_TIME"
            fi
        fi
    fi
    BATCH_START_TIME=$(date +%s)
    
    # Pause periodically
    if [ $FOLDERS_SINCE_PAUSE -ge $PAUSE_EVERY_FOLDERS ]; then
        echo "[$(date '+%H:%M:%S')] Checkpoint: $FOLDERS_SINCE_PAUSE folders completed"
        sleep $FOLDER_PAUSE_SEC
        FOLDERS_SINCE_PAUSE=0
        show_progress
    fi
    
    # Sync periodically
    if [ $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024)) -ge $SYNC_EVERY_GB ]; then
        echo "[$(date '+%H:%M:%S')] Syncing after $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024)) GB..."
        sync
        BYTES_SINCE_SYNC=0
    fi
    
    # Regular progress updates
    if [ $((FOLDER_COUNT % 10)) -eq 0 ]; then
        show_progress
    fi
done

# Final stats
echo
echo "[$(date '+%H:%M:%S')] Generation complete!"
sync

FINAL_TIME=$(date +%s)
FINAL_GB=$(get_disk_usage_gb)
TOTAL_TIME=$((FINAL_TIME - START_TIME))
GENERATED=$((FINAL_GB - STARTING_GB))
FINAL_RATE=$((GENERATED * 1024 / TOTAL_TIME))

echo
echo "=== FINAL STATISTICS ==="
echo "Generated: ${GENERATED} GB in $((TOTAL_TIME / 60)) minutes"
echo "Folders: ${FOLDER_COUNT} | Files: ${TOTAL_FILES}"
echo "Average rate: ${FINAL_RATE} MB/s"
echo "Files/second: $((TOTAL_FILES / TOTAL_TIME))"
echo

df -h "$ROOT_PATH"