# Ignition ComfyUI - Vanilla Baseline (v1.8.0)

**Branch**: `feat/vanilla-refined`
**Base Commit**: `36bf3ce` (Release v1.8.0: Major improvements and refactoring)
**Status**: Pre-privacy/monitoring systems - Clean foundation for architectural review

---

## Purpose

This branch represents the **last stable, production-tested version** of Ignition before the addition of privacy monitoring and ephemeral cleanup systems. It serves as:

1. **Architecture Review Baseline** - Clean codebase for third-party architectural assessment
2. **Reference Implementation** - Proven, working system with minimal complexity
3. **Refinement Target** - Foundation for applying lessons learned with clean design

---

## What This System Does

Ignition is a **RunPod-optimized Docker container** that provides:

### Core Functionality
- **ComfyUI** web interface for Stable Diffusion workflows
- **Dynamic model downloads** at runtime from CivitAI and HuggingFace
- **File Browser** for managing downloaded models and outputs
- **GPU acceleration** with CUDA support (tested on RTX 4090/5090)

### Key Features
- Runtime model downloads (no baked-in models)
- Supports multiple model types: Checkpoints, LoRAs, VAEs, FLUX
- CivitAI API token support for authenticated downloads
- HuggingFace token support for gated models
- Persistent storage via RunPod network volumes
- Simple, single-script startup

---

## Architecture Overview

### Container Structure
```
/workspace/
├── ComfyUI/              # ComfyUI application
│   └── models/           # Symlinked to shared model storage
├── models/               # Shared model storage (persistent)
│   ├── checkpoints/
│   ├── loras/
│   ├── vae/
│   └── diffusion_models/
└── scripts/              # Startup and download scripts
```

### Component Breakdown

#### 1. Dockerfile (`Dockerfile`)
- Base: NVIDIA CUDA PyTorch container
- Python 3.10 with PyTorch 2.6.0+cu118
- ComfyUI and ComfyUI-Manager pre-installed
- File Browser for web-based file management

#### 2. Startup Script (`scripts/startup.sh`)
**Single-responsibility script that:**
- Validates system requirements (GPU, storage, Python)
- Sets up model directory symlinks
- Downloads models (once per model, idempotent)
- Starts File Browser (background)
- Starts ComfyUI (foreground)

#### 3. Download Scripts
**Modular Python scripts with shared utilities:**
- `download_civitai_simple.py` - CivitAI model downloads with API token support
- `download_huggingface_simple.py` - HuggingFace repo/file downloads
- `download_utils.py` - Shared validation, logging, and download utilities
- Uses `aria2c` for reliable multi-connection downloads (8 connections, 8 splits)

#### 4. RunPod Template (`ignition_template.json`)
**Deployment configuration:**
- Port mappings (8188 for ComfyUI, 8080 for File Browser)
- Environment variables for model lists and tokens
- Docker Hub image reference
- User-configurable settings

---

## Key Design Decisions

### ✅ What Works Well
1. **Single Startup Script** - Simple, linear execution flow
2. **Idempotent Downloads** - Models download once, skip if exist
3. **aria2c for Downloads** - Fast, reliable multi-connection downloads
4. **Shared Utilities** - ~70 lines of duplicate code eliminated (v1.8.0)
5. **Environment-Driven Config** - No hardcoded values, all via env vars
6. **Type Hints & Validation** - Clear contracts, better error messages (v1.8.0)

### 📋 Technical Stack
- **Base Image**: NVIDIA PyTorch CUDA 11.8
- **Python**: 3.10
- **PyTorch**: 2.6.0+cu118 (stable, proven)
- **ComfyUI**: Direct git clone (no comfy-cli wrapper)
- **File Browser**: v2.31.2
- **Download Tool**: aria2c (8 connections, 8 splits)

---

## Current State (v1.8.0)

### What's Included
- ✅ ComfyUI web interface
- ✅ Model downloads (CivitAI + HuggingFace)
- ✅ File Browser
- ✅ GPU support (CUDA 11.8)
- ✅ Persistent storage
- ✅ Type hints and validation
- ✅ Comprehensive error handling

### What's NOT Included
- ❌ Privacy monitoring systems
- ❌ Ephemeral cleanup systems
- ❌ Connection monitoring
- ❌ Activity detection
- ❌ Signal handling complexity
- ❌ Multi-mode operation

