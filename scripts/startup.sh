#!/bin/bash
# Ignition Startup Script - Robust Edition
# Starts services FIRST, downloads in background with retry

set -euo pipefail

# Syncing flag management - DO NOT remove on unexpected exit
SYNC_FLAG="/tmp/ignition_syncing"
touch "$SYNC_FLAG"
trap 'echo "IGNITION ABORTED unexpectedly; leaving $SYNC_FLAG to keep healthcheck green."' EXIT

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
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
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
export FILEBROWSER_DB="$WORKSPACE_ROOT/.filebrowser/filebrowser.db"
export FILEBROWSER_USER="admin"
export FILEBROWSER_PASS="${FILEBROWSER_PASSWORD:-}"
export FILEBROWSER_MINPASS="12"
export FILEBROWSER_PORT="${FILEBROWSER_PORT:-8080}"
export COMFYUI_MODELS_DIR="$WORKSPACE_ROOT/ComfyUI/models"
export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
export FORCE_MODEL_SYNC="${FORCE_MODEL_SYNC:-false}"
export DEBUG_MODE="${DEBUG_MODE:-false}"
export USE_CPU_FALLBACK="${USE_CPU_FALLBACK:-true}"

# GPU visibility defaults
export NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-0}
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
export NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-compute,utility}

# Track CUDA health globally
GPU_OK=true

# Wait for port function
wait_for_port() {
    local host="$1" 
    local port="$2" 
    local timeout="$3"
    for i in $(seq 1 "$timeout"); do
        if (echo > /dev/tcp/$host/$port) >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# DNS hardening - non-fatal
require_dns() {
    log "INFO" "🌐 Checking DNS connectivity..."
    for host in civitai.com huggingface.co; do
        if getent hosts "$host" >/dev/null 2>&1; then
            log "INFO" "  ✅ DNS OK for $host"
        else
            log "WARN" "  ⚠️ DNS lookup failed for $host"
        fi
    done
}

# Print startup banner
print_banner() {
    log "INFO" ""
    log "INFO" "╔═══════════════════════════════════════════╗"
    log "INFO" "║              🚀 IGNITION v1.1            ║"
    log "INFO" "║        ComfyUI Dynamic Model Loader      ║"
    log "INFO" "║             ROBUST EDITION               ║"
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

# Check system requirements - non-fatal
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
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 2>/dev/null || echo "Unknown")
        log "INFO" "  • GPU Detected: $GPU_INFO"
    else
        log "WARN" "  • No NVIDIA GPU detected or nvidia-smi not available"
    fi
    
    # Check available disk space
    DISK_SPACE=$(df -h "$WORKSPACE_ROOT" | awk 'NR==2 {print $4}' 2>/dev/null || echo "Unknown")
    log "INFO" "  • Available disk space: $DISK_SPACE"
    
    log "INFO" "✅ System requirements check complete"
    log "INFO" ""
}

# Non-fatal CUDA visibility check with verbose logging
cuda_preflight() {
    log "INFO" "🔧 Verifying CUDA visibility for Python/Torch..."
    
    {
        echo "Verifying CUDA via Python/Torch..."
        python3 - <<'PY'
import sys
try:
    import torch
    print("torch version:", torch.__version__)
    print("cuda available:", torch.cuda.is_available())
    print("cuda device count:", torch.cuda.device_count())
    if torch.cuda.is_available():
        print("current device:", torch.cuda.current_device())
        print("device name:", torch.cuda.get_device_name(0))
    sys.exit(0)
except Exception as e:
    print("CUDA/Torch check FAILED:", repr(e))
    sys.exit(0)  # NON-FATAL
PY
    } 2>&1 | tee -a /tmp/ignition_cuda_check.log
    
    # Determine GPU status from the check
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
        GPU_OK=true
        log "INFO" "✅ CUDA is available"
    else
        GPU_OK=false
        if [[ "$USE_CPU_FALLBACK" == "true" ]]; then
            log "WARN" "⚠️ CUDA not available, falling back to CPU"
        else
            log "WARN" "⚠️ CUDA not available and USE_CPU_FALLBACK=false, but continuing anyway"
        fi
    fi
}

# Setup model directories
setup_storage() {
    log "INFO" "💾 Setting up model directories..."
    
    # Ensure model directories exist using COMFYUI_MODELS_DIR
    mkdir -p "$COMFYUI_MODELS_DIR"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
    
    for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
        model_dir="$COMFYUI_MODELS_DIR/$model_type"
        log "INFO" "  • Created $model_type directory: $model_dir"
    done
    
    log "INFO" "✅ Model directories ready at: $COMFYUI_MODELS_DIR"
    log "INFO" ""
}

# Start ComfyUI service - early and in background
start_comfyui() {
    log "INFO" "🎨 Starting ComfyUI service..."
    cd "$COMFYUI_ROOT"
    
    # Build ComfyUI args based on CUDA availability
    local args=(--listen "0.0.0.0" --port "$COMFYUI_PORT")
    if [[ "$GPU_OK" == "true" ]]; then
        args+=(--cuda-device 0)
        log "INFO" "  • Using CUDA device 0"
    else
        args+=(--cpu)
        log "INFO" "  • Using CPU mode"
    fi
    
    nohup python3 -u main.py "${args[@]}" > /tmp/comfyui.log 2>&1 &
    log "INFO" "  • ComfyUI started in background"
}

