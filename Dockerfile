# Ignition - ComfyUI with Dynamic Model Loading
# Optimized for RTX 5090 and RunPod deployment
# Start with PyTorch base and upgrade for RTX 5090 support

FROM pytorch/pytorch:2.4.0-cuda12.1-cudnn9-devel AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    CUDA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg git aria2 git-lfs wget vim \
    libgl1-mesa-glx libglib2.0-0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Upgrade PyTorch to nightly for RTX 5090 support
RUN --mount=type=cache,target=/root/.cache/pip \
    pip uninstall -y torch torchvision torchaudio && \
    pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121

# Runtime libraries and RTX 5090 optimizations
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install pyyaml gdown triton && \
    # Try to install xformers, fallback gracefully if no compatible wheel
    pip install xformers || echo "xformers not available for this PyTorch/CUDA combination" && \
    # Set environment variables for RTX 5090 compatibility
    echo 'export XFORMERS_DISABLED_ON_INCOMPATIBLE=1' >> /etc/environment && \
    echo 'export FLASH_ATTENTION_FORCE_DISABLE=1' >> /etc/environment

# Install ComfyUI directly (more reliable than comfy-cli)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install additional dependencies for Ignition
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        requests \
        aiohttp \
        aiofiles \
        huggingface-hub \
        tqdm \
        pillow \
        numpy \
        opencv-python \
        psutil

FROM base AS final

# Final stage optimizations
RUN python -m pip install opencv-python

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,vae,upscale_models,embeddings,controlnet}

# Install filebrowser for file management
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Copy our scripts
COPY scripts/ /workspace/scripts/
RUN chmod +x /workspace/scripts/*.sh

# Set environment defaults (simplified approach)
ENV CIVITAI_MODELS=""
ENV HUGGINGFACE_MODELS=""
ENV CIVITAI_TOKEN=""
ENV HF_TOKEN=""
ENV FILEBROWSER_PASSWORD="runpod"
ENV COMFYUI_PORT="8188"
ENV FILEBROWSER_PORT="8080"

# Expose ports
EXPOSE 8188 8080

# Add healthcheck that respects syncing phase
HEALTHCHECK --interval=30s --timeout=5s --start-period=45m --retries=120 \
  CMD bash -lc '[ -f /tmp/ignition_syncing ] || curl -fsS http://127.0.0.1:8188/ || exit 1'

# Set entrypoint
ENTRYPOINT ["/workspace/scripts/startup.sh"]