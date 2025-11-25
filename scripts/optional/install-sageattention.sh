#!/bin/bash
# SAGE Attention Installation Script
# Optional performance optimization for ComfyUI

set -euo pipefail

# Default version (1.0.6 has prebuilt wheels for stable PyTorch)
SAGEATTENTION_VERSION="${SAGEATTENTION_VERSION:-1.0.6}"

echo "🚀 Installing SAGE Attention..."
echo "   Version: ${SAGEATTENTION_VERSION}"

# SA3 requires custom wheel from GitHub releases
if [[ "${SAGEATTENTION_VERSION}" == "3.0.0" ]] || [[ "${SAGEATTENTION_VERSION}" == 3.* ]]; then
    # Auto-detect Python version and select correct wheel
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")

    if [[ -n "${SAGEATTENTION3_WHEEL_URL:-}" ]]; then
        # User provided custom wheel URL
        SA3_WHEEL_URL="${SAGEATTENTION3_WHEEL_URL}"
    elif [[ "${PYTHON_VERSION}" == "311" ]]; then
        # Python 3.11 (production)
        SA3_WHEEL_URL="https://github.com/HeapsGo0d/ignition/releases/download/v3.7.4-sageattention3/sageattn3-1.0.0-cp311-cp311-linux_x86_64.whl"
    elif [[ "${PYTHON_VERSION}" == "313" ]]; then
        # Python 3.13 (experimental)
        SA3_WHEEL_URL="https://github.com/HeapsGo0d/ignition/releases/download/v3.7.4-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl"
    else
        echo "⚠️  Python ${PYTHON_VERSION} not supported for SA3 (needs 3.11 or 3.13)"
        echo "   Falling back to v1.0.6..."
        SAGEATTENTION_VERSION="1.0.6"
    fi

    if [[ "${SAGEATTENTION_VERSION}" == "3.0.0" ]]; then
        echo "   Detected SA3 request - auto-selected Python ${PYTHON_VERSION} wheel"
        echo "   Wheel: ${SA3_WHEEL_URL}"

        if pip install "${SA3_WHEEL_URL}" 2>&1 | tee /tmp/sageattention-install.log; then
            echo "✅ SAGE Attention 3 installed successfully"

            # Verify import works
            if python3 -c "import sageattention" 2>/dev/null; then
                echo "✅ SAGE Attention import verification passed"
                exit 0
            else
                echo "⚠️  SAGE Attention installed but import failed"
                exit 1
            fi
        else
            echo "❌ Failed to install SAGE Attention 3 from wheel"
            echo "   Falling back to v1.0.6..."
            SAGEATTENTION_VERSION="1.0.6"
            # Continue to normal installation below
        fi
    fi
fi

# Normal PyPI installation for v1.0.6 and other versions
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
