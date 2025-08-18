# 🚀 Ignition - Dynamic ComfyUI for RunPod

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

```bash
./template.sh
```

This interactive script will:
- Generate a complete RunPod template JSON
- Set up environment variables for your models
- Create deployment documentation
- Provide usage instructions

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