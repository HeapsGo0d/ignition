#!/bin/bash
# Ignition Startup Script - Simplified Edition
# Uses the same logic as download_models_once.sh for consistency

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="/workspace"
COMFYUI_ROOT="/workspace/ComfyUI"
LOG_FILE="/tmp/ignition_startup.log"

# Set up caches and paths early
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/.cache}"
export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HF_HOME}"
mkdir -p "$HF_HOME" || true

# Consistent Python interpreter
PYBIN="$(command -v python3 || command -v python)"

# Track if ComfyUI successfully started (for nuke on clean shutdown only)
COMFYUI_STARTED=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Environment variable defaults
export CIVITAI_MODELS="${CIVITAI_MODELS:-}"
export CIVITAI_LORAS="${CIVITAI_LORAS:-}"
export CIVITAI_VAES="${CIVITAI_VAES:-}"
export CIVITAI_FLUX="${CIVITAI_FLUX:-}"
export HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-}"
export CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
export HF_TOKEN="${HF_TOKEN:-}"
export FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-runpod}"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export FILEBROWSER_PORT="${FILEBROWSER_PORT:-8080}"
export FORCE_MODEL_SYNC="${FORCE_MODEL_SYNC:-false}"

print_banner() {
    log "INFO" ""
    log "INFO" "╔═══════════════════════════════════════════╗"
    log "INFO" "║         🚀 IGNITION v1.9.2-privacy-lite  ║"
    log "INFO" "║        ComfyUI Dynamic Model Loader      ║"
    log "INFO" "║             SIMPLE EDITION               ║"
    log "INFO" "╚═══════════════════════════════════════════╝"
    log "INFO" ""
}

print_config() {
    log "INFO" "📋 Configuration:"
    log "INFO" "  • CivitAI Models: ${CIVITAI_MODELS:-'None specified'}"
    log "INFO" "  • CivitAI LoRAs: ${CIVITAI_LORAS:-'None specified'}"
    log "INFO" "  • CivitAI VAEs: ${CIVITAI_VAES:-'None specified'}"
    log "INFO" "  • CivitAI FLUX: ${CIVITAI_FLUX:-'None specified'}"
    log "INFO" "  • HuggingFace Models: ${HUGGINGFACE_MODELS:-'None specified'}"
    log "INFO" "  • Storage: RunPod volume (/workspace)"
    log "INFO" "  • ComfyUI Port: $COMFYUI_PORT"
    log "INFO" "  • File Browser Port: $FILEBROWSER_PORT"
    log "INFO" ""
}

check_system() {
    log "INFO" "🔍 Checking system requirements..."
    
    if [[ ! -d "$COMFYUI_ROOT" ]]; then
        log "ERROR" "ComfyUI directory not found: $COMFYUI_ROOT"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/download_civitai_simple.py" ]] || [[ ! -f "$SCRIPT_DIR/download_huggingface_simple.py" ]] || [[ ! -x "$SCRIPT_DIR/download_models_once.sh" ]]; then
        log "ERROR" "Download scripts not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Check GPU availability
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 || echo "Unknown")
        log "INFO" "  • GPU Detected: $GPU_INFO"
    else
        log "WARN" "  • No NVIDIA GPU detected"
    fi
    
    log "INFO" "✅ System requirements check complete"
    log "INFO" ""
}

setup_storage() {
    log "INFO" "💾 Setting up model directories..."
    
    mkdir -p "$COMFYUI_ROOT/models"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models,diffusion_models,text_encoders,clip,unet}
    
    for model_type in checkpoints loras vae embeddings controlnet upscale_models diffusion_models text_encoders clip unet; do
        log "INFO" "  • Created $model_type directory"
    done
    
    log "INFO" "✅ Model directories ready"
    log "INFO" ""
}

# Use the download_models_once.sh script for downloads
download_models() {
    if [[ -z "$CIVITAI_MODELS$CIVITAI_LORAS$CIVITAI_VAES$CIVITAI_FLUX$HUGGINGFACE_MODELS" ]]; then
        log "INFO" "📥 No models requested; skipping downloads."
        log "INFO" ""
        return
    fi

    log "INFO" "📥 Starting model downloads..."
    if bash "$SCRIPT_DIR/download_models_once.sh"; then
        log "INFO" "✅ Model downloads completed"
    else
        if [[ "${FORCE_MODEL_SYNC}" == "true" ]]; then
            log "ERROR" "Model download failed and FORCE_MODEL_SYNC=true"
            exit 3
        fi
        log "WARN" "⚠️ Some model downloads may have failed, continuing"
    fi
    log "INFO" ""
}

