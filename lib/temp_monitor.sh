#!/bin/bash
# ==============================================================================
# Temperature Monitoring Module
# ==============================================================================

# Source common functions
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/common.sh"

# Temperature monitoring configuration
TEMP_SENSOR="k10temp-pci-00c3"       # AMD CPU temperature sensor
TEMP_WARNING=75                       # Warning threshold (°C)
TEMP_CRITICAL=85                      # Critical threshold - pause build (°C)
TEMP_RESUME=70                        # Resume build when temp drops to (°C)
TEMP_CHECK_INTERVAL=5                 # Check every N seconds
TEMP_LOG_FILE="/tmp/kernel_build_temp.log"

# Temperature monitoring function
get_cpu_temp() {
    local temp=$(sensors "$TEMP_SENSOR" 2>/dev/null | grep -oP 'Tctl:\s+\+\K[0-9.]+' | head -1)
    if [ -z "$temp" ]; then
        # Fallback: try to get any k10temp reading
        temp=$(sensors 2>/dev/null | grep -oP 'Tctl:\s+\+\K[0-9.]+' | head -1)
    fi
    if [ -z "$temp" ]; then
        temp="0"
    fi
    echo "${temp%.*}"  # Return integer
}

# Background temperature monitor
start_temp_monitor() {
    log "Starting temperature monitor (Sensor: $TEMP_SENSOR)"
    log "  Warning: ${TEMP_WARNING}°C | Critical: ${TEMP_CRITICAL}°C | Resume: ${TEMP_RESUME}°C"
    
    (
        echo "=== Temperature Log Started: $(date) ===" > "$TEMP_LOG_FILE"
        local paused=0
        local max_temp=0
        
        while true; do
            local temp=$(get_cpu_temp)
            local timestamp=$(date '+%H:%M:%S')
            
            # Track max temperature
            if [ "$temp" -gt "$max_temp" ]; then
                max_temp=$temp
            fi
            
            # Log temperature
            echo "[$timestamp] CPU: ${temp}°C (Max: ${max_temp}°C)" >> "$TEMP_LOG_FILE"
            
            # Critical temperature - need to throttle
            if [ "$temp" -ge "$TEMP_CRITICAL" ] && [ "$paused" -eq 0 ]; then
                echo -e "${RED}[THERMAL] ⚠️  CRITICAL: ${temp}°C - Throttling build processes!${NC}"
                echo "[$timestamp] CRITICAL: ${temp}°C - Sending SIGSTOP" >> "$TEMP_LOG_FILE"
                # Send SIGSTOP to bazel processes to pause
                pkill -STOP -f "bazel" 2>/dev/null || true
                paused=1
            # Resume when cooled down
            elif [ "$temp" -le "$TEMP_RESUME" ] && [ "$paused" -eq 1 ]; then
                echo -e "${GREEN}[THERMAL] ✓ Cooled to ${temp}°C - Resuming build${NC}"
                echo "[$timestamp] RESUMED: ${temp}°C - Sending SIGCONT" >> "$TEMP_LOG_FILE"
                pkill -CONT -f "bazel" 2>/dev/null || true
                paused=0
            # Warning temperature
            elif [ "$temp" -ge "$TEMP_WARNING" ] && [ "$paused" -eq 0 ]; then
                echo -e "${YELLOW}[THERMAL] ⚡ Warning: ${temp}°C${NC}"
            fi
            
            sleep "$TEMP_CHECK_INTERVAL"
        done
    ) &
    TEMP_MONITOR_PID=$!
    echo "$TEMP_MONITOR_PID" > /tmp/temp_monitor.pid
}

# Stop temperature monitor
stop_temp_monitor() {
    if [ -f /tmp/temp_monitor.pid ]; then
        local pid=$(cat /tmp/temp_monitor.pid)
        kill "$pid" 2>/dev/null || true
        rm -f /tmp/temp_monitor.pid
        
        # Print temperature summary
        if [ -f "$TEMP_LOG_FILE" ]; then
            local max_temp=$(grep -oP 'Max: \K[0-9]+' "$TEMP_LOG_FILE" | sort -n | tail -1)
            echo -e "${CYAN}[THERMAL] 📊 Build completed. Max temperature: ${max_temp}°C${NC}"
        fi
    fi
}

# Override cleanup to include temperature monitor cleanup
cleanup() {
    stop_temp_monitor
    # Resume any paused processes
    pkill -CONT -f "bazel" 2>/dev/null || true
    # Note: .config is not restored as Bazel generates it from defconfig
}

