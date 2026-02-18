# 🚀 Ignition - Dynamic ComfyUI for RunPod

**Simplicity · Elegance · Functional**

Ignition is a RunPod-optimized Docker container that automatically downloads and configures models for ComfyUI at runtime. Built for RTX 5090 performance with PyTorch nightly, robust atomic file operations, and supervisor-based restart architecture.

## ✨ Features

### Core Capabilities
- **🎨 Dynamic Model Loading**: Specify models via environment variables, download on startup
- **⚡ Parallel Downloads**: Efficient concurrent downloading from CivitAI and HuggingFace
- **🔒 Atomic File Operations**: Robust download → verify → move → cleanup prevents corruption
- **🔄 Safe Restart Architecture**: Supervisor loop enables in-place restarts without data loss
- **💾 Flexible Storage**: Ephemeral (fast) or persistent (cached) model storage

### Built-in Optimizations (v3.7.0+)
- **🎛️ Manager UI Enabled by Default**: Full ComfyUI-Manager access with offline mode (no 5-min delay)
- **📦 Performance Plugins Pre-installed**: ComfyUI-Custom-Scripts, Crystools, Various included
- **⚡ SAGE Attention Ready**: Optional runtime or build-time SageAttention support
- **🚀 PyTorch Nightly + CUDA 12.8**: Optimized for RTX 5090 Blackwell architecture

### Developer-Friendly
- **📁 Interactive Template Creator**: `template.sh` with smart model presets (FLUX, Qwen, custom)
- **🔐 Integrated File Browser**: Web-based file management on port 8080
- **📊 Progress Monitoring**: Real-time download progress and system status logging
- **🔒 Privacy Lite**: Automatic telemetry blocking and connection monitoring

## 🚀 Quick Start

### Automated Template Creation

Use the included script to create a pre-configured RunPod template with interactive prompts:

#### **Option 1: Local File Generation (Default)**
```bash
./template.sh
```

#### **Option 2: Direct API Deployment**
```bash
export RUNPOD_API_KEY="your_runpod_api_key_here"
./template.sh --deploy
```

**Interactive Prompts Guide:**

1. **Version Selection**: Enter tag (e.g., `v3.7.0`) or `latest`
2. **Model Preset**: Choose from 6 smart presets:
   - FLUX.1-dev (best quality, ~70s/gen)
   - FLUX.1-schnell (fast, ~7s/gen)
   - Qwen-Image (generation, excellent text rendering)
   - Qwen-Image-Edit (editing, inpainting)
   - Qwen-Image + Edit (both capabilities)
   - Custom (manual entry)
3. **SageAttention**: Select performance optimization level:
   - Disabled (default, no performance boost)
   - v1.0.6 stable (~15-20% speedup, runtime install)
   - SA3 experimental (~25-30% speedup, requires custom build)
4. **Security & Storage**: Configure passwords and storage preferences

**Both modes generate:**
- Pre-configured RunPod template with your settings
- Deployment documentation (RUNPOD_USAGE.md)
- API mode creates template directly in your RunPod account

### Manual Docker Run Example

```bash
docker run -d \
  --gpus all \
  -p 8188:8188 \
  -p 8080:8080 \
  -e CIVITAI_MODELS="123456,789012" \
  -e HUGGINGFACE_MODELS="flux1-dev,clip_l,t5xxl_fp16,ae" \
  -e CIVITAI_TOKEN="your_token" \
  -e ENABLE_SAGEATTENTION="true" \
  heapsgo0d/ignition-comfyui:v3.7.0
```

## 📋 Environment Variables

### Model Sources
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `CIVITAI_MODELS` | Comma-separated CivitAI version IDs | `""` | `"123456,789012"` |
| `CIVITAI_LORAS` | CivitAI LoRA version IDs | `""` | `"345678,901234"` |
| `CIVITAI_VAES` | CivitAI VAE version IDs | `""` | `"567890"` |
| `CIVITAI_FLUX` | CivitAI FLUX model IDs | `""` | `"234567"` |
| `HUGGINGFACE_MODELS` | Comma-separated HF repository IDs | `""` | `"flux1-dev,clip_l,ae"` |