start_filebrowser() {
    log "INFO" "📁 Starting file browser..."
    
    local config_dir="$WORKSPACE_ROOT/.filebrowser"
    local db_path="$config_dir/filebrowser.db"
    mkdir -p "$config_dir"
    
    if [[ ! -f "$db_path" ]]; then
        log "INFO" "  • Initializing filebrowser database..."
        filebrowser -d "$db_path" config init
        
        local fb_password="$FILEBROWSER_PASSWORD"
        if [[ ${#fb_password} -lt 12 ]]; then
            fb_password="ignition_${FILEBROWSER_PASSWORD}_2024"
        fi
        
        filebrowser -d "$db_path" config set --auth.method=json --auth.header=""
        filebrowser -d "$db_path" users add admin "$fb_password" --perm.admin
        
        log "INFO" "  • Admin user created (password set; not logged)"
    fi
    
    log "INFO" "  • Starting filebrowser on port $FILEBROWSER_PORT"
    filebrowser \
        --database "$db_path" \
        --root "$WORKSPACE_ROOT" \
        --address "0.0.0.0" \
        --port "$FILEBROWSER_PORT" &
    
    log "INFO" "  • Login: admin (password not shown in logs)"
    log "INFO" ""
}

gpu_preflight() {
    log "INFO" "🔧 GPU preflight check..."

    # Be tolerant: nvidia-smi is informative only; never hard-fail here
    nvidia-smi -L || log "WARN" "nvidia-smi device listing failed; continuing"

    # Select first GPU by UUID if user hasn't pinned one
    if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
        first_uuid="$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1 2>/dev/null || true)"
        if [[ -n "$first_uuid" ]]; then
            export CUDA_VISIBLE_DEVICES="$first_uuid"
            log "INFO" "  • CUDA_VISIBLE_DEVICES set to first GPU UUID"
        else
            export CUDA_VISIBLE_DEVICES=0
            log "WARN" "  • UUID query empty; falling back to index 0"
        fi
    fi

    # Ensure driver libs are in path
    export LD_LIBRARY_PATH="/usr/local/nvidia/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

    # Use one Python everywhere
    log "INFO" "  • Using Python at: $PYBIN"

    # Single source of truth: PyTorch must see CUDA
    "$PYBIN" - <<'PY'
import torch, sys
print(f"[GPU] torch: {torch.__version__} cuda: {torch.version.cuda}")
ok = torch.cuda.is_available()
print(f"[GPU] cuda available: {ok}")
if not ok:
    sys.exit(2)
print(f"[GPU] device: {torch.cuda.get_device_name(0)} cap: {torch.cuda.get_device_capability(0)}")
PY
    rc=$?
    if [[ $rc -ne 0 ]]; then
        log "ERROR" "PyTorch CUDA initialization failed"
        exit 2
    fi

    log "INFO" "✅ GPU preflight complete"
    log "INFO" ""
}

start_comfyui() {
    log "INFO" "🎨 Starting ComfyUI..."

    if command -v ss >/dev/null 2>&1 && ss -tulpn 2>/dev/null | grep -q ":$COMFYUI_PORT "; then
        log "ERROR" "Port $COMFYUI_PORT already in use"
        exit 4
    fi

    cd "$COMFYUI_ROOT"
    log "INFO" "  • Starting with CUDA support"

    # Start ComfyUI in background instead of exec (allows trap to work)
    "$PYBIN" main.py --listen "0.0.0.0" --port "$COMFYUI_PORT" &
    COMFYUI_PID=$!

    # Wait for ComfyUI to actually start (max 30 seconds)
    for i in {1..30}; do
        if curl -sf http://127.0.0.1:$COMFYUI_PORT/ >/dev/null 2>&1; then
            COMFYUI_STARTED=true
            log "INFO" "✅ ComfyUI responding on port $COMFYUI_PORT"
            break
        fi
        sleep 1
    done

    if [[ "$COMFYUI_STARTED" != "true" ]]; then
        log "ERROR" "❌ ComfyUI failed to start within 30 seconds"
        exit 5
    fi

    # Wait for ComfyUI to exit
    wait $COMFYUI_PID
}

# Signal handlers
cleanup() {
    log "INFO" "🛑 Shutting down Ignition..."

    # Kill connection monitor if running
    if [[ -n "${MONITOR_PID:-}" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi

    # Kill background processes (File Browser, etc.)
    jobs -p | xargs -r kill 2>/dev/null || true

    # Run nuclear cleanup only if ComfyUI successfully started
    if [[ "$COMFYUI_STARTED" == "true" ]]; then
        log "INFO" "🔥 Running nuclear cleanup..."
        /usr/local/bin/nuke
    else
        log "INFO" "⏭️  Skipping nuke (ComfyUI did not start successfully)"
    fi
}

trap_handler() {
    cleanup
    exit 0
}

trap trap_handler EXIT SIGTERM SIGINT

# Privacy monitoring
start_connection_monitor() {
    log "INFO" "📊 Starting connection monitoring (every 2 minutes)..."

    (while true; do
        /workspace/scripts/privacy/connection-snapshot.sh
        sleep 120
    done) &
    MONITOR_PID=$!

    log "INFO" "  • Monitor PID: $MONITOR_PID"
    log "INFO" "  • View logs: /workspace/scripts/privacy/show-connections.sh"
    log "INFO" ""
}

# Main execution
main() {
    print_banner
    print_config
    check_system
    setup_storage

    # Setup telemetry blocklist BEFORE downloads
    if [[ -x "/workspace/scripts/privacy/setup-blocklist.sh" ]]; then
        /workspace/scripts/privacy/setup-blocklist.sh
    fi

    # Start connection monitoring BEFORE downloads
    if [[ -x "/workspace/scripts/privacy/connection-snapshot.sh" ]]; then
        start_connection_monitor
    fi

    download_models

    start_filebrowser
    gpu_preflight
    start_comfyui
}

main "$@"