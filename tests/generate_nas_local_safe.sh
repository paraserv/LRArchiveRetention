#!/bin/bash
# Safe NAS data generator with ZFS health monitoring and throttling

TARGET_GB=${1:-3072}
ROOT_PATH="/share/LRArchives/TestData"
AVG_FILE_SIZE_MB=35
FILES_PER_FOLDER=75

# Safety parameters
MAX_WRITE_RATE_MB=600  # Throttle to 600 MB/s max
SYNC_EVERY_GB=10       # Sync every 10GB written
HEALTH_CHECK_INTERVAL=30  # Check ZFS health every 30 seconds
MICRO_DELAY_MS=50      # 50ms delay between folders

# ZFS pool detection
get_zfs_pool() {
    # Extract pool name from mount point
    df "$ROOT_PATH" 2>/dev/null | tail -1 | awk '{print $1}' | cut -d'/' -f1
}

# ZFS health monitoring
check_zfs_health() {
    local pool=$(get_zfs_pool)
    if [ -n "$pool" ]; then
        # Check pool status
        local health=$(zpool status -x "$pool" 2>/dev/null | grep -E "(pool|state):" || echo "unknown")
        
        # Check ARC stats (ZFS cache)
        local arc_size=$(cat /proc/spl/kstat/zfs/arcstats 2>/dev/null | grep "^size" | awk '{print $3}')
        local arc_hit_ratio=$(cat /proc/spl/kstat/zfs/arcstats 2>/dev/null | grep -E "^(hits|misses)" | awk '{sum+=$3} END {print (sum>0)?int(100*hits/(hits+misses)):0}')
        
        # Check write throttling
        local write_throttle=$(zpool status "$pool" 2>/dev/null | grep -c "throttle" || echo 0)
        
        echo "ZFS Health: $health | ARC: $((arc_size/1024/1024))MB | Throttle: $write_throttle"
        
        # Return non-zero if unhealthy
        [[ "$health" =~ "ONLINE" ]] || return 1
        [ "$write_throttle" -eq 0 ] || return 2
    fi
    return 0
}

# Safe sync operation
safe_sync() {
    # QNAP-compatible sync
    sync
    # Also sync ZFS transaction groups
    local pool=$(get_zfs_pool)
    [ -n "$pool" ] && zpool sync "$pool" 2>/dev/null
    # Brief pause to let system catch up
    sleep 0.5
}

# Micro-sleep function (cross-platform)
micro_sleep() {
    local ms=$1
    if command -v usleep >/dev/null 2>&1; then
        usleep $((ms * 1000))
    elif [ -e /proc/timer_list ]; then
        # Use read with timeout as alternative
        read -t "0.${ms}" -N 0 2>/dev/null || true
    else
        # Fallback to perl if available
        perl -e "select(undef, undef, undef, $ms/1000);" 2>/dev/null || true
    fi
}

# Rate-limited write function
write_with_throttle() {
    local infile=$1
    local outfile=$2
    local size_mb=$3
    local start_time=$(date +%s.%N)
    
    # Write the file
    dd if="$infile" of="$outfile" bs=1M count="$size_mb" 2>/dev/null
    
    # Calculate time taken and throttle if needed
    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo 1)
    local rate=$(echo "scale=2; $size_mb / $elapsed" | bc 2>/dev/null || echo 0)
    
    # If we're going too fast, add delay
    if [ $(echo "$rate > $MAX_WRITE_RATE_MB" | bc 2>/dev/null || echo 0) -eq 1 ]; then
        local delay=$(echo "scale=3; ($size_mb / $MAX_WRITE_RATE_MB) - $elapsed" | bc 2>/dev/null || echo 0)
        [ $(echo "$delay > 0" | bc 2>/dev/null || echo 0) -eq 1 ] && sleep "$delay"
    fi
}

# Initialize
echo "Safe NAS Data Generator with ZFS Monitoring"
echo "==========================================="
echo "Target: ${TARGET_GB} GB"
echo "Max write rate: ${MAX_WRITE_RATE_MB} MB/s"
echo "Sync interval: Every ${SYNC_EVERY_GB} GB"
echo

# Check initial ZFS health
echo "Initial ZFS health check..."
if ! check_zfs_health; then
    echo "WARNING: ZFS pool health check failed. Proceed with caution."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Calculate requirements
TOTAL_FILES_NEEDED=$((TARGET_GB * 1024 / AVG_FILE_SIZE_MB))
FOLDERS_NEEDED=$((TOTAL_FILES_NEEDED / FILES_PER_FOLDER))
EXISTING_FOLDERS=$(cd "$ROOT_PATH" 2>/dev/null && ls -1 | wc -l || echo 0)
EXISTING_SIZE_GB=$(cd "$ROOT_PATH" 2>/dev/null && du -s . | awk '{print int($1/1024/1024)}' || echo 0)

echo "Existing: ${EXISTING_FOLDERS} folders, ${EXISTING_SIZE_GB} GB"
echo "Need to generate: $((TARGET_GB - EXISTING_SIZE_GB)) GB more"
echo

# Create random data source
RANDOM_FILE="/tmp/random_source_$$"
echo "Creating random data source..."
dd if=/dev/urandom of="$RANDOM_FILE" bs=1M count=50 2>/dev/null  # Smaller buffer

cd "$ROOT_PATH" || exit 1