### Authentication
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `CIVITAI_TOKEN` | CivitAI API token (for faster downloads/private models) | `""` | `"your_api_token"` |
| `HF_TOKEN` | HuggingFace API token (for private repos) | `""` | `"hf_your_token"` |

### Configuration
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ENABLE_MANAGER_UI` | Enable ComfyUI-Manager UI | `"true"` | `"true"` or `"false"` |
| `ENABLE_SAGEATTENTION` | Enable SAGE Attention optimization | `"false"` | `"true"` or `"false"` |
| `SAGEATTENTION_VERSION` | SAGE Attention version to install | `"1.0.6"` | `"1.0.6"`, `"3.0.0"` |
| `FILEBROWSER_PASSWORD` | File browser password | `"runpod"` | `"secure_password"` |
| `COMFY_FLAGS` | ComfyUI startup flags | `"--preview-method auto"` | `"--lowvram"` |

## 🔍 Finding Model IDs

### CivitAI Version IDs
1. Go to the model page on CivitAI
2. Click on the version you want
3. The version ID is in the URL: `civitai.com/models/123456?modelVersionId=789012`
4. Use the **version ID** (789012), not the model ID

### HuggingFace Repository IDs
1. Go to the model repository on HuggingFace
2. The repository ID is in the URL: `huggingface.co/black-forest-labs/FLUX.1-dev`
3. Use the full repository path: `black-forest-labs/FLUX.1-dev`

## 🎨 Image Generation Model Presets

The `template.sh` script provides smart presets that automatically configure the correct model combinations:

### FLUX Presets

**Preset 1: FLUX.1-dev (Default)**
- Models: `flux1-dev,clip_l,t5xxl_fp16,ae`
- VRAM: ~16GB
- Generation time: ~70s/image on RTX 5090
- Best for: Highest quality image generation, well-tested workflows, detailed outputs

**Preset 2: FLUX.1-schnell (Fast)**
- Models: `flux1-schnell,clip_l,t5xxl_fp16,ae`
- VRAM: ~16GB
- Generation time: ~7s/image on RTX 5090 (4 steps vs 50 steps)
- Best for: Rapid iteration, previews, real-time workflows, batch generation
- Note: Slightly lower quality than dev but 10x faster

### Qwen Presets

**Preset 3: Qwen-Image (Generation)**
- Models: `qwen_image_fp8,qwen_text_encoder_fp8,qwen_vae,qwen_lightning_8step`
- VRAM: ~20GB (RTX 5090 compatible)
- Generation time: ~34s with 8-step Lightning LoRA, ~71s without
- Best for: Text-to-image generation with exceptional text rendering (English/Chinese), fast generation
- Features: Multiple art styles (photorealistic, anime, etc.), native ComfyUI support

**Preset 4: Qwen-Image-Edit (Editing)**
- Models: `qwen_image_edit_2509_fp8,qwen_text_encoder_fp8,qwen_vae`
- VRAM: ~20GB (RTX 5090 compatible)
- Best for: Image editing, inpainting, object removal, style transfer, background changes
- Note: Uses latest Sept 2025 version with improved person/product editing

**Preset 5: Qwen-Image + Edit (Both)**
- Models: Both generation and editing diffusion models + shared text encoder/VAE + Lightning LoRA
- VRAM: ~20GB per model (load one at a time)
- Best for: Users who want both generation and editing capabilities

**Preset 6: Custom**
- Manually specify model names
- Advanced users only

**Manual Qwen Setup:**
```bash
# Generation only (text-to-image)
HUGGINGFACE_MODELS="qwen_image_fp8,qwen_text_encoder_fp8,qwen_vae,qwen_lightning_8step"

# Editing only (inpainting, object removal)
HUGGINGFACE_MODELS="qwen_image_edit_2509_fp8,qwen_text_encoder_fp8,qwen_vae"