---

## File Inventory

### Root Directory
```
Dockerfile                 # Container build definition
README.md                  # User documentation
RUNPOD_USAGE.md           # RunPod-specific usage guide
ignition_template.json    # RunPod template configuration
template.sh               # Template deployment script
example.env               # Environment variable examples
```

### Scripts Directory
```
scripts/
├── startup.sh                      # Main startup orchestration
├── download_models_once.sh         # Legacy download wrapper
├── download_civitai_simple.py      # CivitAI downloader
├── download_huggingface_simple.py  # HuggingFace downloader
└── download_utils.py               # Shared download utilities
```

---

## Environment Variables

### Required
- `COMFYUI_PORT` - ComfyUI web port (default: 8188)
- `FILEBROWSER_PORT` - File browser port (default: 8080)
- `FILEBROWSER_PASSWORD` - File browser auth (default: runpod)

### Optional (Model Downloads)
- `CIVITAI_CHECKPOINTS` - Comma-separated CivitAI model URLs
- `CIVITAI_LORAS` - Comma-separated LoRA URLs
- `CIVITAI_VAES` - Comma-separated VAE URLs
- `CIVITAI_FLUX` - Comma-separated FLUX model URLs
- `HUGGINGFACE_MODELS` - Comma-separated HF repo/file URLs
- `CIVITAI_TOKEN` - CivitAI API token (for gated content)
- `HF_TOKEN` - HuggingFace token (for gated repos)
- `FORCE_MODEL_SYNC` - Re-download all models (default: false)

---

## Startup Flow

```
1. Print Banner (v1.8.0)
2. Print Configuration (env vars)
3. Check System Requirements
   ├── Verify ComfyUI directory exists
   ├── Check GPU availability (nvidia-smi)
   ├── Validate Python installation
   └── Check disk space
4. Setup Storage
   ├── Create model directories
   ├── Symlink ComfyUI/models -> /workspace/models
   └── Ensure persistent storage ready
5. Download Models (if specified)
   ├── Parse environment variables
   ├── Download via aria2c
   └── Validate downloads
6. Start File Browser (background)
7. GPU Preflight Check
8. Start ComfyUI (foreground)
```

---

## Testing

### Manual Testing
1. Deploy to RunPod with template
2. Verify ComfyUI loads at port 8188
3. Verify File Browser loads at port 8080
4. Test model download (CivitAI)
5. Test model download (HuggingFace)
6. Generate image in ComfyUI

### Known Working Configurations
- RTX 4090 (24GB VRAM)
- RTX 5090 (32GB VRAM)
- CUDA 11.8
- Ubuntu 22.04 base
- RunPod network volumes

---

## Review Questions

### For Third-Party Architectural Review

1. **Startup Flow**
   - Is the linear startup flow appropriate?
   - Should we parallelize any operations?
   - Error handling strategy - fail fast vs. graceful degradation?

2. **Download System**
   - Is aria2c the right tool for this?
   - Should we retry failed downloads automatically?
   - How to handle partial downloads?

3. **Storage Architecture**
   - Symlink approach - good or problematic?
   - Model deduplication strategy?
   - Handling storage exhaustion?

4. **Error Handling**
   - Current approach: log and exit with code
   - Should we retry operations?
   - User notification strategy?

5. **Scalability**
   - Single container design - appropriate?
   - How to handle multiple concurrent users?
   - Resource limits and quotas?

6. **Security**
   - Token handling (env vars) - secure enough?
   - File Browser authentication - sufficient?
   - Container isolation concerns?

---

## Success Metrics

This baseline is considered **production-ready** and **stable**:
- ✅ Successfully deploys to RunPod
- ✅ Downloads models reliably
- ✅ ComfyUI functions correctly
- ✅ No critical bugs in v1.8.0 release
- ✅ Clean, maintainable codebase

---

## Next Steps (After Review)

1. Gather architectural feedback from third-party reviewer
2. Document recommended improvements
3. Incrementally apply learnings from privacy/monitoring experiments
4. Keep design simple and maintainable
5. Add only essential features based on real user needs

---

**Last Updated**: 2025-09-30
**Maintainer**: HeapsGo0d
**Review Status**: ⏳ Awaiting third-party architectural review