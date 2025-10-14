# 🚀 Ignition - Dynamic ComfyUI for RunPod

**Simplicity · Elegance · Functional**

Ignition is a RunPod-optimized Docker container that automatically downloads and configures models for ComfyUI at runtime. Built for RTX 5090 performance with robust, atomic file operations and supervisor-based restart architecture.

## ✨ Features

- **🎨 Dynamic Model Loading**: Specify models via environment variables, download on startup
- **🔄 Safe Restart Architecture**: Supervisor loop enables in-place restarts without data loss
- **🎛️ Runtime Manager UI Toggle**: Enable/disable ComfyUI-Manager UI without rebuilding
- **⚡ Parallel Downloads**: Efficient concurrent downloading from CivitAI and HuggingFace
- **🔒 Atomic File Operations**: Robust download → verify → move → cleanup prevents corruption
- **💾 Persistent Storage**: Optional persistent model storage to survive container restarts
- **🔐 File Browser**: Integrated file manager with configurable authentication
- **📊 Progress Monitoring**: Real-time download progress and system status logging

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

**Both modes generate a complete RunPod template with:**
- Pre-configured environment variables for your models
- Deployment documentation and usage instructions
- API deployment creates the template directly in your RunPod account (no manual upload)

### Manual Configuration

Alternatively, set these environment variables in your RunPod template:

```bash
# Model Sources (comma-separated IDs)
CIVITAI_MODELS="123456,789012,345678"  # CivitAI version IDs
HUGGINGFACE_MODELS="black-forest-labs/FLUX.1-dev"  # HF repository paths

# Optional: API Tokens
CIVITAI_TOKEN="your_civitai_api_token"
HF_TOKEN="your_huggingface_token"

# Optional: Configuration
ENABLE_MANAGER_UI="false"  # true = +2-3s load time for Manager UI
FILEBROWSER_PASSWORD="your_secure_password"
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
  heapsgo0d/ignition-comfyui:v3.4.1-supervisor
```

## 🎯 Optional Enhancements

After your pod starts, you can run these optional scripts via SSH for additional features:

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

### Performance Plugins (UI/Workflow Enhancements)
```bash
/workspace/scripts/optional/install-performance-plugins.sh
```

**What it installs:**
- **ComfyUI-eSuite**: UI quality-of-life improvements
- **ComfyUI-Crystools**: Utility tools and workflow helpers
- **ComfyUI-Various**: Additional UI extensions

**Optional plugins (env-gated):**
```bash
# Enable before running script
export ENABLE_IMPACT_PACK=1      # Advanced segmentation tools
export ENABLE_CONTROLNET_AUX=1   # ControlNet preprocessors
```

**When to use:**
- Want better UI/UX than stock ComfyUI
- Need workflow management features
- Using advanced techniques (ControlNet, segmentation)

**Note:** Both scripts are idempotent and safe to rerun.

## 📋 Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `CIVITAI_MODELS` | Comma-separated CivitAI version IDs | `""` | `"123456,789012"` |
| `CIVITAI_LORAS` | CivitAI LoRA version IDs | `""` | `"345678,901234"` |
| `CIVITAI_VAES` | CivitAI VAE version IDs | `""` | `"567890"` |
| `CIVITAI_FLUX` | CivitAI FLUX model IDs | `""` | `"234567"` |
| `HUGGINGFACE_MODELS` | Comma-separated HF repository IDs | `""` | `"black-forest-labs/FLUX.1-dev"` |
| `CIVITAI_TOKEN` | CivitAI API token | `""` | `"your_api_token"` |
| `HF_TOKEN` | HuggingFace API token | `""` | `"hf_your_token"` |
| `ENABLE_MANAGER_UI` | Enable ComfyUI-Manager UI | `"false"` | `"true"` or `"false"` |
| `FILEBROWSER_PASSWORD` | File browser password | `"runpod"` | `"secure_password"` |
| `COMFYUI_PORT` | ComfyUI web interface port | `"8188"` | `"8188"` |
| `FILEBROWSER_PORT` | File browser port | `"8080"` | `"8080"` |
| `PERSISTENT_STORAGE` | Persistent storage path | `"none"` | `"/workspace/models"` |

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
- Toggle Manager UI (see below)

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