# Both generation & editing
HUGGINGFACE_MODELS="qwen_image_fp8,qwen_image_edit_2509_fp8,qwen_text_encoder_fp8,qwen_vae,qwen_lightning_8step"
```

**Qwen-Image Technical Details:**
- 20B parameter MMDiT models (separate for generation vs editing)
- Optimized FP8 variants for RTX 5090
- Native ComfyUI support (no custom nodes required)
- Generation times (RTX 5090): ~94s first run, ~71s subsequent, ~34s with 8-step Lightning

## ⚡ SAGE Attention (Performance Optimization)

SAGE Attention provides 15-30% faster inference on RTX 30xx/40xx/50xx series GPUs.

### Option 1: Runtime Auto-Install (Recommended)

Set environment variables - SageAttention installs automatically on first startup:

```bash
# Basic setup (uses v1.0.6 stable)
ENABLE_SAGEATTENTION=true

# Advanced: Pin specific version
SAGEATTENTION_VERSION=1.0.6  # Stable, prebuilt wheels
# or
SAGEATTENTION_VERSION=3.0.0  # Experimental SA3 (requires custom build)
```

**How it works:**
- When `ENABLE_SAGEATTENTION=true`, installation happens automatically on first startup
- Subsequent startups detect it's installed and enable it immediately
- No SSH access or manual intervention required

### Option 2: Build-Time SA3 Wheel (Advanced)

For maximum performance (~25-30% speedup), build with a custom-compiled SageAttention3 wheel:

```bash
# Build with SA3 wheel
docker build \
  --build-arg SAGEATTENTION_WHEEL_URL=https://github.com/HeapsGo0d/ignition/releases/download/v3.6.0-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl \
  -t ignition-comfyui:sa3 .

# Then deploy with ENABLE_SAGEATTENTION=true
```

**When to use SA3 wheel:**
- Want maximum performance (~25-30% vs ~15-20% for v1.0.6)
- Willing to manage custom builds
- Have the precompiled wheel available

**Using template.sh:**
- Select "Option 3: Enabled with SA3" during SageAttention prompt
- Script provides build command with correct wheel URL

### Manual Installation (SSH)

```bash
# If needed - usually not required
/workspace/scripts/optional/install-sageattention.sh
```

**Important Notes:**
- Version 1.0.6 (default) has prebuilt wheels for fast installation
- Version 3.0.0 (SA3) requires custom build or prebuilt wheel
- **Warning:** SageAttention 3 is an aggressive optimization that may produce significantly different images compared to standard attention or SageAttention 1/2, even with the same seed and workflow.
- Not all models benefit equally - test with your specific workflows
- Best results with FLUX and SDXL models

## 🎯 What's Included Out of the Box (v3.7.0+)

Ignition now includes essential optimizations **pre-installed** - no manual setup required:

### Manager UI (Enabled by Default)
- **ComfyUI-Manager UI visible** in browser
- **Network mode: offline** (no 5-min startup delay)
- **Full custom node management** capabilities
- To disable: Set `ENABLE_MANAGER_UI=false`

### Performance Plugins (Auto-Installed)
- **ComfyUI-Custom-Scripts**: UI quality-of-life improvements
- **ComfyUI-Crystools**: Utility tools and workflow helpers
- **comfyui-various**: Additional UI extensions
- Plugin versions locked for reproducibility

**Optional plugins** (env-gated, install via SSH if needed):
```bash
# Enable before running install script
export ENABLE_IMPACT_PACK=1      # Advanced segmentation tools
export ENABLE_CONTROLNET_AUX=1   # ControlNet preprocessors

