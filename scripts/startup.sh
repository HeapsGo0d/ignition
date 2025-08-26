#!/bin/bash
# Ignition Startup Script - Simplified Edition
# Uses the same logic as download_models_once.sh for consistency

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="/workspace"
COMFYUI_ROOT="/workspace/ComfyUI"
LOG_FILE="/tmp/ignition_startup.log"

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
    log "INFO" "║              🚀 IGNITION v1.2            ║"
    log "INFO" "║        ComfyUI Dynamic Model Loader      ║"
    log "INFO" "║             SIMPLE EDITION               ║"
    log "INFO" "╚═══════════════════════════════════════════╝"
    log "INFO" ""
}

print_config() {
    log "INFO" "📋 Configuration:"
    log "INFO" "  • CivitAI Models: ${CIVITAI_MODELS:-'None specified'}"
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
    
    mkdir -p "$COMFYUI_ROOT/models"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
    
    for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
        log "INFO" "  • Created $model_type directory"
    done
    
    log "INFO" "✅ Model directories ready"
    log "INFO" ""
}

# Use the download_models_once.sh script for downloads
download_models() {
    log "INFO" "📥 Starting model downloads..."
    
    if bash "$SCRIPT_DIR/download_models_once.sh"; then
        log "INFO" "✅ Model downloads completed"
    else
        log "WARN" "⚠️ Some model downloads may have failed, but continuing"
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
            log "INFO" "  • Extended password for security: $fb_password"
        fi
        
        filebrowser -d "$db_path" config set --auth.method=json --auth.header=""
        filebrowser -d "$db_path" users add admin "$fb_password" --perm.admin
        
        log "INFO" "  • Admin user created"
    fi
    
    log "INFO" "  • Starting filebrowser on port $FILEBROWSER_PORT"
    filebrowser \
        --database "$db_path" \
        --root "$WORKSPACE_ROOT" \
        --address "0.0.0.0" \
        --port "$FILEBROWSER_PORT" &
    
    log "INFO" "  • Login: admin / [check password above]"
    log "INFO" ""
}

start_comfyui() {
    log "INFO" "🎨 Starting ComfyUI..."
    
    cd "$COMFYUI_ROOT"
    
    # Check for CUDA support
    if command -v nvidia-smi &> /dev/null && nvidia-smi > /dev/null 2>&1; then
        log "INFO" "  • Starting with CUDA support"
        exec python3 main.py \
            --listen "0.0.0.0" \
            --port "$COMFYUI_PORT" \
            --cuda-device 0
    else
        log "INFO" "  • Starting in CPU mode (no CUDA detected)"
        exec python3 main.py \
            --listen "0.0.0.0" \
            --port "$COMFYUI_PORT" \
            --cpu
    fi
}

# Signal handlers
cleanup() {
    log "INFO" "🛑 Shutting down Ignition..."
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
main() {
    print_banner
    print_config
    check_system
    setup_storage
    download_models
    start_filebrowser
    start_comfyui
}

main "$@"