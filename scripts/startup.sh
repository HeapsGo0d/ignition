#!/bin/bash
# Ignition Startup Script
# Orchestrates model downloads and ComfyUI startup for RunPod

set -euo pipefail  # safer bash: exit on error/undef; fail on pipe errors

# Syncing flag management
SYNC_FLAG="/tmp/ignition_syncing"
touch "$SYNC_FLAG"

# Clean up flag on exit
trap 'rm -f "$SYNC_FLAG"' EXIT

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
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
        *)
            echo -e "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Environment variable defaults - Single source of truth
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
export USE_CPU_FALLBACK="${USE_CPU_FALLBACK:-true}"  # new: allow CPU fallback if CUDA not visible

# --- GPU visibility defaults (make Torch/ComfyUI see GPU 0 consistently) ---
export NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-0}
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
export NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-compute,utility}

# Track CUDA health globally
GPU_OK=true

# Health marker file to track successful boots
HEALTH_MARKER_FILE="$WORKSPACE_ROOT/.ignition_ok"

# Service management functions
wait_for_port() {
    local host="$1" port="$2" max="$3"
    for i in $(seq 1 "$max"); do
        if (echo > /dev/tcp/$host/$port) >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

start_comfyui_service() {
    log "INFO" "🎨 Starting ComfyUI service..."
    cd "$COMFYUI_ROOT"
    
    # Build ComfyUI args based on CUDA availability
    local args=(--listen "0.0.0.0" --port "$COMFYUI_PORT")
    if [[ "$GPU_OK" == "true" ]]; then
        args+=(--cuda-device 0)
    else
        args+=(--cpu)
    fi
    
    nohup python -u main.py "${args[@]}" > /tmp/comfyui.log 2>&1 &
    log "INFO" "  • ComfyUI started in background"
}

start_filebrowser_service() {
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
        
        filebrowser config init --database "$FILEBROWSER_DB"
        
        filebrowser config set \
            --database "$FILEBROWSER_DB" \
            --auth.method=json \
            --signup=false \
            --root=/workspace \
            --address=0.0.0.0 \
            --port="$FILEBROWSER_PORT"
        
        # Generate secure password if not provided
        if [[ -z "$FILEBROWSER_PASS" || ${#FILEBROWSER_PASS} -lt $FILEBROWSER_MINPASS ]]; then
            FILEBROWSER_PASS="ignition_$(date +%s)_secure"
            log "INFO" "  • Generated secure password: $FILEBROWSER_PASS"
        fi
        
        filebrowser users add "$FILEBROWSER_USER" "$FILEBROWSER_PASS" \
            --perm.admin --database "$FILEBROWSER_DB" || {
            log "ERROR" "Failed to create filebrowser user"
            exit 1
        }
        
        log "INFO" "  • Admin user created successfully"
    fi
    
    nohup filebrowser \
        --database "$FILEBROWSER_DB" \
        --address 0.0.0.0 \
        --port "$FILEBROWSER_PORT" \
        --root /workspace > /tmp/filebrowser.log 2>&1 &
    
    log "INFO" "  • File browser started in background"
    
    # Show current filebrowser password
    local current_password="$FILEBROWSER_PASS"
    if [[ -z "$current_password" || ${#current_password} -lt $FILEBROWSER_MINPASS ]]; then
        current_password="[Generated during DB init - check logs above]"
    fi
    log "INFO" "  • Login: $FILEBROWSER_USER / $current_password"
}

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

# Ensure Python/Torch can actually see a CUDA GPU before launching ComfyUI
cuda_preflight() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        log "INFO" "🔧 Verifying CUDA visibility for Python/Torch…"
        python - <<'PY' >/dev/null 2>&1
import sys
try:
    import torch
    sys.exit(0 if torch.cuda.is_available() else 2)
except Exception:
    sys.exit(3)
PY
        rc=$?
        if [[ $rc -ne 0 ]]; then
            GPU_OK=false
            if [[ "$USE_CPU_FALLBACK" == "true" ]]; then
                log "WARN" "Torch can't see CUDA (rc=$rc). Falling back to CPU."
            else
                log "ERROR" "Torch can't see CUDA and USE_CPU_FALLBACK=false. Exiting in 5s to avoid restart thrash."
                sleep 5
                exit 1
            fi
        fi
    else
        GPU_OK=false
        if [[ "$USE_CPU_FALLBACK" == "true" ]]; then
            log "WARN" "nvidia-smi not found. Continuing on CPU."
        else
            log "ERROR" "nvidia-smi not found and USE_CPU_FALLBACK=false. Exiting in 5s."
            sleep 5
            exit 1
        fi
    fi
}

# Setup model directories (RunPod volume handles persistence)
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

# File-level model presence checking
check_downloads_needed() {
    # Redirect all output to stderr to prevent contaminating return value
    {
        log "DEBUG" "check_downloads_needed() function started"
        
        local civitai_needed=false
        local hf_needed=false
        
        log "INFO" "  • Performing file-level model availability check..."
        log "INFO" "  • Using models directory: $COMFYUI_MODELS_DIR"
        log "DEBUG" "  • FORCE_MODEL_SYNC current value: $FORCE_MODEL_SYNC"
        log "DEBUG" "  • CIVITAI_MODELS current value: $CIVITAI_MODELS"
        log "DEBUG" "  • HUGGINGFACE_MODELS current value: $HUGGINGFACE_MODELS"
        
        # Essential FLUX.1-dev files (use shard names that actually exist)
        local must_have=(
            "checkpoints/flux1-dev.safetensors"
            "checkpoints/ae.safetensors"
            # transformer shards + index
            "checkpoints/transformer/diffusion_pytorch_model-00001-of-00003.safetensors"
            "checkpoints/transformer/diffusion_pytorch_model-00002-of-00003.safetensors"
            "checkpoints/transformer/diffusion_pytorch_model-00003-of-00003.safetensors"
            "checkpoints/transformer/diffusion_pytorch_model.safetensors.index.json"
            # text encoder 1 (single file)
            "checkpoints/text_encoder/model.safetensors"
            # text encoder 2 shards + index
            "checkpoints/text_encoder_2/model-00001-of-00002.safetensors"
            "checkpoints/text_encoder_2/model-00002-of-00002.safetensors"
            "checkpoints/text_encoder_2/model.safetensors.index.json"
            # vae + basic configs
            "checkpoints/vae/diffusion_pytorch_model.safetensors"
            "checkpoints/tokenizer/tokenizer_config.json"
            "checkpoints/scheduler/scheduler_config.json"
        )
        
        log "DEBUG" "  • Checking ${#must_have[@]} essential files for presence"
        
        # Check if we need sync based on missing files
        local need_sync=false
        local missing_files=0
        local present_files=0
        local missing_list=()
        
        for file in "${must_have[@]}"; do
            local full_path="$COMFYUI_MODELS_DIR/$file"
            log "DEBUG" "    → Checking: $full_path"
            if [[ -f "$full_path" ]]; then
                ((present_files++))
                log "DEBUG" "      ✓ Present"
            else
                ((missing_files++))
                need_sync=true
                missing_list+=("$file")
                log "INFO" "    → Missing: $file"
                log "DEBUG" "      ✗ Missing (need_sync=true)"
            fi
        done
        
        log "INFO" "  • Essential files: $present_files present, $missing_files missing"
        log "DEBUG" "  • need_sync after file check: $need_sync"
        
        # Log missing files summary for debugging
        if [[ $missing_files -gt 0 ]]; then
            log "DEBUG" "  • Missing files that triggered download:"
            for missing_file in "${missing_list[@]}"; do
                log "DEBUG" "    - $missing_file"
            done
        fi
        
        # Force sync if environment variable is set
        if [[ "$FORCE_MODEL_SYNC" == "true" ]]; then
            need_sync=true
            log "INFO" "  • FORCE_MODEL_SYNC=true - forcing download"
            log "DEBUG" "  • need_sync set to true by FORCE_MODEL_SYNC"
        else
            log "DEBUG" "  • FORCE_MODEL_SYNC is not 'true', no forced sync"
        fi
        
        log "DEBUG" "  • Final need_sync value: $need_sync"
        
        # Check for any additional models from CivitAI
        if [[ -n "$CIVITAI_MODELS" && "$need_sync" == "true" ]]; then
            civitai_needed=true
            log "INFO" "  • Will download CivitAI models: $CIVITAI_MODELS"
            log "DEBUG" "  • civitai_needed set to true"
        else
            log "DEBUG" "  • CivitAI check: CIVITAI_MODELS='$CIVITAI_MODELS', need_sync='$need_sync' -> civitai_needed=false"
        fi
        
        # Check for HuggingFace models
        if [[ -n "$HUGGINGFACE_MODELS" && "$need_sync" == "true" ]]; then
            hf_needed=true
            log "INFO" "  • Will download HuggingFace models: $HUGGINGFACE_MODELS"
            log "DEBUG" "  • hf_needed set to true"
        else
            log "DEBUG" "  • HuggingFace check: HUGGINGFACE_MODELS='$HUGGINGFACE_MODELS', need_sync='$need_sync' -> hf_needed=false"
        fi
        
        if [[ "$need_sync" == "false" ]]; then
            log "INFO" "  ✅ All essential models present - skipping downloads"
            log "DEBUG" "  • No downloads needed"
        else
            log "DEBUG" "  • Downloads needed: civitai_needed=$civitai_needed, hf_needed=$hf_needed"
        fi
    
        log "DEBUG" "check_downloads_needed() function returning: '$civitai_needed $hf_needed'"
    } >&2
    
    # Return clean values to stdout only
    echo "$civitai_needed $hf_needed"
}

# Download models function
download_models() {
    log "DEBUG" "download_models() function started"
    
    local download_needed=false
    local download_processes=()
    
    log "INFO" "📥 Checking model downloads..."
    log "DEBUG" "About to call check_downloads_needed()"
    
    # Smart download check to avoid redundancy
    local needs_check=$(check_downloads_needed)
    log "DEBUG" "check_downloads_needed() returned: '$needs_check'"
    
    local civitai_needed=$(echo $needs_check | cut -d' ' -f1)
    local hf_needed=$(echo $needs_check | cut -d' ' -f2)
    log "DEBUG" "Parsed results: civitai_needed='$civitai_needed', hf_needed='$hf_needed'"
    
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
    fi
    
    # Fix model permissions after downloads
    log "INFO" "🔧 Setting model permissions..."
    chown -R "$(id -u)":"$(id -g)" "$COMFYUI_MODELS_DIR" 2>/dev/null || true
    chmod -R u+rwX,go+rX "$COMFYUI_MODELS_DIR" 2>/dev/null || true
    log "INFO" "✅ Model permissions updated"
    
    # One-shot FORCE_MODEL_SYNC handling
    if [[ "${FORCE_MODEL_SYNC:-false}" == "true" ]]; then
        log "INFO" "FORCE_MODEL_SYNC used for initial sync; disabling for remainder of session."
        export FORCE_MODEL_SYNC="false"
    fi
    
    log "INFO" ""
}

# Start services and wait for readiness
start_services() {
    log "INFO" "🚀 Starting services..."
    
    # Comprehensive health summary
    log "INFO" "📊 Health Summary:"
    log "INFO" "  • Mount: $(df -h /workspace | tail -1 | awk '{print $4 " available"}')"
    log "INFO" "  • Models: $(find "$COMFYUI_MODELS_DIR" -type f 2>/dev/null | wc -l) files in $COMFYUI_MODELS_DIR"
    
    # Show model counts per directory
    for model_type in checkpoints loras vae embeddings controlnet upscale_models; do
        local model_dir="$COMFYUI_MODELS_DIR/$model_type"
        if [[ -d "$model_dir" ]]; then
            local count=$(find "$model_dir" -type f 2>/dev/null | wc -l)
            local size=$(du -sh "$model_dir" 2>/dev/null | cut -f1 || echo "0B")
            log "INFO" "    → $model_type: $count files ($size)"
        fi
    done
    
    # Export model path for ComfyUI
    export COMFYUI_MODELS_DIR
    
    # Start services
    start_comfyui_service
    start_filebrowser_service
    
    # Wait for ComfyUI to be ready
    log "INFO" "⏳ Waiting for ComfyUI to be ready..."
    if wait_for_port 127.0.0.1 8188 180; then
        log "INFO" "✅ ComfyUI is ready on port 8188"
    else
        log "WARN" "ComfyUI not responding after 180s, but continuing..."
    fi
    
    # Remove syncing flag now that services are up
    rm -f "$SYNC_FLAG"
    log "INFO" "🟢 Services started - healthcheck will now monitor port 8188"
    
    # Create health marker
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ignition startup completed successfully" > "$HEALTH_MARKER_FILE"
    log "INFO" "✅ Health marker created"
    
    # Keep container alive by tailing logs
    log "INFO" "📋 Following service logs..."
    exec tail -F /tmp/comfyui.log /tmp/filebrowser.log 2>/dev/null
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
    cuda_preflight           # moved before services to fail/decide early
    start_services
}

# Run main function
main "$@"