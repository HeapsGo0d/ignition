# Ignition - ComfyUI with Dynamic Model Loading
# Optimized for RTX 5090 and RunPod deployment
# Using NVIDIA's official PyTorch container with RTX 5090 support

FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib64:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH \
    CUDA_DEVICE_ORDER=PCI_BUS_ID \
    PIP_NO_CACHE_DIR=1 \
    XDG_CACHE_HOME=/workspace/.cache \
    HF_HOME=/workspace/.cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/workspace/.cache/huggingface

# Set working directory
WORKDIR /workspace

# Install additional system dependencies including aria2 for downloads
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ffmpeg git aria2 git-lfs wget vim \
    iproute2 net-tools \
    libgl1-mesa-glx libglib2.0-0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Core Python tooling (PyTorch already included in base image)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install packaging setuptools wheel

# Remove base image PyTorch to ensure clean nightly installation
RUN pip uninstall -y torch torchvision torchaudio

# Install PyTorch nightly with CUDA 12.8 for RTX 5090 Blackwell support
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --pre --force-reinstall --no-deps \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    pip install --no-deps torchsde

# Verify nightly installation succeeded (build fails if not)
RUN python3 -c "import torch; v=torch.__version__; print(f'✅ PyTorch: {v} CUDA: {torch.version.cuda}'); assert 'dev' in v, f'Expected nightly, got: {v}'"

# Runtime libraries (triton comes with PyTorch nightly)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install pyyaml gdown

# Install ComfyUI directly (more reliable than comfy-cli)
# Filter out torch packages to prevent downgrade from nightly (but keep torchsde)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    grep -v "^torch$" requirements.txt | \
    grep -v "^torchvision$" | \
    grep -v "^torchaudio$" | \
    pip install --no-cache-dir -r /dev/stdin

# Install ComfyUI-Manager for custom node management
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
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

# Optional: Install SageAttention from prebuilt wheel URL
# Allows building with custom-compiled SageAttention3 for better performance
# Example: docker build --build-arg SAGEATTENTION_WHEEL_URL=https://github.com/.../sageattn3.whl
ARG SAGEATTENTION_WHEEL_URL=""
RUN if [ -n "${SAGEATTENTION_WHEEL_URL}" ]; then \
      echo "Installing SageAttention from wheel: ${SAGEATTENTION_WHEEL_URL}" && \
      pip install --no-cache-dir "${SAGEATTENTION_WHEEL_URL}"; \
    else \
      echo "No SageAttention wheel URL provided, will use runtime install if enabled"; \
    fi

FROM base AS final

# Final stage setup

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,vae,upscale_models,embeddings,controlnet,diffusion_models,text_encoders,clip,unet}

# Create HuggingFace cache directory
RUN mkdir -p /workspace/.cache/huggingface

# Install filebrowser for file management
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Copy our scripts
COPY scripts/ /workspace/scripts/
RUN chmod +x /workspace/scripts/*.sh /workspace/scripts/privacy/*.sh && \
    chmod +x /workspace/scripts/restart-comfyui.sh /workspace/scripts/stop-pod.sh

# Install nuke script for nuclear cleanup
COPY scripts/nuke /usr/local/bin/nuke
RUN chmod +x /usr/local/bin/nuke

# Note: Performance plugins are installed at runtime via startup.sh
# This ensures reliable installation with proper volume context

# Set environment defaults (simplified approach)
ENV CIVITAI_MODELS=""
ENV CIVITAI_LORAS=""
ENV CIVITAI_VAES=""
ENV CIVITAI_FLUX=""
ENV HUGGINGFACE_MODELS=""
ENV CIVITAI_TOKEN=""
ENV HF_TOKEN=""
ENV FILEBROWSER_PASSWORD="runpod"
ENV COMFYUI_PORT="8188"
ENV FILEBROWSER_PORT="8080"

# Expose ports
EXPOSE 8188 8080

# Add basic healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
  CMD curl -f http://127.0.0.1:8188/ || exit 1

# Set entrypoint
ENTRYPOINT ["/workspace/scripts/startup.sh"]