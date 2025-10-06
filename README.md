# 🚀 Ignition - Dynamic ComfyUI for RunPod

**Simplicity · Elegance · Functional**

Ignition is a RunPod-optimized Docker container that automatically downloads and configures models for ComfyUI at runtime. Built for RTX 5090 performance with robust, atomic file operations that prevent infinite download loops.

## ✨ Features

- **🎨 Dynamic Model Loading**: Specify models via environment variables, download on startup
- **⚡ Parallel Downloads**: Efficient concurrent downloading from multiple sources
- **🔒 Atomic File Operations**: Robust download → verify → move → cleanup process prevents corruption
- **💾 Persistent Storage Support**: Optional persistent model storage to survive container restarts
- **🔐 Secure File Browser**: Integrated file manager with configurable authentication
- **🏗️ Auto-Build Pipeline**: GitHub Actions automatically builds and tags Docker images
- **📊 Progress Monitoring**: Real-time download progress and system status logging

## 🎯 Supported Model Sources

### CivitAI
- **Models**: Checkpoints, LoRAs, VAEs, Embeddings, ControlNets
- **Specification**: Comma-separated version IDs (e.g., `123456,789012,345678`)
- **Authentication**: Optional API token for faster downloads and private models

### HuggingFace
- **Models**: Flux models, diffusion models, and other Transformers
- **Specification**: Comma-separated repository IDs (e.g., `black-forest-labs/FLUX.1-dev`)
- **Authentication**: Optional HF token for private repositories

## 🚀 Quick Start

### Automated Template Creation

Use the included script to create a pre-configured RunPod template:

#### **Option 1: Local File Generation (Default)**
```bash
./template.sh
```

#### **Option 2: Direct API Deployment**
```bash
export RUNPOD_API_KEY="your_runpod_api_key_here"
./template.sh --deploy
```

**Both modes will:**
- Generate a complete RunPod template JSON
- Set up environment variables for your models
- Create deployment documentation
- Provide usage instructions

**API deployment mode additionally:**
- Creates the template directly in your RunPod account
- No manual upload needed
- Immediate template availability

### Manual RunPod Template Configuration

Alternatively, set these environment variables manually in your RunPod template:

```bash
# Required: Specify models to download
CIVITAI_MODELS="123456,789012,345678"
HUGGINGFACE_MODELS="black-forest-labs/FLUX.1-dev,stabilityai/stable-diffusion-xl-base-1.0"

# Optional: API tokens for authentication
CIVITAI_TOKEN="your_civitai_api_token_here"
HF_TOKEN="your_huggingface_token_here"

# Optional: Storage configuration
PERSISTENT_STORAGE="none"  # or "/workspace/persistent_models"
FILEBROWSER_PASSWORD="your_secure_password"

# Optional: Port configuration
COMFYUI_PORT="8188"
FILEBROWSER_PORT="8080"
```

### Docker Run Example

```bash
docker run -d \
  --gpus all \
  -p 8188:8188 \
  -p 8080:8080 \
  -e CIVITAI_MODELS="123456,789012" \
  -e HUGGINGFACE_MODELS="black-forest-labs/FLUX.1-dev" \
  -e CIVITAI_TOKEN="your_token" \
  -e FILEBROWSER_PASSWORD="secure123" \
  your_username/ignition-comfyui:latest
```

## 📋 Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `CIVITAI_MODELS` | Comma-separated CivitAI version IDs | `""` | `"123456,789012,345678"` |
| `HUGGINGFACE_MODELS` | Comma-separated HF repository IDs | `""` | `"black-forest-labs/FLUX.1-dev"` |
| `CIVITAI_TOKEN` | CivitAI API token | `""` | `"your_api_token"` |
| `HF_TOKEN` | HuggingFace API token | `""` | `"hf_your_token"` |
| `PERSISTENT_STORAGE` | Persistent storage path | `"none"` | `"/workspace/models"` |
| `FILEBROWSER_PASSWORD` | File browser password | `"runpod"` | `"secure_password"` |
| `COMFYUI_PORT` | ComfyUI web interface port | `"8188"` | `"8188"` |
| `FILEBROWSER_PORT` | File browser port | `"8080"` | `"8080"` |