# Then run
/workspace/scripts/optional/install-performance-plugins.sh
```

### File Browser
- **Web-based file management** on port 8080
- **Default login**: admin / (your configured password)
- **Full filesystem access** to container

## 🎯 Optional Enhancements

Additional features available via SSH for specific use cases:

### SDXL VAE (Recommended for SDXL workflows)
```bash
/workspace/scripts/optional/download-sdxl-vae.sh
```

**What it does:**
- Downloads official Stability AI SDXL VAE (335MB)
- Improves image quality for SDXL-based models
- Idempotent - safe to run multiple times

**When to use:**
- Working with SDXL checkpoints
- Notice color banding or quality issues
- Want optimal SDXL performance

## 📁 File Organization

Models are automatically organized into the correct ComfyUI directories:

```
/workspace/ComfyUI/models/
├── checkpoints/        # Main diffusion models
├── loras/             # LoRA adaptations
├── vae/               # VAE models
├── embeddings/        # Textual inversions
├── controlnet/        # ControlNet models
├── upscale_models/    # Super-resolution models
├── diffusion_models/  # FLUX and other diffusion models
├── text_encoders/     # CLIP and T5 encoders
├── clip/              # CLIP models
└── unet/              # UNet models
```

## 🔄 Restarting ComfyUI

Ignition includes a supervisor loop architecture for safe restarts without data loss:

### Soft Restart (Models Preserved)
```bash
/workspace/scripts/restart-comfyui.sh
```

**What happens:**
- ComfyUI process stops
- Supervisor automatically restarts it in 2 seconds
- All models and data remain intact
- Container keeps running

**Use cases:**
- Apply custom node changes
- Reload workflows
- Recover from ComfyUI errors
- Toggle Manager UI (change env var + soft restart)

### Hard Stop (Triggers Nuke)
```bash
/workspace/scripts/stop-pod.sh
```

**What happens:**
- ComfyUI process stops
- Supervisor loop exits
- Container exits
- Nuclear cleanup runs (all data deleted)

**Use cases:**
- Complete pod shutdown
- Fresh start needed
- End of session

### Behavior Comparison

| Action | Command | ComfyUI | Models | Container | Nuke |
|--------|---------|---------|--------|-----------|------|
| **Soft Restart** | `restart-comfyui.sh` | Restarts | ✅ Preserved | Running | ❌ No |
| **Hard Stop** | `stop-pod.sh` | Stops | ❌ Deleted | Exits | ✅ Yes |
| **Crash** | *(automatic)* | Auto-restarts | ✅ Preserved | Running | ❌ No |

## 🎛️ Manager UI & Performance

### Default Configuration (v3.7.0+)

ComfyUI-Manager UI is **enabled by default** for better usability:

- **Manager UI visible** in ComfyUI browser interface
- **Network mode: offline** (fast boot, no 5-min delay)
- **Curated performance plugins** pre-installed
- **Plugin versions locked** for reproducibility

### Customization

**To disable Manager UI:**
```bash
# Set environment variable
ENABLE_MANAGER_UI=false

# Then run soft restart
/workspace/scripts/restart-comfyui.sh
```

**Performance impact:**
- UI enabled (default): ~3-5s load time
- UI disabled: ~1-2s load time
- Network mode offline: No 5-min startup delay (in both cases)

## 🔧 Advanced Configuration

### Private Models
```bash
# Use API tokens for private/premium models
CIVITAI_TOKEN="your_private_token"
HF_TOKEN="hf_your_private_token"
```

### Performance Tuning
```bash
# Low VRAM mode (for cards with limited memory)
export COMFY_FLAGS="--lowvram"

# Enable SAGE Attention
export ENABLE_SAGEATTENTION=true
export SAGEATTENTION_VERSION=1.0.6

# Custom flags (combine as needed)
export COMFY_FLAGS="--preview-method auto --lowvram"
```

### Manual Downloads

Add models to a running pod without restarting:

```bash
# Download a FLUX model (goes to diffusion_models/)
python3 /workspace/scripts/download_civitai_simple.py \
  --flux "618692" \
  --token "$CIVITAI_TOKEN" \
  --output-dir "/workspace/ComfyUI/models"

# Download from HuggingFace
python3 /workspace/scripts/download_huggingface_simple.py \
  flux1-dev,clip_l,ae
