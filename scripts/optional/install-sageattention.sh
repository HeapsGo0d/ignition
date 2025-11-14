#!/bin/bash
# SAGE Attention Installation Script
# Optional performance optimization for ComfyUI

set -euo pipefail

# Default version (1.0.6 has prebuilt wheels for stable PyTorch)
SAGEATTENTION_VERSION="${SAGEATTENTION_VERSION:-1.0.6}"

echo "🚀 Installing SAGE Attention..."
echo "   Version: ${SAGEATTENTION_VERSION}"

# Try to install sageattention
if pip install "sageattention==${SAGEATTENTION_VERSION}" 2>&1 | tee /tmp/sageattention-install.log; then
    echo "✅ SAGE Attention ${SAGEATTENTION_VERSION} installed successfully"

    # Verify import works
    if python3 -c "import sageattention" 2>/dev/null; then
        echo "✅ SAGE Attention import verification passed"
    else
        echo "⚠️  SAGE Attention installed but import failed - may not work at runtime"
        exit 1
    fi
else
    echo "❌ Failed to install SAGE Attention ${SAGEATTENTION_VERSION}"
    echo "   Check /tmp/sageattention-install.log for details"
    echo ""
    echo "   Common issues:"
    echo "   - Version 2.2.0+ requires building from source (no wheels)"
    echo "   - Building requires CUDA toolkit and matching PyTorch version"
    echo "   - Try SAGEATTENTION_VERSION=1.0.6 for prebuilt wheels"
    exit 1
fi

echo ""
echo "📌 To enable SAGE Attention in ComfyUI:"
echo "   Set environment variable: ENABLE_SAGEATTENTION=1"
echo "   This will add --use-sage-attention to COMFY_FLAGS"
