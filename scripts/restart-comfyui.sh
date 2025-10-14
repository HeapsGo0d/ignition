#!/bin/bash
# Soft restart - reloads ComfyUI without data loss
set -e

echo "🔄 Restarting ComfyUI..."
pkill -f "python.*main.py" || true
echo "✅ ComfyUI will restart automatically (models preserved)"
echo "   Check status: curl http://localhost:8188/"
