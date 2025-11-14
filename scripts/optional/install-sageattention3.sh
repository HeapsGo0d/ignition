#!/bin/bash
# SAGE Attention 3 Installation Script
# For Blackwell GPUs with Python 3.13+

set -euo pipefail

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 13 ]; }; then
    echo "❌ SageAttention3 requires Python 3.13+, found $PYTHON_VERSION"
    exit 1
fi

# Wheel URL from environment or default
WHEEL_URL="${SAGEATTENTION3_WHEEL_URL:-https://github.com/HeapsGo0d/ignition/releases/download/v3.6.0-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl}"

echo "🚀 Installing SAGE Attention 3 for Blackwell..."
echo "   Python: $PYTHON_VERSION"
echo "   Wheel URL: $WHEEL_URL"

# Try to install from wheel first
if pip install "$WHEEL_URL" 2>&1 | tee /tmp/sageattention3-install.log; then
    echo "✅ SAGE Attention 3 installed successfully from wheel"
else
    echo "⚠️  Wheel installation failed, attempting to build from source..."

    # Clone and build from source
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    git clone https://github.com/thu-ml/SageAttention.git
    cd SageAttention/sageattention3_blackwell

    # Set build environment variables
    export FAHOPPER_FORCE_BUILD=1
    export TORCH_CUDA_ARCH_LIST="10.0a;12.0a"

    if python3 setup.py install 2>&1 | tee -a /tmp/sageattention3-install.log; then
        echo "✅ SAGE Attention 3 built and installed from source"
    else
        echo "❌ Failed to install SAGE Attention 3"
        echo "   Check /tmp/sageattention3-install.log for details"
        cd /
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    cd /
    rm -rf "$TEMP_DIR"
fi

# Verify import works
if python3 -c "from sageattn3 import sageattn3_blackwell" 2>/dev/null; then
    echo "✅ SAGE Attention 3 import verification passed"
else
    echo "❌ SAGE Attention 3 installed but import failed"
    exit 1
fi

echo ""
echo "📌 To use SAGE Attention 3 in ComfyUI:"
echo "   Set environment variable: ENABLE_SAGEATTENTION3=true"
echo "   Custom nodes can import: from sageattn3 import sageattn3_blackwell"
