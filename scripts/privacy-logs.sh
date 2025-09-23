#!/bin/bash
# Privacy Log Management - Rotation and Summary Generation
# No cron dependency - triggered by startup and daily via entry script

set -euo pipefail

# Configuration
LOGS_DIR="/workspace/logs/privacy"
PROXY_LOG="$LOGS_DIR/proxy.log"
SUMMARY_DIR="$LOGS_DIR"
MAX_LOG_SIZE="104857600"  # 100MB in bytes
PROXY_LOG_RETENTION=7     # days
SUMMARY_RETENTION=30      # days

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [LOGS-$level] $message"
}

# Ensure log directories exist
setup_log_dirs() {
    mkdir -p "$LOGS_DIR"

    # Create initial proxy log if it doesn't exist
    if [[ ! -f "$PROXY_LOG" ]]; then
        touch "$PROXY_LOG"
        log "INFO" "Created initial proxy log: $PROXY_LOG"
    fi
}

# Rotate proxy log if it exceeds size limit
rotate_proxy_log() {
    if [[ ! -f "$PROXY_LOG" ]]; then
        return 0
    fi

    local log_size=$(stat -f%z "$PROXY_LOG" 2>/dev/null || stat -c%s "$PROXY_LOG" 2>/dev/null || echo "0")

    if [[ "$log_size" -gt "$MAX_LOG_SIZE" ]]; then
        log "INFO" "Rotating proxy log (size: ${log_size} bytes)"

        local timestamp=$(date '+%Y%m%d-%H%M%S')
        local rotated_log="${PROXY_LOG}.${timestamp}"

        # Move current log to rotated name
        mv "$PROXY_LOG" "$rotated_log"

        # Create new empty log
        touch "$PROXY_LOG"

        # Compress rotated log to save space
        if command -v gzip >/dev/null 2>&1; then
            gzip "$rotated_log"
            log "INFO" "Rotated log compressed: ${rotated_log}.gz"
        else
            log "INFO" "Rotated log saved: $rotated_log"
        fi

        return 0
    fi

    log "INFO" "Proxy log size OK (${log_size} bytes, limit: ${MAX_LOG_SIZE})"
}

# Clean old proxy logs
cleanup_proxy_logs() {
    log "INFO" "Cleaning proxy logs older than $PROXY_LOG_RETENTION days"

    # Find and remove old rotated logs
    find "$LOGS_DIR" -name "proxy.log.*" -type f -mtime "+$PROXY_LOG_RETENTION" -delete 2>/dev/null || true

    local cleaned=$(find "$LOGS_DIR" -name "proxy.log.*" -type f -mtime "+$PROXY_LOG_RETENTION" 2>/dev/null | wc -l)
    log "INFO" "Cleaned $cleaned old proxy log files"
}

