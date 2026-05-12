# Ignition — Dynamic ComfyUI for RunPod

**FLUX · Qwen · Dynamic model loading · CUDA 13**

Ignition is a RunPod-optimized Docker image that downloads and configures AI image generation models at startup via environment variables. Built on CUDA 13.0.3 with PyTorch nightly cu130 for RTX 5090 / Blackwell performance.

## What's included

- **ComfyUI** — latest main branch, fresh clone at build time
- **ComfyUI-Manager** — offline mode by default (no 5-minute startup delay)
- **File Browser** — web-based file management on port 8080 (pinned v2.63.3)
- **Supervisor architecture** — in-place ComfyUI restarts without data loss
- **Privacy Lite** — telemetry blocklist + connection monitoring
- **Parallel downloads** — CivitAI and HuggingFace with aria2

## Quick start

### Template creator (recommended)

```bash
./template.sh           # Generate ignition_template.json for manual upload
./template.sh --deploy  # Deploy directly via RunPod API
```

The script prompts you to choose a model preset, set API tokens, and configure storage. Both modes produce `ignition_template.json` and `RUNPOD_USAGE.md`.

### Manual docker run

```bash
docker run -d \
  --gpus all \
  -p 8188:8188 \
  -p 8080:8080 \
  -e HUGGINGFACE_MODELS="flux1-dev,clip_l,t5xxl_fp16,ae" \
  -e CIVITAI_TOKEN="your_token" \
  heapsgo0d/ignition-comfyui:latest
```

## Environment variables

### Model sources

| Variable | Description | Example |
|----------|-------------|---------|
| `HUGGINGFACE_MODELS` | Comma-separated model keys | `flux1-dev,clip_l,t5xxl_fp16,ae` |
| `CIVITAI_MODELS` | CivitAI model version IDs | `"1569593,919063"` |
| `CIVITAI_LORAS` | CivitAI LoRA version IDs | `"182404,445135"` |
| `CIVITAI_VAES` | CivitAI VAE version IDs | `"1674314"` |

### Authentication

| Variable | Description |
|----------|-------------|
| `CIVITAI_TOKEN` | CivitAI API token — required for gated models, speeds up downloads |
| `HF_TOKEN` | HuggingFace token — required for private/gated repos |

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `FILEBROWSER_PASSWORD` | `runpod` | File browser login password |
| `COMFY_FLAGS` | `--preview-method auto --enable-cors-header` | Extra flags passed to ComfyUI |
| `ENABLE_MANAGER_UI` | `true` | Show ComfyUI-Manager UI in browser |
| `FORCE_MODEL_SYNC` | `false` | Exit on download failure instead of continuing |

## Model presets

`template.sh` offers these presets via interactive prompt:

| # | Preset | Models | VRAM | Speed |
|---|--------|--------|------|-------|
| 1 | FLUX.1-dev | `flux1-dev,clip_l,t5xxl_fp16,ae` | ~16GB | ~70s/img |
| 2 | FLUX.1-schnell | `flux1-schnell,clip_l,t5xxl_fp16,ae` | ~16GB | ~7s/img (4 steps) |
| 3 | Qwen-Image | `qwen_image_fp8,qwen_text_encoder_fp8,qwen_vae,qwen_lightning_8step` | ~20GB | ~34s/img |
| 4 | Qwen-Image-Edit | `qwen_image_edit_2509_fp8,qwen_text_encoder_fp8,qwen_vae` | ~20GB | — |
| 5 | Qwen both | Presets 3 + 4 combined | ~20GB | load one at a time |
| 6 | Custom | Manual entry | — | — |

**Qwen-Image** is a 20B MMDiT with native ComfyUI support (no custom nodes). FP8 variants are optimised for RTX 5090. The `qwen_lightning_8step` LoRA reduces generation to ~34s.

**FLUX.1-schnell** is 10× faster than dev at slightly lower quality — good for iteration.

