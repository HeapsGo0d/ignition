#!/usr/bin/env python3
"""
RTX 5090 Blackwell sm_120 Sanity Check
Runtime probe for CUDA compatibility validation
"""

import torch

print("torch", torch.__version__, "cuda", torch.version.cuda)

if torch.cuda.is_available():
    dev = torch.cuda.get_device_name(0)
    cap = torch.cuda.get_device_capability(0)
    print("device:", dev, "capability:", cap)

    # Simple CUDA smoke test
    x = torch.rand(1, device="cuda")
    print("smoke:", x.device)

    # Check for Blackwell (sm_120) support
    if cap >= (12, 0):
        print("✅ Blackwell (sm_120) ready")
    else:
        print("⚠️ Older GPU")

    # Quick matrix operation test
    try:
        a = torch.randn(1000, 1000, device="cuda")
        b = a @ a.T
        torch.cuda.synchronize()
        print("✅ Matrix operations working")
    except Exception as e:
        print("❌ Matrix operation failed:", str(e))

else:
    print("❌ CUDA not available (runtime)")