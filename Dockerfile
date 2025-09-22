# Ignition ComfyUI - Clean Refactor
# Single-stage Dockerfile following kodxana/comfyui-base patterns
# Optimized for RTX 5090 and clean architecture

FROM ubuntu:22.04

# Environment setup
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PIP_NO_CACHE_DIR=1 \
    XDG_CACHE_HOME=/workspace/.cache \
    HF_HOME=/workspace/.cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/workspace/.cache/huggingface

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core system tools
    curl wget git git-lfs vim jq software-properties-common \
    # Media processing
    ffmpeg libgl1-mesa-glx libglib2.0-0 \
    # Download tools
    aria2 \
    # Basic networking (minimal privacy tools)
    iptables iproute2 dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Add Python 3.12 repository and install
RUN add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    && rm -rf /var/lib/apt/lists/*

# Setup Python 3.12 as default and install pip
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --set python3 /usr/bin/python3.12 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# Install core Python packages
RUN python3 -m pip install --upgrade pip setuptools wheel && \
    python3 -m pip install \
    # PyTorch with CUDA 12.8 support for RTX 5090
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 \
    # Core dependencies
    requests aiohttp aiofiles huggingface-hub tqdm pillow numpy opencv-python

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    python3 -m pip install -r requirements.txt

# Install ComfyUI-Manager
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    python3 -m pip install -r requirements.txt

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,vae,upscale_models,embeddings,controlnet,diffusion_models,text_encoders,clip,unet}

# Create cache directories
RUN mkdir -p /workspace/.cache/huggingface

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

# Expose ports
EXPOSE 8188 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
  CMD curl -f http://127.0.0.1:8188/ || exit 1

# Entrypoint
ENTRYPOINT ["/workspace/scripts/startup-clean.sh"]