## 📁 File Organization

Models are automatically organized into the correct ComfyUI directories:

```
/workspace/ComfyUI/models/
├── checkpoints/     # Main diffusion models
├── loras/          # LoRA adaptations
├── vae/            # VAE models
├── embeddings/     # Textual inversions
├── controlnet/     # ControlNet models
└── upscale_models/ # Super-resolution models
```

## 🔍 Finding Model IDs

### CivitAI Version IDs
1. Go to the model page on CivitAI
2. Click on the version you want
3. The version ID is in the URL: `civitai.com/models/123456?modelVersionId=789012`
4. Use the **version ID** (789012), not the model ID (123456)

### HuggingFace Repository IDs
1. Go to the model repository on HuggingFace
2. The repository ID is in the URL: `huggingface.co/black-forest-labs/FLUX.1-dev`
3. Use the full repository path: `black-forest-labs/FLUX.1-dev`

## 💾 Storage Options

### Ephemeral (Default)
- `PERSISTENT_STORAGE="none"`
- Models download fresh each container start
- Fastest startup for one-time use
- No storage requirements

### Persistent Storage
- `PERSISTENT_STORAGE="/path/to/storage"`
- Models persist between container restarts
- Faster subsequent startups
- Requires network volume or persistent disk

## 🔧 Advanced Usage

### Multiple Model Types from CivitAI
```bash
# Mix different model types by ID
CIVITAI_MODELS="123456,789012,345678"  # checkpoint,lora,vae
```

### Private Models
```bash
# Use API tokens for private/premium models
CIVITAI_TOKEN="your_private_token"
HF_TOKEN="hf_your_private_token"
```

### Custom Ports
```bash
# Change default ports if needed
COMFYUI_PORT="3000"
FILEBROWSER_PORT="3001"
```

### 🔒 Privacy Lite

Ignition includes basic privacy protection for telemetry blocking and connection monitoring.

**Features**:
- **Telemetry Blocklist**: Blocks known analytics/tracking domains (CivitAI, Stability AI, Google Analytics, etc.) via `/etc/hosts`
- **Connection Monitoring**: Logs external connections every 2 minutes to `/tmp/ignition-connections.log`
- **IPv4 + IPv6 Protection**: Blocks both protocols to prevent bypass
- **Graceful Degradation**: Continues if `/etc/hosts` is read-only

**View Connection Log**:
```bash
# SSH into your pod
/workspace/scripts/privacy/show-connections.sh
```

**Automatic Setup**: Privacy protection activates automatically on container start before any model downloads occur.

### 💣 Nuclear Cleanup (Nuke)

Ignition includes a nuclear cleanup feature that **deletes all user data and models** for a fresh start.

**Automatic**: Runs on clean pod shutdown (after successful ComfyUI start)
```bash
# Stop your pod normally - nuke runs automatically
# Next start will be completely fresh
```

**Manual**: Run anytime via SSH
```bash
# SSH into your pod
nuke

# Output:
# 💣 NUKE: Deleting all user data and models...
# ✅ Nuclear cleanup complete
```

**What Gets Deleted**:
- User data: `/workspace/ComfyUI/{user,input,output}/*`
- Temp files: `/tmp/*`, `/workspace/ComfyUI/temp/*`
- Cache: `/root/.cache/*`, `/root/.bash_history`
- Config: `/root/.config/*`, `/root/.local/share/*`
- Logs: `/workspace/ComfyUI/logs/*`
- **Models**: `/workspace/ComfyUI/models/*` (all downloaded models)

**Safety**: Nuke only runs automatically if ComfyUI successfully started. Failed startups (GPU errors, download failures, etc.) preserve data for debugging.

## Performance Profile

Optimized for sub-30 second startup and instant boot performance.

### Startup Flags
- **Default flags**: `--gpu-only --preview-method auto --use-sage-attention`
- **Customize per-pod**: Override via environment variable
- **Logged on startup**: `[ignition] Startup flags: ${COMFY_FLAGS}`