START_TIME=$(date +%s)
TOTAL_BYTES=0
FOLDER_COUNT=$EXISTING_FOLDERS
LAST_SYNC_BYTES=0
LAST_HEALTH_CHECK=$(date +%s)

# Timestamp generation (same as before)
get_timestamp() {
    DAYS_AGO=$((RANDOM % 1095))
    CURRENT_EPOCH=$(date +%s)
    FOLDER_EPOCH=$((CURRENT_EPOCH - (DAYS_AGO * 86400)))
    DATESTR=$(date -d "@$FOLDER_EPOCH" +%Y%m%d 2>/dev/null || date -r $FOLDER_EPOCH +%Y%m%d 2>/dev/null || echo "20250101")
    TICKS="${FOLDER_EPOCH}0000000"
    echo "${DATESTR}_1_1_1_${TICKS}"
}

# Progress with health status
show_progress() {
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    GB_WRITTEN=$((TOTAL_BYTES / 1024 / 1024 / 1024))
    TOTAL_GB=$((EXISTING_SIZE_GB + GB_WRITTEN))
    
    if [ $ELAPSED -gt 0 ]; then
        RATE_MB=$((TOTAL_BYTES / 1024 / 1024 / ELAPSED))
        
        # Check if we need health check
        if [ $((CURRENT_TIME - LAST_HEALTH_CHECK)) -gt $HEALTH_CHECK_INTERVAL ]; then
            HEALTH_STATUS=$(check_zfs_health 2>&1 | cut -d'|' -f1)
            LAST_HEALTH_CHECK=$CURRENT_TIME
        else
            HEALTH_STATUS="OK"
        fi
        
        printf "\rFolders: %d/%d | Data: %d/%d GB | Rate: %d MB/s | Health: %s    " \
            "$FOLDER_COUNT" "$FOLDERS_NEEDED" "$TOTAL_GB" "$TARGET_GB" "$RATE_MB" "$HEALTH_STATUS"
    fi
}

# Main generation loop with safety features
echo "Starting safe generation..."
while [ $FOLDER_COUNT -lt $FOLDERS_NEEDED ]; do
    FOLDER_NAME=$(get_timestamp)
    mkdir -p "$FOLDER_NAME" 2>/dev/null
    
    # Brief micro-delay between folders
    micro_sleep $MICRO_DELAY_MS
    
    # Generate files in this folder
    FILE_COUNT=$((50 + RANDOM % 51))
    for i in $(seq 1 $FILE_COUNT); do
        FILE_SIZE_MB=$((20 + RANDOM % 31))
        TIMESTR=$(printf "%02d%02d%02d" $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)))
        RANDNUM=$((1000 + RANDOM % 9000))
        FILENAME="${FOLDER_NAME:0:8}_${TIMESTR}_${RANDNUM}.lca"
        
        # Rate-limited write
        write_with_throttle "$RANDOM_FILE" "$FOLDER_NAME/$FILENAME" "$FILE_SIZE_MB"
        
        TOTAL_BYTES=$((TOTAL_BYTES + FILE_SIZE_MB * 1024 * 1024))
    done
    
    FOLDER_COUNT=$((FOLDER_COUNT + 1))
    
    # Periodic sync
    BYTES_SINCE_SYNC=$((TOTAL_BYTES - LAST_SYNC_BYTES))
    if [ $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024)) -ge $SYNC_EVERY_GB ]; then
        echo -e "\n[$(date '+%H:%M:%S')] Syncing after $((BYTES_SINCE_SYNC / 1024 / 1024 / 1024))GB..."
        safe_sync
        LAST_SYNC_BYTES=$TOTAL_BYTES
        
        # Health check after sync
        if ! check_zfs_health >/dev/null 2>&1; then
            echo -e "\nWARNING: ZFS health degraded. Pausing for 30 seconds..."
            sleep 30
            if ! check_zfs_health; then
                echo "ERROR: ZFS health critical. Stopping generation."
                break
            fi
        fi
    fi
    
    # Progress update
    if [ $((FOLDER_COUNT % 5)) -eq 0 ]; then
        show_progress
    fi
    
    # Check target
    CURRENT_TOTAL_GB=$((EXISTING_SIZE_GB + TOTAL_BYTES / 1024 / 1024 / 1024))
    [ $CURRENT_TOTAL_GB -ge $TARGET_GB ] && break
done

# Final sync
echo -e "\nPerforming final sync..."
safe_sync

# Cleanup
rm -f "$RANDOM_FILE"

# Final stats
echo
FINAL_TIME=$(date +%s)
TOTAL_TIME=$((FINAL_TIME - START_TIME))
FINAL_GB=$((TOTAL_BYTES / 1024 / 1024 / 1024))
FINAL_RATE=$((TOTAL_BYTES / 1024 / 1024 / TOTAL_TIME))

echo "=== SAFE GENERATION COMPLETE ==="
echo "New folders created: $((FOLDER_COUNT - EXISTING_FOLDERS))"
echo "New data generated: ${FINAL_GB} GB"
echo "Total time: $((TOTAL_TIME / 60)) minutes"
echo "Average rate: ${FINAL_RATE} MB/s (throttled to max $MAX_WRITE_RATE_MB)"
echo "Total data in TestData: $(du -sh "$ROOT_PATH" 2>/dev/null | cut -f1)"

# Final health check
echo
echo "Final ZFS health check:"
check_zfs_health