## Finding model IDs

**CivitAI version ID** — from the URL: `civitai.com/models/4384?modelVersionId=128713` → use `128713`

**HuggingFace** — use the short keys defined in `scripts/download_huggingface_simple.py` (e.g. `flux1-dev`, `clip_l`, `ae`, `qwen_image_fp8`)

## Restarting ComfyUI

Ignition runs a supervisor loop so ComfyUI can restart in-place without losing models or stopping the container.

```bash
# Soft restart — ComfyUI restarts in 2s, models preserved
/workspace/scripts/restart-comfyui.sh

# Hard stop — supervisor exits, container stops, nuke runs
/workspace/scripts/stop-pod.sh
```

| Action | ComfyUI | Models | Container | Nuke |
|--------|---------|--------|-----------|------|
| Soft restart | Restarts | ✅ Kept | Running | No |
| Hard stop | Stops | Deleted | Exits | ✅ Yes |
| Crash | Auto-restarts | ✅ Kept | Running | No |

Nuke only runs on a clean hard-stop **after** ComfyUI has successfully started at least once. Failed startups are left intact for debugging.

## SSH quick reference

```bash
tail -f /tmp/ignition_startup.log          # Live startup log
/workspace/scripts/restart-comfyui.sh      # Soft restart ComfyUI
/workspace/scripts/stop-pod.sh             # Hard stop + nuke
nuke                                        # Manual nuclear cleanup
/workspace/scripts/privacy/show-connections.sh  # Connection log

# On-demand downloads (no restart needed)
python3 /workspace/scripts/download_huggingface_simple.py flux1-dev,clip_l,ae
python3 /workspace/scripts/download_civitai_simple.py --models "123456"

# Optional: SDXL VAE
/workspace/scripts/optional/download-sdxl-vae.sh
```

## Model directories

```
/workspace/ComfyUI/models/
├── checkpoints/        SD1.5, SDXL diffusion models
├── loras/              LoRA adaptations
├── vae/                VAE models
├── embeddings/         Textual inversions
├── controlnet/         ControlNet models
├── upscale_models/     Super-resolution models
├── diffusion_models/   FLUX and other flow-matching models
├── text_encoders/      T5, CLIP-L encoders
├── clip/               CLIP models
├── clip_vision/        CLIP vision models
└── unet/               UNet models
```

## Startup sequence

1. System check + GPU detection
2. Privacy blocklist setup
3. Model directory creation
4. Parallel model downloads
5. File browser (port 8080)
6. GPU preflight — verifies PyTorch CUDA
7. ComfyUI-Manager configuration
8. Performance plugins (first run only)
9. ComfyUI (port 8188) under supervisor loop

## CUDA 13 upgrade (v4.0.0)

v4.0.0 moves from `pytorch/pytorch:2.5.1-cuda12.4` + nightly cu128 to:

- **Base image**: `nvidia/cuda:13.0.3-cudnn-runtime-ubuntu24.04`
- **PyTorch**: nightly cu130
- **Build**: single runtime stage — no SA compilation, smaller image
- **Filebrowser**: pinned to v2.63.3 (avoids GitHub API rate-limit on `get.sh`)
- **Manager config path**: updated for ComfyUI-Manager 0.18+

CUDA 13 / cu130 is required for RTX 5090 (Blackwell sm_120) and provides the same compatibility for earlier Ampere/Ada architectures.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Models not downloading | Check IDs are correct; verify tokens; see `tail -f /tmp/ignition_startup.log` |
| Out of disk space | Use persistent network volume; choose smaller models |
| ComfyUI not responding | `restart-comfyui.sh` or check logs |
| File browser unreachable | Check pod proxy URL — port 8080 |

## Building locally

```bash
git clone https://github.com/HeapsGo0d/ignition.git
cd ignition
docker build -t ignition-comfyui:dev .
```

## License

MIT — see LICENSE file.
