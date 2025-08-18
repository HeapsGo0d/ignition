# 🚀 Ignition RunPod Deployment Guide

## Quick Start

1. **Import Template**:
   - Go to RunPod Templates
   - Click "New Template"
   - Upload the `ignition_template.json` file

2. **Deploy Pod**:
   - Select Ignition template
   - Choose GPU (RTX 5090 recommended)
   - Add network volume if using persistent storage
   - Deploy!

## Access URLs

Once your pod is running:

- **ComfyUI**: `http://[your-pod-id]-8188.proxy.runpod.net`
- **File Browser**: `http://[your-pod-id]-8080.proxy.runpod.net`
  - Username: `admin`
  - Password: ``

## Environment Variables

### Required for Model Downloads
| Variable | Description | Example |
|----------|-------------|---------|
| `CIVITAI_MODELS` | CivitAI model version IDs | `128713,46846,5616` |
| `HUGGINGFACE_MODELS` | HuggingFace repo names | `black-forest-labs/FLUX.1-dev` |

### Optional Authentication  
| Variable | Description | Get Token From |
|----------|-------------|----------------|
| `CIVITAI_TOKEN` | CivitAI API token | https://civitai.com/user/account |
| `HF_TOKEN` | HuggingFace token | https://huggingface.co/settings/tokens |

### Storage Configuration
Storage: Ephemeral volume (0GB; models redownload each start) (Container: 200GB disk, 0GB volume)

## Finding Model IDs

### CivitAI Version IDs
1. Go to model page on CivitAI
2. Click the version you want
3. Copy the `modelVersionId` from URL
4. Example: `civitai.com/models/4384?modelVersionId=128713` → use `128713`

### HuggingFace Repository IDs  
1. Go to model repository
2. Copy the full path from URL
3. Example: `huggingface.co/black-forest-labs/FLUX.1-dev` → use `black-forest-labs/FLUX.1-dev`

## Startup Process

1. 🔍 System check
2. 💾 Storage setup  
3. 📥 Model downloads (parallel)
4. 📁 File browser start (port 8080)
5. 🎨 ComfyUI start (port 8188)

## Troubleshooting

### Logs
- SSH into pod: `ssh root@[pod-id]-ssh.proxy.runpod.net`
- View logs: `tail -f /tmp/ignition_startup.log`

### Common Issues
- **No models downloading**: Check model IDs are correct
- **Out of space**: Use persistent storage or smaller models
- **Slow downloads**: Add API tokens for authentication

---
**🚀 Ready to create amazing AI art with Ignition!**
