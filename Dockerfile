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

# Install system dependencies with proper pip upgrade (proven pattern)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core system tools
    curl wget git git-lfs vim jq \
    # Python and development (using system Python 3.10)
    python3 python3-dev python3-venv python3-pip \
    # Media processing
    ffmpeg libgl1-mesa-glx libglib2.0-0 \
    # Download tools
    aria2 \
    # Basic networking (minimal privacy tools)
    iptables iproute2 dnsutils \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && python -m pip install --upgrade pip setuptools wheel \
    && rm -rf /var/lib/apt/lists/*

# Install CUDA-enabled PyTorch (proven pattern - separate for caching)
RUN python -m pip install \
    --index-url https://download.pytorch.org/whl/cu121 \
    torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1

# CUDA sanity check at build time
RUN python -c "import torch; print('PyTorch version:', torch.__version__); print('CUDA available:', torch.cuda.is_available()); print('CUDA version:', torch.version.cuda)"

# Install other Python dependencies separately
RUN python -m pip install \
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