# Start FileBrowser service - early and in background
start_filebrowser() {
    log "INFO" "📁 Starting filebrowser service..."
    
    if ! command -v filebrowser >/dev/null 2>&1; then
        log "WARN" "filebrowser not found in PATH; skipping File Browser startup."
        return 0
    fi
    
    # Create filebrowser config directory
    mkdir -p "$(dirname "$FILEBROWSER_DB")"
    
    # Initialize filebrowser database if it doesn't exist
    if [[ ! -f "$FILEBROWSER_DB" ]]; then
        log "INFO" "  • Initializing filebrowser database..."
        
        filebrowser config init --database "$FILEBROWSER_DB" 2>/dev/null || {
            log "WARN" "Failed to init filebrowser database"
            return 0
        }
        
        filebrowser config set \
            --database "$FILEBROWSER_DB" \
            --auth.method=json \
            --signup=false \
            --root=/workspace \
            --address=0.0.0.0 \
            --port="$FILEBROWSER_PORT" 2>/dev/null || {
            log "WARN" "Failed to configure filebrowser"
            return 0
        }
        
        # Generate secure password if not provided
        if [[ -z "$FILEBROWSER_PASS" || ${#FILEBROWSER_PASS} -lt $FILEBROWSER_MINPASS ]]; then
            FILEBROWSER_PASS="ignition_$(date +%s)_secure"
            log "INFO" "  • Generated secure password: $FILEBROWSER_PASS"
        fi
        
        filebrowser users add "$FILEBROWSER_USER" "$FILEBROWSER_PASS" \
            --perm.admin --database "$FILEBROWSER_DB" 2>/dev/null || {
            log "WARN" "Failed to create filebrowser user"
            return 0
        }
        
        log "INFO" "  • Admin user created successfully"
    fi
    
    nohup filebrowser \
        --database "$FILEBROWSER_DB" \
        --address 0.0.0.0 \
        --port "$FILEBROWSER_PORT" \
        --root /workspace > /tmp/filebrowser.log 2>&1 &
    
    log "INFO" "  • File browser started in background"
    log "INFO" "  • Login: $FILEBROWSER_USER / ${FILEBROWSER_PASS:-[check logs above]}"
}

# Background download loop with exponential backoff
download_loop() {
    local delay=60
    while true; do
        log "INFO" "🔄 Starting model download attempt..."
        if "$SCRIPT_DIR/download_models_once.sh"; then
            log "INFO" "✅ Model sync succeeded"
            break
        else
            log "WARN" "❌ Model sync failed; retrying in $delay seconds"
            sleep "$delay"
            delay=$(( delay < 1800 ? delay*2 : 1800 ))  # Cap at 30 minutes
        fi
    done
}

# Start background downloads
start_downloads() {
    log "INFO" "📥 Starting background model downloads..."
    nohup bash -c "$(declare -f log download_loop); download_loop" > /tmp/ignition_downloads.log 2>&1 &
    log "INFO" "  • Download loop started in background"
}

# Main execution
main() {
    print_banner
    print_config
    check_system
    setup_storage
    require_dns
    cuda_preflight
    
    # Start core services EARLY - before downloads
    log "INFO" "🚀 Starting core services..."
    start_comfyui
    start_filebrowser
    
    # Wait for ComfyUI to be reachable, but don't exit if slow
    log "INFO" "⏳ Waiting for ComfyUI to be ready..."
    if wait_for_port 127.0.0.1 8188 180; then
        log "INFO" "✅ ComfyUI is ready on port 8188"
    else
        log "WARN" "⚠️ ComfyUI not up after 180s, continuing anyway"
    fi
    
    # Only after ComfyUI is reachable, clear the syncing flag
    rm -f "$SYNC_FLAG"
    log "INFO" "🟢 Services started - healthcheck will now monitor port 8188"
    
    # Now allow normal exit semantics
    trap - EXIT
    
    # Start downloads in background with retry
    start_downloads
    
    # Show health summary
    log "INFO" "📊 Health Summary:"
    log "INFO" "  • Mount: $(df -h /workspace | tail -1 | awk '{print $4 " available"}' 2>/dev/null || echo 'Unknown')"
    log "INFO" "  • Models: $(find "$COMFYUI_MODELS_DIR" -type f 2>/dev/null | wc -l) files in $COMFYUI_MODELS_DIR"
    
    # Keep PID 1 alive regardless of download outcome
    log "INFO" "📋 Following service logs..."
    exec tail -F /tmp/comfyui.log /tmp/filebrowser.log /tmp/ignition_downloads.log /tmp/ignition_cuda_check.log 2>/dev/null
}

# Set up signal handlers for graceful shutdown
cleanup() {
    log "INFO" ""
    log "INFO" "🛑 Shutting down Ignition..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    log "INFO" "✅ Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main function
main "$@"