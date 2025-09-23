# Ignition ComfyUI - Clean Refactor
# Minimal CUDA-enabled PyTorch on Ubuntu 22.04 following proven patterns
# Optimized for RTX 5090 and clean architecture

FROM ubuntu:22.04

# Environment setup following proven pattern
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    XDG_CACHE_HOME=/workspace/.cache \
    HF_HOME=/workspace/.cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/workspace/.cache/huggingface

# Set working directory
WORKDIR /workspace

# Install system dependencies (minimal specification for RTX 5090)
# Note: Image will be >1-2GB due to cu128 PyTorch wheels - this is normal for minimal path
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip ca-certificates \
    git curl ffmpeg git-lfs aria2 wget jq \
    libglib2.0-0 \
    psmisc procps iproute2 net-tools dnsutils \
    # Privacy tools and minimal proxy
    iptables vim privoxy tinyproxy \
    && rm -rf /var/lib/apt/lists/*

# Upgrade tooling first
RUN python3 -m pip install --no-cache-dir -U pip setuptools wheel packaging

# Install PyTorch cu128 (RTX 5090 Blackwell sm_120 support)
# Isolated cu128 index - no global PIP_INDEX_URL leaks to later installs
RUN PIP_ONLY_BINARY=:all: python3 -m pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu128 \
    torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1

# Install other Python dependencies with binary protection
RUN PIP_ONLY_BINARY=:all: python3 -m pip install --no-cache-dir \
    requests aiohttp aiofiles huggingface-hub tqdm pillow numpy opencv-python-headless

# Install ComfyUI with pre-filtering (block ALL CUDA-fragile extensions)
RUN echo -e "xformers\nflash-attn\nflash_attn\nflash_attn_2\nonnxruntime-gpu\nonnxruntime" > /tmp/deny.txt && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    grep -v -f /tmp/deny.txt requirements.txt > /tmp/reqs.safe && \
    PIP_ONLY_BINARY=:all: python3 -m pip install --no-cache-dir -r /tmp/reqs.safe

# Install ComfyUI-Manager with same protections
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    grep -v -f /tmp/deny.txt requirements.txt > /tmp/mgr_reqs.safe && \
    PIP_ONLY_BINARY=:all: python3 -m pip install --no-cache-dir -r /tmp/mgr_reqs.safe

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,vae,upscale_models,embeddings,controlnet,diffusion_models,text_encoders,clip,unet}

# Create cache directories
RUN mkdir -p /workspace/.cache/huggingface

# Create minimal privacy system directories and allowlist
RUN mkdir -p /workspace/logs/privacy /workspace/privacy && \
    echo "# Minimal Privacy Allowlist - Evidence-Based Domains Only" > /workspace/privacy/allowlist.txt && \
    echo "# HuggingFace domains" >> /workspace/privacy/allowlist.txt && \
    echo "*.huggingface.co" >> /workspace/privacy/allowlist.txt && \
    echo "*.hf.co" >> /workspace/privacy/allowlist.txt && \
    echo "cdn-lfs.huggingface.co" >> /workspace/privacy/allowlist.txt && \
    echo "# CivitAI domains" >> /workspace/privacy/allowlist.txt && \
    echo "civitai.com" >> /workspace/privacy/allowlist.txt && \
    echo "files.civitai.com" >> /workspace/privacy/allowlist.txt && \
    echo "# NOTE: PyPI domains added only during PRIV_ALLOW_UPDATES=1" >> /workspace/privacy/allowlist.txt

# Install filebrowser
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Copy scripts
COPY scripts/ /workspace/scripts/
RUN chmod +x /workspace/scripts/*.sh

# Environment defaults
ENV CIVITAI_MODELS="" \
    CIVITAI_LORAS="" \
    CIVITAI_VAES="" \
    CIVITAI_FLUX="" \
    HUGGINGFACE_MODELS="" \
    CIVITAI_TOKEN="" \
    HF_TOKEN="" \
    FILEBROWSER_PASSWORD="runpod" \
    COMFYUI_PORT="8188" \
    FILEBROWSER_PORT="8080" \
    PRIVACY_ENABLED="true"

# Minimal Privacy System Configuration
ENV STRICT_MODE="0" \
    PRIVACY_BYPASS="0" \
    PRIV_ALLOW_UPDATES="0" \
    PROXY_PORT="8888"

# HuggingFace Telemetry Controls (Official Kill-switches)
ENV HF_HUB_DISABLE_TELEMETRY="1" \
    HF_HUB_ENABLE_HF_TRANSFER="0" \
    PIP_DISABLE_PIP_VERSION_CHECK="1"

# Debug flags (runtime only - do not set by default):
# SANITY=1              - Enable RTX 5090 Blackwell validation
# CUDA_LAUNCH_BLOCKING=1 - Enable synchronous CUDA for debugging

# Expose ports
EXPOSE 8188 8080

# Healthcheck (with NO_PROXY to avoid polluting privacy logs)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
  CMD NO_PROXY=127.0.0.1,localhost,::1 curl -f http://127.0.0.1:8188/ || exit 1

# Entrypoint
ENTRYPOINT ["/workspace/scripts/startup-clean.sh"]