# Generate daily summary in JSONL format
generate_summary() {
    local summary_date="${1:-$(date '+%Y%m%d')}"
    local summary_file="$SUMMARY_DIR/summary-${summary_date}.jsonl"

    log "INFO" "Generating summary for date: $summary_date"

    if [[ ! -f "$PROXY_LOG" ]]; then
        log "WARN" "No proxy log found for summary generation"
        return 1
    fi

    # Extract today's entries from proxy log
    local today_pattern=$(date -d "$summary_date" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    local temp_file=$(mktemp)

    # Filter log entries for the target date
    grep "^$today_pattern" "$PROXY_LOG" > "$temp_file" 2>/dev/null || true

    if [[ ! -s "$temp_file" ]]; then
        log "INFO" "No log entries found for $summary_date"
        rm -f "$temp_file"
        return 0
    fi

    # Process log entries and generate JSONL summary
    log "INFO" "Processing $(wc -l < "$temp_file") log entries"

    # Parse proxy log format and aggregate by host/action
    python3 -c "
import sys
import json
import re
from collections import defaultdict

# Counters for host/action combinations
counters = defaultdict(int)
timestamp = None

# Process each log line
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    # Extract timestamp (first occurrence)
    if not timestamp:
        match = re.match(r'^(\d{4}-\d{2}-\d{2})', line)
        if match:
            timestamp = match.group(1) + 'T00:00:00Z'

    # Parse different proxy log formats
    # Format: YYYY-MM-DD HH:MM:SS [LEVEL] ACTION host:port - RESULT

    # Extract hostname and action
    host = 'unknown'
    action = 'UNKNOWN'

    # Look for CONNECT hostname:port patterns
    connect_match = re.search(r'CONNECT\s+([^:\s]+)', line)
    if connect_match:
        host = connect_match.group(1)

    # Look for GET/POST hostname patterns
    else:
        get_match = re.search(r'(GET|POST)\s+https?://([^/\s]+)', line)
        if get_match:
            host = get_match.group(2)

    # Determine action (ALLOW/DENY)
    if 'DENY' in line or 'BLOCK' in line or 'block{' in line:
        action = 'DENY'
    elif 'ALLOW' in line or any(word in line for word in ['INFO', 'GET', 'POST', 'CONNECT']):
        action = 'ALLOW'

    # Count this combination
    counters[(host, action)] += 1

# Output JSONL format
if not timestamp:
    timestamp = '$(date -d "$summary_date" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date '+%Y-%m-%dT00:00:00Z')'

for (host, action), count in counters.items():
    entry = {
        'ts': timestamp,
        'dst_host': host,
        'action': action,
        'count': count
    }
    print(json.dumps(entry))
" < "$temp_file" > "$summary_file"

    rm -f "$temp_file"

    if [[ -s "$summary_file" ]]; then
        local entries=$(wc -l < "$summary_file")
        log "INFO" "Generated summary with $entries entries: $summary_file"
    else
        log "WARN" "No summary entries generated"
        rm -f "$summary_file"
    fi
}

# Clean old summary files
cleanup_summaries() {
    log "INFO" "Cleaning summaries older than $SUMMARY_RETENTION days"

    find "$SUMMARY_DIR" -name "summary-*.jsonl" -type f -mtime "+$SUMMARY_RETENTION" -delete 2>/dev/null || true

    local cleaned=$(find "$SUMMARY_DIR" -name "summary-*.jsonl" -type f -mtime "+$SUMMARY_RETENTION" 2>/dev/null | wc -l)
    log "INFO" "Cleaned $cleaned old summary files"
}

# Show recent log activity
show_recent() {
    local lines="${1:-20}"

    echo "=== Recent Proxy Activity ==="
    if [[ -f "$PROXY_LOG" ]]; then
        tail -n "$lines" "$PROXY_LOG"
    else
        echo "No proxy log found"
    fi
}

# Show summary for a specific date
show_summary() {
    local date="${1:-$(date '+%Y%m%d')}"
    local summary_file="$SUMMARY_DIR/summary-${date}.jsonl"

    echo "=== Summary for $date ==="
    if [[ -f "$summary_file" ]]; then
        cat "$summary_file" | python3 -c "
import sys
import json

print('Host\tAction\tCount')
print('----\t------\t-----')

for line in sys.stdin:
    data = json.loads(line.strip())
    print(f\"{data['dst_host']}\t{data['action']}\t{data['count']}\")
"
    else
        echo "No summary found for $date"
        echo "Available summaries:"
        ls "$SUMMARY_DIR"/summary-*.jsonl 2>/dev/null | sed 's/.*summary-/  /' | sed 's/.jsonl$//' || echo "  None"
    fi
}

# Main log management
case "${1:-daily}" in
    "setup")
        setup_log_dirs
        ;;

    "rotate")
        setup_log_dirs
        rotate_proxy_log
        ;;

    "cleanup")
        cleanup_proxy_logs
        cleanup_summaries
        ;;

    "summary")
        setup_log_dirs
        generate_summary "${2:-}"
        ;;

    "daily")
        # Full daily maintenance (called by startup script)
        setup_log_dirs
        rotate_proxy_log
        generate_summary
        cleanup_proxy_logs
        cleanup_summaries
        log "INFO" "Daily log maintenance complete"
        ;;

    "recent")
        show_recent "${2:-20}"
        ;;

    "show")
        show_summary "${2:-}"
        ;;

    "status")
        echo "=== Privacy Log Status ==="
        echo "Logs directory: $LOGS_DIR"
        echo "Proxy log: $PROXY_LOG"

        if [[ -f "$PROXY_LOG" ]]; then
            size=$(stat -f%z "$PROXY_LOG" 2>/dev/null || stat -c%s "$PROXY_LOG" 2>/dev/null || echo "0")
            echo "Proxy log size: $size bytes (limit: $MAX_LOG_SIZE)"
        else
            echo "Proxy log: NOT FOUND"
        fi

        echo ""
        echo "Recent log files:"
        ls -la "$LOGS_DIR"/ 2>/dev/null || echo "  Directory not found"

        echo ""
        echo "Available summaries:"
        ls "$LOGS_DIR"/summary-*.jsonl 2>/dev/null | sed 's/.*summary-/  /' | sed 's/.jsonl$//' || echo "  None"
        ;;

    *)
        echo "Usage: $0 {setup|rotate|cleanup|summary|daily|recent|show|status}"
        echo "  setup     - Create log directories and initial files"
        echo "  rotate    - Rotate proxy log if over size limit"
        echo "  cleanup   - Remove old logs and summaries"
        echo "  summary   - Generate daily summary (optional date YYYYMMDD)"
        echo "  daily     - Full daily maintenance (setup+rotate+summary+cleanup)"
        echo "  recent    - Show recent proxy activity (optional line count)"
        echo "  show      - Show summary for date (optional YYYYMMDD)"
        echo "  status    - Show log system status"
        exit 1
        ;;
esac