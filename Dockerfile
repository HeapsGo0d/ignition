# Ignition - ComfyUI with Dynamic Model Loading
# Optimized for RTX 5090 and RunPod deployment
# Use multi-stage build with caching optimizations

FROM nvidia/cuda:12.1.1-cudnn-devel-ubuntu22.04 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Install system dependencies with caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev python3-venv \
        curl ffmpeg ninja-build git aria2 git-lfs wget vim \
        libgl1-mesa-glx libglib2.0-0 build-essential gcc \
        software-properties-common && \
    \
    # Create virtual environment with system Python3
    python3 -m venv /opt/venv && \
    \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Set working directory
WORKDIR /workspace

# Install PyTorch with CUDA 12.1 (matching base image)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121

# Core Python tooling  
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install packaging setuptools wheel

# Runtime libraries including comfy-cli
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install pyyaml gdown triton comfy-cli

# Install ComfyUI using comfy-cli  
RUN --mount=type=cache,target=/root/.cache/pip \
    /usr/bin/yes | comfy --workspace /workspace install

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

# Set entrypoint
ENTRYPOINT ["/workspace/scripts/startup.sh"]