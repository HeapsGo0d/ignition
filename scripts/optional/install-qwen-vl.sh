#!/bin/bash
# Qwen-VL Installation Script
# Optional vision-language model support for ComfyUI

set -euo pipefail

# Central paths
COMFY="${COMFY:-/workspace/ComfyUI}"
CNODES="$COMFY/custom_nodes"
MODEL_DIR="$COMFY/models/LLM"
mkdir -p "$CNODES" "$MODEL_DIR"

echo "🔧 Installing Qwen-VL support..."
echo ""

# Clone ComfyUI-QwenVL custom node
cd "$CNODES"

if [ ! -d "ComfyUI-QwenVL" ]; then
  echo "📦 Cloning ComfyUI-QwenVL custom node..."
  git clone --depth 1 https://github.com/1038lab/ComfyUI-QwenVL.git
  echo "✅ Cloned ComfyUI-QwenVL"
else
  echo "✅ ComfyUI-QwenVL already exists"
fi

# Install Python dependencies
if [ -f "ComfyUI-QwenVL/requirements.txt" ]; then
  echo "📦 Installing Python dependencies..."
  python3 -m pip install -q -r ComfyUI-QwenVL/requirements.txt
  echo "✅ Dependencies installed"
else
  echo "⚠️  No requirements.txt found, skipping pip install"
fi

# Create model directory
mkdir -p "$MODEL_DIR/Qwen-VL"
echo "✅ Model directory created: $MODEL_DIR/Qwen-VL"

echo ""
echo "🎉 Qwen-VL installation complete!"
echo ""
echo "📌 Usage:"
echo "   • Restart ComfyUI to load the custom node"
echo "   • Models auto-download from HuggingFace on first use"
echo "   • Recommended for RTX 5090: Qwen2-VL-7B-Instruct (~15GB)"
echo "   • Faster alternative: Qwen2-VL-2B-Instruct (~4GB)"
echo ""
echo "📌 To restart ComfyUI:"
echo "   /workspace/scripts/restart-comfyui.sh"
echo ""
