#!/bin/bash
# Hard stop - triggers container exit and nuke cleanup
set -e

echo "🛑 Hard stop initiated..."
echo "⚠️  This will trigger nuclear cleanup (all data deleted)"
touch /tmp/comfyui.stop
pkill -f "python.*main.py" || true
echo "✅ Container will exit and run cleanup"