```

## 🔒 Privacy & Cleanup

### Privacy Lite

Ignition includes basic privacy protection for telemetry blocking and connection monitoring.

**Features:**
- **Telemetry Blocklist**: Blocks known analytics domains via `/etc/hosts`
- **Connection Monitoring**: Logs external connections to `/tmp/ignition-connections.log`
- **IPv4 + IPv6 Protection**: Blocks both protocols
- **Automatic Setup**: Activates before model downloads

**View Connection Log:**
```bash
/workspace/scripts/privacy/show-connections.sh
```

### Nuclear Cleanup (Nuke)

Deletes all user data and models for a fresh start.

**Automatic (Hard Stop Only):**
```bash
/workspace/scripts/stop-pod.sh  # Triggers nuke automatically
```

**Manual:**
```bash
nuke  # Run anytime via SSH
```

**What Gets Deleted:**
- User data, temp files, cache, config, logs
- Custom node data and caches
- **All downloaded models** in `/workspace/ComfyUI/models/*`

**Safety:** Nuke only runs automatically if ComfyUI successfully started. Failed startups preserve data for debugging.

## ⚡ Performance

Ignition includes targeted optimizations for RTX 5090 and modern GPUs:

**Startup Performance:**
- Manager network mode offline (instant load vs 5-min delay)
- Performance plugins pre-installed (no runtime installation delay)
- Non-blocking initialization

**Inference Performance:**
- **PyTorch nightly with CUDA 12.8** (RTX 5090 Blackwell support)
- **SAGE Attention** available (15-30% speedup when enabled)
- **Customizable** via `COMFY_FLAGS` environment variable

**Generation Times (RTX 5090):**
- FLUX.1-dev: ~70s/image
- FLUX.1-schnell: ~7s/image
- Qwen-Image: ~71s baseline, ~34s with 8-step Lightning
- With SageAttention: ~15-30% faster

## 📟 SSH Command Reference

Quick reference for common operations via SSH:

```bash
# Restart ComfyUI (preserves models)
/workspace/scripts/restart-comfyui.sh

# Stop pod with cleanup (deletes all data)
/workspace/scripts/stop-pod.sh

# Manual nuclear cleanup
nuke

# View connection monitoring logs
/workspace/scripts/privacy/show-connections.sh

# Check ComfyUI status
curl http://localhost:8188/

# View startup logs
tail -f /tmp/ignition_startup.log

# List downloaded models
ls -lh /workspace/ComfyUI/models/checkpoints/
ls -lh /workspace/ComfyUI/models/diffusion_models/

# Optional: Download SDXL VAE
/workspace/scripts/optional/download-sdxl-vae.sh

# Optional: Install additional performance plugins (if env vars set)
/workspace/scripts/optional/install-performance-plugins.sh

# Optional: Manually install SageAttention (usually not needed)
/workspace/scripts/optional/install-sageattention.sh
```

## 🐛 Troubleshooting

### Downloads Never Complete
- Check API tokens are valid
- Verify model IDs exist and are accessible
- Monitor logs: `tail -f /tmp/ignition_startup.log`

### Out of Disk Space
- Use persistent storage to avoid re-downloading
- Check available space in logs on startup
- Consider using smaller models for testing

### ComfyUI Won't Start
- Verify GPU drivers are installed
- Check that models downloaded successfully
- Review startup logs for specific errors

### SageAttention Issues
- Check Python version compatibility
- Verify CUDA version matches (12.8 for RTX 5090)
- Try stable v1.0.6 instead of experimental versions
- Monitor logs during installation

### Startup Process
1. 🔍 System requirements check
2. 🔒 Privacy blocklist setup
3. 💾 Model directory setup
4. 📥 Parallel model downloads
5. 📁 File browser startup (port 8080)
6. 🎨 ComfyUI startup (port 8188)

## 🏗️ Development

### Building Locally

**Basic build:**
```bash
git clone https://github.com/HeapsGo0d/ignition.git
cd ignition
docker build -t ignition-comfyui:dev .
```

**Build with SageAttention3 wheel:**
```bash
docker build \
  --build-arg SAGEATTENTION_WHEEL_URL=https://github.com/HeapsGo0d/ignition/releases/download/v3.6.0-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl \
  -t ignition-comfyui:sa3 .
```

### Testing Downloads
```bash
# Test CivitAI downloader
python3 scripts/download_civitai_simple.py --models "123456"

# Test HuggingFace downloader
python3 scripts/download_huggingface_simple.py flux1-dev,clip_l,ae
```

## 🔐 Security Notes

- Use strong passwords for file browser access
- Store API tokens securely in RunPod secrets
- File browser provides admin access to container filesystem
- Consider network policies for production use

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

---

**🚀 Ready to ignite your ComfyUI experience? Deploy on RunPod today!**
