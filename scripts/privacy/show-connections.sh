#!/bin/bash
# Privacy Lite - Show Connections
# Display connection monitoring log

set -euo pipefail

LOG_FILE="/tmp/ignition-connections.log"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "❌ No connection log found at $LOG_FILE"
    echo "   Connection monitoring may not have started yet."
    exit 1
fi

echo "📊 Ignition Connection Monitor"
echo "================================"
echo ""
cat "$LOG_FILE"
echo ""
echo "💡 Tip: This log updates every 2 minutes while the container is running"