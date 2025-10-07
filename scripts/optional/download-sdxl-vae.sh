#!/bin/bash
# Performance Optimization: SDXL VAE Download Script
# Downloads official Stability AI SDXL VAE

set -euo pipefail

COMFY="${COMFY:-/workspace/ComfyUI}"
VAE_DIR="$COMFY/models/vae"
mkdir -p "$VAE_DIR"

cd "$VAE_DIR"

echo "📥 Downloading SDXL VAE..."

if [ ! -f "sdxl_vae.safetensors" ]; then
  curl -L --fail -o sdxl_vae.safetensors \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
  echo "✅ SDXL VAE downloaded from Stability AI"
else
  echo "✅ SDXL VAE already exists (idempotent)"
fi

# Verify size (~335MB expected)
FILE_SIZE=$(stat -c '%s' sdxl_vae.safetensors 2>/dev/null || echo "0")
FILE_SIZE_MB=$((FILE_SIZE / 1048576))

if [ "$FILE_SIZE_MB" -gt 300 ] && [ "$FILE_SIZE_MB" -lt 350 ]; then
  echo "✅ Size verification passed: ${FILE_SIZE_MB}MB"
else
  echo "⚠️  Unexpected size: ${FILE_SIZE_MB}MB (expected ~335MB)"
fi