## 🎛️ Manager UI Toggle

ComfyUI-Manager UI can be enabled/disabled at runtime without rebuilding:

### Default: Disabled (Instant Loads)
```bash
ENABLE_MANAGER_UI="false"  # Default
```
- ComfyUI loads instantly (~1-2s)
- Manager backend still installed
- No browser UI for custom nodes

### Enable: Manager UI Available
```bash
ENABLE_MANAGER_UI="true"
```
- ComfyUI loads in ~3-5s (+2-3s overhead)
- Full Manager UI in browser
- Install/manage custom nodes visually

**To toggle after deployment:**
1. Update environment variable in RunPod
2. Run soft restart: `/workspace/scripts/restart-comfyui.sh`
3. Manager UI will be enabled/disabled on next load

## 💾 Storage Options

### Ephemeral (Default)
- `PERSISTENT_STORAGE="none"`
- Models download fresh each container start
- Fastest startup for one-time use
- No storage requirements

### Persistent Storage
- `PERSISTENT_STORAGE="/workspace/models"`
- Models persist between container restarts
- Faster subsequent startups
- Requires network volume or persistent disk

## 🔧 Advanced Configuration

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

### Performance Tuning
```bash
# Low VRAM mode (for cards with limited memory)
export COMFY_FLAGS="--lowvram --use-sage-attention"

# Disable SAGE temporarily (troubleshooting)
export COMFY_FLAGS="--preview-method auto"

# Minimal flags (fastest startup)
export COMFY_FLAGS=""
```

## 🔒 Privacy & Cleanup

### Privacy Lite

Ignition includes basic privacy protection for telemetry blocking and connection monitoring.

**Features:**
- **Telemetry Blocklist**: Blocks known analytics domains (CivitAI, Stability AI, Google Analytics, PostHog, etc.) via `/etc/hosts`
- **Connection Monitoring**: Logs external connections every 2 minutes to `/tmp/ignition-connections.log`
- **IPv4 + IPv6 Protection**: Blocks both protocols to prevent bypass
- **Graceful Degradation**: Continues if `/etc/hosts` is read-only

**View Connection Log:**
```bash
/workspace/scripts/privacy/show-connections.sh
```

**Automatic Setup:** Privacy protection activates automatically on container start before any model downloads occur.

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
- User data: `/workspace/ComfyUI/{user,input,output}/*`
- Temp files: `/tmp/*`, `/workspace/ComfyUI/temp/*`
- Cache: `/root/.cache/*`, `/root/.bash_history`, `/root/.python_history`
- Config: `/root/.config/*`, `/root/.local/share/*`
- Logs: `/workspace/ComfyUI/logs/*`
- Custom node data: `*/cache*`, `*/history*`, `*.db` files
- **Models**: `/workspace/ComfyUI/models/*` (all downloaded models)

**Safety:** Nuke only runs automatically if ComfyUI successfully started. Failed startups preserve data for debugging.

## ⚡ Performance

Ignition includes targeted optimizations for RTX 5090 and modern GPUs:

**Startup Performance:**
- Disabled ComfyUI-Manager network calls at boot (5min → instant)
- Removed web extension loading overhead
- Non-blocking initialization

**Inference Performance:**
- PyTorch nightly with CUDA 12.8 support
- SAGE Attention enabled by default (2-5x faster)
- Customizable via `COMFY_FLAGS` environment variable

**See "🎯 Optional Enhancements" above for additional performance plugins.**

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

# Check what's being blocked
cat /etc/hosts | grep -A 1 "Ignition"

# List downloaded models
ls -lh /workspace/ComfyUI/models/checkpoints/
ls -lh /workspace/ComfyUI/models/diffusion_models/

# Optional: Download SDXL VAE
/workspace/scripts/optional/download-sdxl-vae.sh

# Optional: Install performance plugins
/workspace/scripts/optional/install-performance-plugins.sh
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

### Startup Process
1. 🔍 System requirements check
2. 🔒 Privacy blocklist setup
3. 💾 Model directory setup
4. 📥 Parallel model downloads
5. 📁 File browser startup (port 8080)
6. 🎨 ComfyUI startup (port 8188)

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
