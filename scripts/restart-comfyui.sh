#!/bin/bash
# Soft restart - reloads ComfyUI without data loss

echo "🔄 Restarting ComfyUI..."

# Find and kill the ComfyUI Python process (not the startup script)
# Look for python process running main.py with --listen flag
COMFY_PID=$(pgrep -f "python.*main\.py.*--listen" | head -n1)

if [[ -n "$COMFY_PID" ]]; then
    echo "  • Found ComfyUI PID: $COMFY_PID"
    kill "$COMFY_PID" 2>/dev/null || true
    echo "  • Sent termination signal"
else
    echo "  • No ComfyUI process found (may already be stopped)"
fi

echo "✅ ComfyUI will restart automatically (models preserved)"
echo "   Check status: curl http://localhost:8188/"
