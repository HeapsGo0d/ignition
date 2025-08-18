#!/bin/bash
# Ignition Startup Script
# Orchestrates model downloads and ComfyUI startup for RunPod

set -e  # Exit on any error

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
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
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
export PERSISTENT_STORAGE="${PERSISTENT_STORAGE:-none}"
export FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-runpod}"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export FILEBROWSER_PORT="${FILEBROWSER_PORT:-8080}"

# Print startup banner
print_banner() {
    log "INFO" ""
    log "INFO" "╔═══════════════════════════════════════════╗"
    log "INFO" "║              🚀 IGNITION v1.0            ║"
    log "INFO" "║        ComfyUI Dynamic Model Loader      ║"
    log "INFO" "╚═══════════════════════════════════════════╝"
    log "INFO" ""
}

# Print environment configuration
print_config() {
    log "INFO" "📋 Configuration:"
    log "INFO" "  • CivitAI Models: ${CIVITAI_MODELS:-'None specified'}"
    log "INFO" "  • HuggingFace Models: ${HUGGINGFACE_MODELS:-'None specified'}"
    log "INFO" "  • Persistent Storage: $PERSISTENT_STORAGE"
    log "INFO" "  • ComfyUI Port: $COMFYUI_PORT"
    log "INFO" "  • File Browser Port: $FILEBROWSER_PORT"
    log "INFO" ""
}

# Check system requirements
check_system() {
    log "INFO" "🔍 Checking system requirements..."
    
    # Check if we're in the right directory
    if [[ ! -d "$COMFYUI_ROOT" ]]; then
        log "ERROR" "ComfyUI directory not found: $COMFYUI_ROOT"
        exit 1
    fi
    
    # Check if Python scripts exist
    if [[ ! -f "$SCRIPT_DIR/download_civitai.py" ]] || [[ ! -f "$SCRIPT_DIR/download_huggingface.py" ]]; then
        log "ERROR" "Download scripts not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Check GPU availability
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1)
        log "INFO" "  • GPU Detected: $GPU_INFO"
    else
        log "WARN" "  • No NVIDIA GPU detected or nvidia-smi not available"
    fi
    
    # Check available disk space
    DISK_SPACE=$(df -h "$WORKSPACE_ROOT" | awk 'NR==2 {print $4}')
    log "INFO" "  • Available disk space: $DISK_SPACE"
    
    log "INFO" "✅ System requirements check complete"
    log "INFO" ""
}

# Setup persistent storage if specified
setup_storage() {
    if [[ "$PERSISTENT_STORAGE" != "none" ]]; then
        log "INFO" "💾 Setting up persistent storage: $PERSISTENT_STORAGE"
        
        # Create persistent storage directories if they don't exist
        mkdir -p "$PERSISTENT_STORAGE"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
        
        # Create symlinks to persistent storage
        for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
            local_dir="$COMFYUI_ROOT/models/$model_type"
            persistent_dir="$PERSISTENT_STORAGE/$model_type"
            
            # Remove existing directory if it exists
            if [[ -d "$local_dir" ]] && [[ ! -L "$local_dir" ]]; then
                log "INFO" "  • Moving existing $model_type to persistent storage"
                rsync -av "$local_dir/" "$persistent_dir/" 2>/dev/null || true
                rm -rf "$local_dir"
            fi
            
            # Create symlink
            if [[ ! -L "$local_dir" ]]; then
                ln -sf "$persistent_dir" "$local_dir"
                log "INFO" "  • Linked $model_type to persistent storage"
            fi
        done
        
        log "INFO" "✅ Persistent storage setup complete"
        log "INFO" ""
    fi
}

