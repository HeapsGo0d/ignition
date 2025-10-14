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
  - Password: `runpod`

## Environment Variables

### Required for Model Downloads
| Variable | Description | Example |
|----------|-------------|---------|
| `CIVITAI_MODELS` | CivitAI model version IDs | `138977,46846,5616` |
| `HUGGINGFACE_MODELS` | HuggingFace model keys | `flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev` |

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
3. Example: For FLUX workflow use `flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev` (complete set with KREA variant)

## Startup Process

1. 🔍 System check
2. 💾 Storage setup  
3. 📥 Model downloads (parallel)
4. 📁 File browser start (port 8080)
5. 🎨 ComfyUI start (port 8188)

## 🔄 Restarting ComfyUI

Ignition includes supervisor architecture for safe restarts:

### Soft Restart (Models Preserved)
```bash
/workspace/scripts/restart-comfyui.sh
```
- Restarts ComfyUI in 2 seconds
- All models and data preserved
- Container keeps running
- Use for: applying changes, toggling Manager UI

### Hard Stop (Triggers Nuke)
```bash
/workspace/scripts/stop-pod.sh
```
- Exits container completely
- Nuclear cleanup deletes all data
- Use for: complete shutdown, fresh start

| Action | Models | Container | Nuke |
|--------|--------|-----------|------|
| Soft Restart | ✅ Preserved | Running | ❌ No |
| Hard Stop | ❌ Deleted | Exits | ✅ Yes |
| Crash | ✅ Preserved | Running | ❌ No |

## 🎛️ Manager UI Toggle

Control ComfyUI-Manager UI at runtime:

- `ENABLE_MANAGER_UI=false` (default): Instant loads (~1-2s)
- `ENABLE_MANAGER_UI=true`: Manager UI available (+2-3s load time)

**To toggle**: Update env var in RunPod, then run soft restart

## Troubleshooting

### Logs
- SSH into pod: `ssh root@[pod-id]-ssh.proxy.runpod.net`
- View logs: `tail -f /tmp/ignition_startup.log`

### Common Issues
- **No models downloading**: Check model IDs are correct
- **Out of space**: Use persistent storage or smaller models
- **Slow downloads**: Add API tokens for authentication
- **ComfyUI not responding**: Run `/workspace/scripts/restart-comfyui.sh`

---
**🚀 Ready to create amazing AI art with Ignition!**
