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

### Minimal Privacy System (Big Red Switch)
| Variable | Description | Default |
|----------|-------------|---------|
| `PRIVACY_ENABLED` | Enable minimal privacy proxy system | `true` |
| `STRICT_MODE` | Deny-by-default networking (0/1) | `0` |
| `PRIVACY_BYPASS` | Break-glass bypass - DANGER (0/1) | `0` |
| `PRIV_ALLOW_UPDATES` | Enable GitHub/PyPI updates window (0/1) | `0` |
| `PROXY_PORT` | Minimal proxy port | `8888` |

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

## Privacy System Operation

### Two-Mode Enforcement
The minimal privacy system operates in two modes:

**Kernel Mode (with NET_ADMIN capability)**:
- ✅ Full iptables enforcement
- ✅ Deny-by-default networking in STRICT_MODE
- ✅ Only allowlisted domains can connect

**User-Space Mode (without capabilities)**:
- ✅ Proxy logging of all connections
- ⚠️ Monitoring-only in STRICT_MODE
- ⚠️ Enforcement relies on proxy environment variables

### Startup Banner
Look for this line in startup logs:
```
🛡️ STRICT_MODE=1 ENFORCEMENT=kernel PROXY=127.0.0.1:8888 ALLOWLIST=5
```

### Requesting Capabilities
To enable kernel mode enforcement:
1. Template must include NET_ADMIN capability request
2. RunPod deployment will have full iptables enforcement
3. STRICT_MODE will block non-allowlisted domains

## Startup Process

1. 🔍 System check
2. 🛡️ Privacy system initialization
3. 💾 Storage setup
4. 📥 Model downloads (parallel)
5. 📁 File browser start (port 8080)
6. 🎨 ComfyUI start (port 8188)

## Troubleshooting

### Logs
- SSH into pod: `ssh root@[pod-id]-ssh.proxy.runpod.net`
- View logs: `tail -f /tmp/ignition_startup.log`

### Common Issues
- **No models downloading**: Check model IDs are correct
- **Out of space**: Use persistent storage or smaller models
- **Slow downloads**: Add API tokens for authentication

### Privacy System Issues
- **STRICT_MODE not enforcing**: Check startup banner for enforcement mode
- **Need iptables enforcement**: Request NET_ADMIN capability in template
- **Proxy not logging**: Check `/workspace/logs/privacy/proxy.log`
- **Update window not working**: Use `/workspace/scripts/privacy-update-window.sh test`

---
**🚀 Ready to create amazing AI art with Ignition!**