**Customization Examples**:
```bash
# Low VRAM mode (for cards with limited memory)
export COMFY_FLAGS="--gpu-only --lowvram --use-sage-attention"

# Disable SAGE temporarily (troubleshooting)
export COMFY_FLAGS="--gpu-only --preview-method auto --normalvram"

# High VRAM mode (maximize performance on high-end cards)
export COMFY_FLAGS="--gpu-only --highvram --use-sage-attention"

# Minimal flags (fastest startup, testing)
export COMFY_FLAGS="--gpu-only"
```

### SAGE Attention
- **Enabled automatically** via `--use-sage-attention` startup flag
- **2-5x faster inference** compared to standard attention
- **No separate download needed** - it's a ComfyUI optimization built into PyTorch
- **Works with any model/VAE** - not model-specific

### SDXL VAE
- **Standard SDXL VAE** available as drop-in replacement
- **Works with SAGE Attention** (enabled via startup flag above)
- **Download**: `scripts/download-sdxl-vae.sh`
- **Size**: ~335MB
- **Location**: `/workspace/ComfyUI/models/vae/sdxl_vae.safetensors`

### Curated Plugins
**Core (always installed)**:
- **ComfyUI-eSuite**: Essential utilities for enhanced workflow
- **ComfyUI-Crystools**: Productivity tools and helpers
- **ComfyUI-Various**: Auto Node Layout for clean graphs

**Optional (env-gated)**:
```bash
export ENABLE_IMPACT_PACK=1        # Detailer nodes for refinement
export ENABLE_CONTROLNET_AUX=1     # ControlNet preprocessors
```

### Installation
Run the performance optimization script:
```bash
# Download SDXL VAE
./scripts/download-sdxl-vae.sh

# Install plugins (with optional packs)
export ENABLE_IMPACT_PACK=1
export ENABLE_CONTROLNET_AUX=1
./scripts/install-performance-plugins.sh
```

### Version Locking
- Plugin versions pinned in `plugins.lock` for reproducible builds
- ComfyUI-Manager network mode disabled for instant boot
- Zero FETCH delays on startup

### Expected Performance
- ⚡ **Startup**: <30s (vs 2-3min baseline)
- 🚀 **Boot**: Instant (no network fetches)
- 🔥 **Inference**: 2-5x faster (SAGE Attention)
- 📦 **Reproducible**: Version-locked plugins

## 🐛 Troubleshooting

### Common Issues

**Downloads Never Complete**
- Check API tokens are valid
- Verify model IDs exist and are accessible
- Monitor logs for specific error messages

**Out of Disk Space**
- Use persistent storage to avoid re-downloading
- Check available space: logs show disk usage on startup
- Consider using smaller models for testing

**ComfyUI Won't Start**
- Verify GPU drivers are installed
- Check that models downloaded successfully
- Review startup logs for specific errors

### Debug Mode
View detailed logs during startup:
```bash
# SSH into your RunPod instance
tail -f /tmp/ignition_startup.log
```

### Startup Process
1. 🔍 System requirements check
2. 💾 Storage setup (if persistent)
3. 📥 Parallel model downloads
4. 📁 File browser startup (port 8080)
5. 🎨 ComfyUI startup (port 8188)

## 🏗️ Development

### Building Locally
```bash
git clone https://github.com/your_username/ignition.git
cd ignition
docker build -t ignition-comfyui:dev .
```

### Testing Downloads
```bash
# Test CivitAI downloader
python3 scripts/download_civitai.py --models "123456" --token "your_token"

# Test HuggingFace downloader
python3 scripts/download_huggingface.py --repos "black-forest-labs/FLUX.1-dev"
```

## 🔐 Security Notes

- Use strong passwords for file browser access
- Store API tokens securely in RunPod secrets
- Consider network policies for production use
- File browser provides admin access to container filesystem

## 📝 Version History

- **v1.0**: Initial release with CivitAI and HuggingFace support
- **v1.1**: Enhanced error handling and progress monitoring
- **v1.2**: Added persistent storage and file browser integration

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## 🙋 Support

- **Issues**: [GitHub Issues](https://github.com/your_username/ignition/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your_username/ignition/discussions)
- **RunPod Community**: [RunPod Discord](https://discord.gg/runpod)

---

**🚀 Ready to ignite your ComfyUI experience? Deploy on RunPod today!**
