#!/bin/bash
# Download Protector - Monitor aria2c processes and protect downloads
# Part of Ignition Privacy Blocking System

set -euo pipefail

# Configuration
DOWNLOAD_GRACE_PERIOD=${DOWNLOAD_GRACE_PERIOD:-300}  # 5 minutes after aria2c exits
LOG_FILE="/tmp/ignition_download_protector.log"
STATE_FILE="/tmp/ignition_download_state"

# Status indicators
SUCCESS='✅'
INFO='🔍'
DOWNLOAD='📥'
PROTECT='🛡️'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Check if aria2c processes are running
check_aria2c_processes() {
    local count
    count=$(pgrep -f aria2c | wc -l)
    echo "$count"
}

# Get list of active aria2c processes with details
get_aria2c_details() {
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f aria2c | while read -r pid; do
            if [ -n "$pid" ]; then
                local cmd_line
                cmd_line=$(ps -p "$pid" -o args= 2>/dev/null || echo "Unknown")
                echo "PID: $pid - $cmd_line"
            fi
        done
    fi
}

# Check for recent network activity to model sources
check_model_source_activity() {
    local recent_activity=false

    # Check for recent connections to model sources (last 5 minutes)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tn 2>/dev/null | grep -E "(civitai|huggingface)" >/dev/null 2>&1; then
            recent_activity=true
        fi
    fi

    echo "$recent_activity"
}

# Update download state file
update_download_state() {
    local aria2c_count=$1
    local model_activity=$2
    local timestamp=$(date +%s)

    cat > "$STATE_FILE" <<EOF
{
    "timestamp": $timestamp,
    "aria2c_count": $aria2c_count,
    "model_activity": "$model_activity",
    "downloads_active": $([ "$aria2c_count" -gt 0 ] && echo "true" || echo "false"),
    "last_activity": $timestamp
}
EOF
}

# Get current download state
get_download_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"downloads_active": false, "aria2c_count": 0}'
    fi
}

# Check if downloads should be protected
should_protect_downloads() {
    local aria2c_count=$1
    local current_time=$(date +%s)

    # Always protect if aria2c is running
    if [ "$aria2c_count" -gt 0 ]; then
        echo "true"
        return
    fi

    # Check grace period after last aria2c exit
    if [ -f "$STATE_FILE" ]; then
        local last_activity
        last_activity=$(grep -o '"last_activity": [0-9]*' "$STATE_FILE" | cut -d':' -f2 | tr -d ' ')
        if [ -n "$last_activity" ]; then
            local time_since_last=$((current_time - last_activity))
            if [ "$time_since_last" -lt "$DOWNLOAD_GRACE_PERIOD" ]; then
                echo "true"
                return
            fi
        fi
    fi

    echo "false"
}

# Main monitoring loop
monitor_downloads() {
    log "INFO" "$PROTECT Download protector started"
    log "INFO" "Grace period: ${DOWNLOAD_GRACE_PERIOD}s after aria2c exits"

    while true; do
        local aria2c_count
        local model_activity
        local protect_downloads

        aria2c_count=$(check_aria2c_processes)
        model_activity=$(check_model_source_activity)
        protect_downloads=$(should_protect_downloads "$aria2c_count")

        # Update state
        update_download_state "$aria2c_count" "$model_activity"

        # Log status if downloads are active
        if [ "$aria2c_count" -gt 0 ]; then
            log "INFO" "$DOWNLOAD Downloads active: $aria2c_count aria2c processes"
            log "INFO" "$PROTECT Protecting model download domains"
        elif [ "$protect_downloads" = "true" ]; then
            log "INFO" "$PROTECT Grace period active - protecting downloads"
        fi

        # Sleep before next check
        sleep 10
    done
}

# Status reporting
show_status() {
    local state
    local aria2c_count
    local protect_status

    if [ -f "$STATE_FILE" ]; then
        state=$(cat "$STATE_FILE")
        aria2c_count=$(echo "$state" | grep -o '"aria2c_count": [0-9]*' | cut -d':' -f2 | tr -d ' ')
        protect_status=$(should_protect_downloads "$aria2c_count")
    else
        aria2c_count=0
        protect_status="false"
    fi

    echo "=== Download Protection Status ==="
    echo "Active aria2c processes: $aria2c_count"
    echo "Downloads protected: $protect_status"

    if [ "$aria2c_count" -gt 0 ]; then
        echo ""
        echo "Active download processes:"
        get_aria2c_details
    fi

    if [ "$protect_status" = "true" ] && [ "$aria2c_count" -eq 0 ]; then
        local current_time=$(date +%s)
        local last_activity
        last_activity=$(grep -o '"last_activity": [0-9]*' "$STATE_FILE" | cut -d':' -f2 | tr -d ' ')
        local time_since_last=$((current_time - last_activity))
        local remaining=$((DOWNLOAD_GRACE_PERIOD - time_since_last))
        echo "Grace period: ${remaining}s remaining"
    fi
}

# Command line interface
case "${1:-monitor}" in
    "monitor")
        monitor_downloads
        ;;
    "status")
        show_status
        ;;
    "check")
        aria2c_count=$(check_aria2c_processes)
        protect_status=$(should_protect_downloads "$aria2c_count")
        echo "$protect_status"
        ;;
    "details")
        get_aria2c_details
        ;;
    *)
        echo "Usage: $0 {monitor|status|check|details}"
        echo "  monitor - Start continuous monitoring (default)"
        echo "  status  - Show current download protection status"
        echo "  check   - Return true/false if downloads should be protected"
        echo "  details - Show active aria2c process details"
        exit 1
        ;;
esac