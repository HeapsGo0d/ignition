#!/bin/bash
# Connection Monitor - Track outbound network connections
# Part of Ignition Privacy Blocking System

set -euo pipefail

# Configuration
LOG_FILE="/tmp/ignition_connections.log"
CONNECTIONS_STATE="/tmp/ignition_connections_state"
MONITORING_ACTIVE="/tmp/ignition_monitoring_active"

# Status indicators
SUCCESS='✅'
ERROR='❌'
WARNING='⚠️'
INFO='🔍'
NETWORK='🌐'
BLOCK='🚫'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Get current activity context from privacy state manager
get_activity_context() {
    local domain="$1"

    # Try to get activity context from privacy state manager
    if command -v python3 >/dev/null 2>&1 && [ -f "/workspace/scripts/privacy_state_manager.py" ]; then
        local context=$(python3 -c "
import sys
sys.path.append('/workspace/scripts')
try:
    from privacy_state_manager import PrivacyStateManager
    manager = PrivacyStateManager()
    status = manager.get_status()

    if 'activities' in status and status['activities']['detection_available']:
        for activity in status['activities']['active_activities']:
            if '$domain' in activity.get('allowed_domains', []):
                print(f\"{activity['activity_type']}:{activity['confidence']:.2f}\")
                sys.exit(0)
    print('none')
except:
    print('error')
" 2>/dev/null)
        echo "$context"
    else
        echo "unavailable"
    fi
}

# Track a new outbound connection with activity context
track_connection() {
    local dest_ip="$1"
    local dest_port="$2"
    local dest_host="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get activity context for this connection
    local activity_context=$(get_activity_context "$dest_host")

    # Enhanced log format with activity context
    echo "$timestamp|$dest_ip|$dest_port|$dest_host|$activity_context" >> "$LOG_FILE"

    # Check if it's a blocked domain
    if is_blocked_domain "$dest_host"; then
        if [ "$activity_context" != "none" ] && [ "$activity_context" != "error" ] && [ "$activity_context" != "unavailable" ]; then
            log "WARNING" "$BLOCK Connection to $dest_host blocked despite activity: $activity_context"
        else
            log "WARNING" "$BLOCK Blocked connection attempt to $dest_host"
        fi
        return 1
    else
        if [ "$activity_context" != "none" ] && [ "$activity_context" != "error" ] && [ "$activity_context" != "unavailable" ]; then
            log "INFO" "$NETWORK Connection to $dest_host ($dest_ip:$dest_port) - Activity: $activity_context"
        else
            log "INFO" "$NETWORK Connection to $dest_host ($dest_ip:$dest_port)"
        fi
        return 0
    fi
}

# Check if a domain should be blocked
is_blocked_domain() {
    local domain="$1"

    # Always blocked domains (telemetry & AI services)
    local blocked_patterns=(
        "analytics"
        "telemetry"
        "tracking"
        "metrics"
        "api.openai.com"
        "googleapis.com"
        "api.blackforestlabs.ai"
        "anthropic.com"
        "cohere.ai"
        "replicate.com"
    )

    for pattern in "${blocked_patterns[@]}"; do
        if echo "$domain" | grep -q "$pattern"; then
            return 0  # Should be blocked
        fi
    done

    return 1  # Not blocked
}

# Check if a domain is always allowed
is_allowed_domain() {
    local domain="$1"

    # Always allowed domains (model sources)
    local allowed_patterns=(
        "civitai.com"
        "huggingface.co"
    )

    for pattern in "${allowed_patterns[@]}"; do
        if echo "$domain" | grep -q "$pattern"; then
            return 0  # Always allowed
        fi
    done

    return 1  # Not in allowed list
}

# Check if domain is startup-only
is_startup_domain() {
    local domain="$1"

    # Startup-only domains
    local startup_patterns=(
        "github.com"
    )

    for pattern in "${startup_patterns[@]}"; do
        if echo "$domain" | grep -q "$pattern"; then
            return 0  # Startup only
        fi
    done

    return 1  # Not startup-only
}

# Monitor network connections using netstat
monitor_netstat() {
    log "INFO" "$NETWORK Starting netstat monitoring"

    while [ -f "$MONITORING_ACTIVE" ]; do
        # Get current established connections
        if command -v netstat >/dev/null 2>&1; then
            netstat -tn 2>/dev/null | grep ESTABLISHED | while read -r line; do
                # Skip empty lines
                [[ -z "$line" ]] && continue

                # Parse netstat output
                local local_addr=$(echo "$line" | awk '{print $4}')
                local remote_addr=$(echo "$line" | awk '{print $5}')

                # Extract remote IP and port (handle both IPv4 and IPv6)
                local remote_ip=""
                local remote_port=""

                if [[ "$remote_addr" =~ ^\[.*\]: ]]; then
                    # IPv6 format [::1]:8080
                    remote_ip=$(echo "$remote_addr" | sed 's/^\[\(.*\)\]:.*/\1/')
                    remote_port=$(echo "$remote_addr" | sed 's/.*\]:\(.*\)/\1/')
                elif [[ "$remote_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
                    # IPv4 format 192.168.1.1:80
                    remote_ip=$(echo "$remote_addr" | cut -d':' -f1)
                    remote_port=$(echo "$remote_addr" | cut -d':' -f2)
                else
                    continue
                fi

                # Skip local connections
                if [[ "$remote_ip" =~ ^127\.|^::1|^localhost|^0\.0\.0\.0 ]]; then
                    continue
                fi

                # Try to resolve hostname with multiple approaches
                local hostname="$remote_ip"

                # Try getent first (fastest and most reliable)
                if command -v getent >/dev/null 2>&1; then
                    local resolved=$(timeout 1 getent hosts "$remote_ip" 2>/dev/null | awk '{print $2}' | head -1)
                    if [[ -n "$resolved" && "$resolved" != "$remote_ip" ]]; then
                        hostname="$resolved"
                    fi
                fi

                # Fallback to nslookup if getent didn't work
                if [[ "$hostname" == "$remote_ip" ]] && command -v nslookup >/dev/null 2>&1; then
                    local resolved=$(timeout 1 nslookup "$remote_ip" 2>/dev/null | grep "name =" | cut -d'=' -f2 | tr -d ' ' | head -1)
                    if [[ -n "$resolved" && "$resolved" != "$remote_ip" ]]; then
                        hostname="$resolved"
                    fi
                fi

                # Track the connection
                track_connection "$remote_ip" "$remote_port" "$hostname"
            done
        fi

        sleep 5
    done
}

# Monitor connections using ss (more modern alternative)
monitor_ss() {
    log "INFO" "$NETWORK Starting ss monitoring"

    while [ -f "$MONITORING_ACTIVE" ]; do
        # Get current established connections
        if command -v ss >/dev/null 2>&1; then
            ss -tn state established 2>/dev/null | tail -n +2 | while read -r line; do
                # Skip empty lines
                [[ -z "$line" ]] && continue

                # Parse ss output - handle IPv4 and IPv6
                local remote_addr=""
                if echo "$line" | grep -q "::ffff:"; then
                    # IPv4-mapped IPv6 address
                    remote_addr=$(echo "$line" | awk '{print $5}' | sed 's/::ffff://')
                else
                    # Regular IPv4 or IPv6
                    remote_addr=$(echo "$line" | awk '{print $5}')
                fi

                # Extract remote IP and port (handle both IPv4 and IPv6)
                local remote_ip=""
                local remote_port=""

                if [[ "$remote_addr" =~ ^\[.*\]: ]]; then
                    # IPv6 format [::1]:8080
                    remote_ip=$(echo "$remote_addr" | sed 's/^\[\(.*\)\]:.*/\1/')
                    remote_port=$(echo "$remote_addr" | sed 's/.*\]:\(.*\)/\1/')
                elif [[ "$remote_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
                    # IPv4 format 192.168.1.1:80
                    remote_ip=$(echo "$remote_addr" | cut -d':' -f1)
                    remote_port=$(echo "$remote_addr" | cut -d':' -f2)
                else
                    continue
                fi

                # Skip local connections
                if [[ "$remote_ip" =~ ^127\.|^::1|^localhost|^0\.0\.0\.0 ]]; then
                    continue
                fi

                # Try to resolve hostname with multiple approaches
                local hostname="$remote_ip"

                # Try getent first (fastest and most reliable)
                if command -v getent >/dev/null 2>&1; then
                    local resolved=$(timeout 1 getent hosts "$remote_ip" 2>/dev/null | awk '{print $2}' | head -1)
                    if [[ -n "$resolved" && "$resolved" != "$remote_ip" ]]; then
                        hostname="$resolved"
                    fi
                fi

                # Fallback to dig if getent didn't work
                if [[ "$hostname" == "$remote_ip" ]] && command -v dig >/dev/null 2>&1; then
                    local resolved=$(timeout 1 dig +short -x "$remote_ip" 2>/dev/null | sed 's/\.$//' | head -1)
                    if [[ -n "$resolved" && "$resolved" != "$remote_ip" ]]; then
                        hostname="$resolved"
                    fi
                fi

                # Track the connection
                track_connection "$remote_ip" "$remote_port" "$hostname"
            done
        fi

        sleep 5
    done
}

# Start monitoring
start_monitoring() {
    # Create monitoring active flag
    touch "$MONITORING_ACTIVE"

    log "INFO" "$NETWORK Connection monitoring started"
    log "INFO" "Log file: $LOG_FILE"

    # Use ss if available, otherwise netstat
    if command -v ss >/dev/null 2>&1; then
        monitor_ss
    elif command -v netstat >/dev/null 2>&1; then
        monitor_netstat
    else
        log "ERROR" "$ERROR No network monitoring tools available (ss or netstat)"
        exit 1
    fi
}

# Stop monitoring
stop_monitoring() {
    if [ -f "$MONITORING_ACTIVE" ]; then
        rm -f "$MONITORING_ACTIVE"
        log "INFO" "$NETWORK Connection monitoring stopped"
    fi
}

# Show recent connections with activity context
show_recent_connections() {
    local count=${1:-20}

    echo "=== Recent Network Connections ==="
    if [ -f "$LOG_FILE" ]; then
        tail -n "$count" "$LOG_FILE" | while IFS='|' read -r timestamp ip port host activity; do
            if [ -n "$timestamp" ]; then
                if [ -n "$activity" ] && [ "$activity" != "none" ] && [ "$activity" != "error" ] && [ "$activity" != "unavailable" ]; then
                    echo "$timestamp -> $host ($ip:$port) [Activity: $activity]"
                else
                    echo "$timestamp -> $host ($ip:$port)"
                fi
            fi
        done
    else
        echo "No connection log found"
    fi
}

# Show connection summary
show_summary() {
    echo "=== Connection Summary ==="

    if [ -f "$LOG_FILE" ]; then
        echo "Total connections logged: $(wc -l < "$LOG_FILE")"
        echo ""
        echo "Top destinations:"
        grep -o '|[^|]*$' "$LOG_FILE" | cut -c2- | sort | uniq -c | sort -nr | head -10
        echo ""
        echo "Recent blocked attempts:"
        grep "Blocked connection" "$LOG_FILE" | tail -5
    else
        echo "No connection data available"
    fi
}

# Real-time monitoring display
show_realtime() {
    log "INFO" "$NETWORK Starting real-time connection monitor"
    log "INFO" "Press Ctrl+C to exit"

    # Start monitoring in background if not already running
    if [ ! -f "$MONITORING_ACTIVE" ]; then
        start_monitoring &
        sleep 2
    fi

    # Display real-time updates
    tail -f "$LOG_FILE" 2>/dev/null | while read -r line; do
        echo "$line"
    done
}

# Command line interface
case "${1:-start}" in
    "start")
        start_monitoring
        ;;
    "stop")
        stop_monitoring
        ;;
    "status")
        if [ -f "$MONITORING_ACTIVE" ]; then
            echo "Connection monitoring is ACTIVE"
        else
            echo "Connection monitoring is STOPPED"
        fi
        ;;
    "recent")
        show_recent_connections "${2:-20}"
        ;;
    "summary")
        show_summary
        ;;
    "realtime"|"live")
        show_realtime
        ;;
    "test")
        # Test domain checking
        echo "Testing domain classification:"
        echo "civitai.com: $(is_allowed_domain "civitai.com" && echo "ALLOWED" || echo "CHECK_FURTHER")"
        echo "api.openai.com: $(is_blocked_domain "api.openai.com" && echo "BLOCKED" || echo "ALLOWED")"
        echo "github.com: $(is_startup_domain "github.com" && echo "STARTUP_ONLY" || echo "CHECK_FURTHER")"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|recent|summary|realtime|test}"
        echo "  start    - Start connection monitoring"
        echo "  stop     - Stop connection monitoring"
        echo "  status   - Check if monitoring is active"
        echo "  recent   - Show recent connections (default: 20)"
        echo "  summary  - Show connection summary and statistics"
        echo "  realtime - Show real-time connection monitoring"
        echo "  test     - Test domain classification"
        exit 1
        ;;
esac