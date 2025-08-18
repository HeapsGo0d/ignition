# Ignition - ComfyUI with Dynamic Model Loading
# Optimized for RTX 5090 and RunPod deployment

FROM nvidia/cuda:12.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    wget \
    curl \
    unzip \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgoogle-perftools4 \
    libtcmalloc-minimal4 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Install Python dependencies for downloading and ComfyUI
RUN pip3 install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 \
    requests \
    aiohttp \
    aiofiles \
    huggingface-hub \
    tqdm \
    pillow \
    numpy \
    opencv-python \
    psutil

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Install ComfyUI dependencies
RUN cd /workspace/ComfyUI && pip3 install -r requirements.txt

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,vae,upscale_models,embeddings,controlnet}

# Install filebrowser for file management
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Copy our scripts
COPY scripts/ /workspace/scripts/
RUN chmod +x /workspace/scripts/*.sh

# Set environment defaults
ENV CIVITAI_MODELS=""
ENV HUGGINGFACE_MODELS=""
ENV CIVITAI_TOKEN=""
ENV PERSISTENT_STORAGE="none"
ENV FILEBROWSER_PASSWORD="runpod"

# Expose ports
EXPOSE 8188 8080

# Set entrypoint
ENTRYPOINT ["/workspace/scripts/startup.sh"]