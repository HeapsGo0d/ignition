# Ignition - ComfyUI with Dynamic Model Loading
# Optimized for RTX 5090 and RunPod deployment
# Using NVIDIA's official PyTorch container (proven RTX 5090 support)

FROM nvcr.io/nvidia/pytorch:24.04-py3 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    CUDA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Set working directory
WORKDIR /workspace

# Install additional system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg git aria2 git-lfs wget vim \
    libgl1-mesa-glx libglib2.0-0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Core Python tooling (PyTorch already included in base image)
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