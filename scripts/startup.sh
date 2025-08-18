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
export FILEBROWSER_PASSWORD="${FILEBROWSER_PASSWORD:-runpod}"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export FILEBROWSER_PORT="${FILEBROWSER_PORT:-8080}"
export FORCE_MODEL_SYNC="${FORCE_MODEL_SYNC:-false}"

# Health marker file to track successful boots
HEALTH_MARKER_FILE="$WORKSPACE_ROOT/.ignition_ok"

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
    log "INFO" "  • Storage: RunPod volume (/workspace)"
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

# Setup model directories (RunPod volume handles persistence)
setup_storage() {
    log "INFO" "💾 Setting up model directories..."
    
    # Ensure model directories exist in /workspace/ComfyUI/models/
    for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
        model_dir="$COMFYUI_ROOT/models/$model_type"
        mkdir -p "$model_dir"
        log "INFO" "  • Created $model_type directory"
    done
    
    log "INFO" "✅ Model directories ready"
    log "INFO" ""
}

# Check if downloads are needed by scanning existing models
check_downloads_needed() {
    local civitai_needed=false
    local hf_needed=false
    
    # If health marker exists and force sync is not enabled, do quick check but trust previous success
    if [[ -f "$HEALTH_MARKER_FILE" && "$FORCE_MODEL_SYNC" != "true" ]]; then
        log "INFO" "  • Health marker found - doing quick model count verification"
        # Quick count check - if models exist, trust health marker
        local total_files=$(find "$COMFYUI_ROOT/models" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" 2>/dev/null | wc -l)
        if (( total_files > 0 )); then
            log "INFO" "  • Found $total_files model files - trusting previous successful boot"
            log "INFO" "  • Use FORCE_MODEL_SYNC=true to override and re-download"
            echo "false false"
            return
        else
            log "INFO" "  • No model files found despite health marker - will re-download"
        fi
    fi
    
    log "INFO" "  • Performing detailed model availability check..."
    
    # Debug: Show where we're looking and what's actually there
    log "INFO" "  • Searching in: $COMFYUI_ROOT/models/"
    local all_files=$(find "$COMFYUI_ROOT/models" -type f 2>/dev/null | wc -l)
    log "INFO" "  • Total files in models directory: $all_files"
    
    # List some files if they exist
    if (( all_files > 0 )); then
        log "INFO" "  • Sample files found:"
        find "$COMFYUI_ROOT/models" -type f 2>/dev/null | head -3 | while read file; do
            log "INFO" "    → $file"
        done
    fi
    
    # Quick check for existing models to avoid redundant downloads
    if [[ -n "$CIVITAI_MODELS" ]]; then
        # Count existing models in common directories
        local checkpoint_count=$(find "$COMFYUI_ROOT/models/checkpoints" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" 2>/dev/null | wc -l)
        local lora_count=$(find "$COMFYUI_ROOT/models/loras" -name "*.safetensors" -o -name "*.pt" 2>/dev/null | wc -l)
        local vae_count=$(find "$COMFYUI_ROOT/models/vae" -name "*.safetensors" -o -name "*.pt" 2>/dev/null | wc -l)
        
        local total_models=$((checkpoint_count + lora_count + vae_count))
        local civitai_model_count=$(echo "$CIVITAI_MODELS" | tr ',' '\n' | wc -l)
        
        log "INFO" "  • checkpoints: $checkpoint_count, loras: $lora_count, vae: $vae_count"
        
        if (( total_models < civitai_model_count )); then
            civitai_needed=true
        fi
        
        log "INFO" "  • Found $total_models existing models, expecting $civitai_model_count from CivitAI"
    fi
    
    if [[ -n "$HUGGINGFACE_MODELS" ]]; then
        # Check for HuggingFace models (typically in checkpoints)
        local hf_checkpoint_count=$(find "$COMFYUI_ROOT/models/checkpoints" -name "*flux*" -o -name "*FLUX*" 2>/dev/null | wc -l)
        local hf_model_count=$(echo "$HUGGINGFACE_MODELS" | tr ',' '\n' | wc -l)
        
        if (( hf_checkpoint_count < hf_model_count )); then
            hf_needed=true
        fi
        
        log "INFO" "  • Found $hf_checkpoint_count existing HF models, expecting $hf_model_count"
    fi
    
    echo "$civitai_needed $hf_needed"
}

# Download models function
download_models() {
    local download_needed=false
    local download_processes=()
    
    log "INFO" "📥 Checking model downloads..."
    
    # Smart download check to avoid redundancy
    local needs_check=$(check_downloads_needed)
    local civitai_needed=$(echo $needs_check | cut -d' ' -f1)
    local hf_needed=$(echo $needs_check | cut -d' ' -f2)
    
    # Download CivitAI models only if needed
    if [[ -n "$CIVITAI_MODELS" && "$civitai_needed" == "true" ]]; then
        log "INFO" "🎨 Downloading CivitAI models..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_civitai.py" \
            --models "$CIVITAI_MODELS" \
            --token "$CIVITAI_TOKEN" &
        
        civitai_pid=$!
        download_processes+=($civitai_pid)
        log "INFO" "  • CivitAI download started (PID: $civitai_pid)"
    elif [[ -n "$CIVITAI_MODELS" ]]; then
        log "INFO" "✅ CivitAI models already present, skipping download"
    fi
    
    # Download HuggingFace models only if needed
    if [[ -n "$HUGGINGFACE_MODELS" && "$hf_needed" == "true" ]]; then
        log "INFO" "🤗 Downloading HuggingFace models..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_huggingface.py" \
            --repos "$HUGGINGFACE_MODELS" \
            --token "$HF_TOKEN" &
        
        hf_pid=$!
        download_processes+=($hf_pid)
        log "INFO" "  • HuggingFace download started (PID: $hf_pid)"
    elif [[ -n "$HUGGINGFACE_MODELS" ]]; then
        log "INFO" "✅ HuggingFace models already present, skipping download"
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
        log "INFO" "ℹ️  All models already present, skipping downloads"
    fi
    
    log "INFO" ""
}

# Start file browser
start_filebrowser() {
    log "INFO" "📁 Starting file browser..."
    
    # Create filebrowser config in persistent storage
    local config_dir="$WORKSPACE_ROOT/.filebrowser"
    local db_path="$config_dir/filebrowser.db"
    mkdir -p "$config_dir"
    
    # Initialize filebrowser database with user (only if doesn't exist)
    if [[ ! -f "$db_path" ]]; then
        log "INFO" "  • Initializing filebrowser database..."
        # First initialize the config
        filebrowser -d "$db_path" config init
        
        # Ensure password meets minimum requirements (12+ chars)
        local fb_password="$FILEBROWSER_PASSWORD"
        if [[ ${#fb_password} -lt 12 ]]; then
            fb_password="ignition_${FILEBROWSER_PASSWORD}_2024"
            log "INFO" "  • Password too short, using: $fb_password"
        fi
        
        # Set minimum password length policy
        filebrowser -d "$db_path" config set --auth.method=json --auth.header=""
        
        # Then add the admin user with proper password
        filebrowser -d "$db_path" users add admin "$fb_password" --perm.admin
        
        log "INFO" "  • Admin user created with password: $fb_password"
    fi
    
    # Start filebrowser in background (using Hearmeman's approach)
    filebrowser \
        -d "$db_path" \
        -r "$WORKSPACE_ROOT" \
        -a "0.0.0.0" \
        -p "$FILEBROWSER_PORT" \
        > "$config_dir/filebrowser.log" 2>&1 &
    
    local fb_pid=$!
    
    # Show the actual password being used (handle extended password case)
    local display_password="$FILEBROWSER_PASSWORD"
    if [[ ${#FILEBROWSER_PASSWORD} -lt 12 ]]; then
        display_password="ignition_${FILEBROWSER_PASSWORD}_2024"
    fi
    
    log "INFO" "  • File browser started on port $FILEBROWSER_PORT (PID: $fb_pid)"
    log "INFO" "  • Username: admin"
    log "INFO" "  • Password: $display_password"
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
    
    # Set explicit ComfyUI model paths
    export COMFYUI_MODEL_PATH="$COMFYUI_ROOT/models"
    
    # Ensure all model directories exist with proper permissions
    for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
        local model_dir="$COMFYUI_ROOT/models/$model_type"
        mkdir -p "$model_dir"
        chmod 755 "$model_dir"
        chown -R $(whoami):$(whoami) "$model_dir" 2>/dev/null || true
        
        if [[ -d "$model_dir" ]]; then
            local count=$(find "$model_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
            log "INFO" "  • $model_type: $count models ($(du -sh "$model_dir" 2>/dev/null | cut -f1 || echo "0B"))"
            
            # List first few models for verification
            if [[ $count -gt 0 ]]; then
                local first_models=$(find "$model_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" 2>/dev/null | head -2 | xargs -I {} basename {})
                if [[ -n "$first_models" ]]; then
                    log "INFO" "    → Sample files: $first_models"
                fi
            fi
        fi
    done
    
    log "INFO" "  • Starting ComfyUI server on port $COMFYUI_PORT..."
    log "INFO" ""
    
    # Create health marker to indicate successful startup
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ignition startup completed successfully" > "$HEALTH_MARKER_FILE"
    log "INFO" "✅ Health marker created - future restarts will be faster"
    
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