# Download models function
download_models() {
    local download_needed=false
    local download_processes=()
    
    log "INFO" "📥 Starting model downloads..."
    
    # Download CivitAI models
    if [[ -n "$CIVITAI_MODELS" ]]; then
        log "INFO" "🎨 Downloading CivitAI models..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_civitai.py" \
            --models "$CIVITAI_MODELS" \
            --token "$CIVITAI_TOKEN" \
            --persistent-storage "$PERSISTENT_STORAGE" &
        
        civitai_pid=$!
        download_processes+=($civitai_pid)
        log "INFO" "  • CivitAI download started (PID: $civitai_pid)"
    fi
    
    # Download HuggingFace models
    if [[ -n "$HUGGINGFACE_MODELS" ]]; then
        log "INFO" "🤗 Downloading HuggingFace models..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_huggingface.py" \
            --repos "$HUGGINGFACE_MODELS" \
            --token "$HF_TOKEN" \
            --persistent-storage "$PERSISTENT_STORAGE" &
        
        hf_pid=$!
        download_processes+=($hf_pid)
        log "INFO" "  • HuggingFace download started (PID: $hf_pid)"
    fi
    
    # Wait for all downloads to complete if any were started
    if [[ "$download_needed" == true ]]; then
        log "INFO" "⏳ Waiting for downloads to complete..."
        
        local all_success=true
        for pid in "${download_processes[@]}"; do
            if wait $pid; then
                log "INFO" "  • Download process $pid completed successfully"
            else
                log "ERROR" "  • Download process $pid failed"
                all_success=false
            fi
        done
        
        if [[ "$all_success" == true ]]; then
            log "INFO" "✅ All model downloads completed successfully"
        else
            log "WARN" "⚠️  Some model downloads failed, but continuing with startup"
        fi
    else
        log "INFO" "ℹ️  No models specified for download"
    fi
    
    log "INFO" ""
}

# Start file browser
start_filebrowser() {
    log "INFO" "📁 Starting file browser..."
    
    # Create filebrowser config
    local config_dir="/tmp/filebrowser"
    mkdir -p "$config_dir"
    
    # Start filebrowser in background
    filebrowser \
        --root "$WORKSPACE_ROOT" \
        --port "$FILEBROWSER_PORT" \
        --address "0.0.0.0" \
        --username "admin" \
        --password "$FILEBROWSER_PASSWORD" \
        --database "$config_dir/filebrowser.db" \
        --log /tmp/filebrowser.log &
    
    local fb_pid=$!
    log "INFO" "  • File browser started on port $FILEBROWSER_PORT (PID: $fb_pid)"
    log "INFO" "  • Username: admin"
    log "INFO" "  • Password: $FILEBROWSER_PASSWORD"
    log "INFO" ""
}

# Start ComfyUI
start_comfyui() {
    log "INFO" "🎨 Starting ComfyUI..."
    
    # Change to ComfyUI directory
    cd "$COMFYUI_ROOT"
    
    # Set up CUDA environment if available
    if command -v nvidia-smi &> /dev/null; then
        export CUDA_VISIBLE_DEVICES=0
        log "INFO" "  • CUDA device set to: $CUDA_VISIBLE_DEVICES"
    fi
    
    # Log model counts
    for model_type in checkpoints loras vae embeddings; do
        local model_dir="$COMFYUI_ROOT/models/$model_type"
        if [[ -d "$model_dir" ]]; then
            local count=$(find "$model_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" | wc -l)
            log "INFO" "  • $model_type: $count models"
        fi
    done
    
    log "INFO" "  • Starting ComfyUI server on port $COMFYUI_PORT..."
    log "INFO" ""
    
    # Start ComfyUI (this will run in foreground)
    exec python3 main.py \
        --listen "0.0.0.0" \
        --port "$COMFYUI_PORT" \
        --cuda-device 0
}

# Cleanup function for graceful shutdown
cleanup() {
    log "INFO" ""
    log "INFO" "🛑 Shutting down Ignition..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    log "INFO" "✅ Shutdown complete"
    exit 0
}

# Set up signal handlers
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

# Run main function
main "$@"