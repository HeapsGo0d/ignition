#!/bin/bash
# Privacy Lite - Connection Snapshot
# Captures active network connections to log file

set -euo pipefail

LOG_FILE="/tmp/ignition-connections.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create header on first run
if [[ ! -f "$LOG_FILE" ]]; then
    echo "=== Ignition Privacy Lite - Connection Monitor ===" > "$LOG_FILE"
    echo "Started: $TIMESTAMP" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
fi

# Append timestamp marker
echo "--- Snapshot at $TIMESTAMP ---" >> "$LOG_FILE"

# Capture established connections (exclude localhost)
if command -v ss >/dev/null 2>&1; then
    ss -tn state established '( dport != :8188 and sport != :8188 )' 2>/dev/null | \
        grep -v "127.0.0.1" | \
        grep -v "Local Address" >> "$LOG_FILE" 2>&1 || echo "  No external connections" >> "$LOG_FILE"
else
    netstat -tn 2>/dev/null | \
        grep ESTABLISHED | \
        grep -v "127.0.0.1" | \
        grep -v ":8188" >> "$LOG_FILE" 2>&1 || echo "  No external connections" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"