#!/bin/bash
# Ignition Startup Script - Clean Architecture
# Core ComfyUI initialization only, privacy system separate

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="/workspace"
COMFYUI_ROOT="/workspace/ComfyUI"
LOG_FILE="/tmp/ignition_startup.log"

# Set up caches and paths (centralized for IEC cleanup)
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/data/cache}"
export HF_HOME="${HF_HOME:-/workspace/data/cache/huggingface}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HF_HOME}"
export TMPDIR="${TMPDIR:-/workspace/tmp}"

# Create centralized directories
mkdir -p "$HF_HOME" "$XDG_CACHE_HOME" "$TMPDIR" /workspace/data/{outputs,uploads,logs,state} /workspace/models /workspace/policy || true

# Source IEC helpers if available
if [[ -f "$SCRIPT_DIR/cleanup-helpers.sh" ]]; then
    source "$SCRIPT_DIR/cleanup-helpers.sh"
    IEC_AVAILABLE=true
else
    IEC_AVAILABLE=false
fi

# Add scripts to PATH
export PATH="/workspace/scripts:$PATH"

# Python interpreter
PYBIN="$(command -v python3 || command -v python)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
export PRIVACY_ENABLED="${PRIVACY_ENABLED:-true}"

# IEC environment defaults
export IEC_MODE_ON_EXIT="${IEC_MODE_ON_EXIT:-basic}"
export IEC_TIMEOUT_SEC="${IEC_TIMEOUT_SEC:-30}"

print_banner() {
    log "INFO" ""
    log "INFO" "╔═══════════════════════════════════════════╗"
    log "INFO" "║              🚀 IGNITION v2.1            ║"
    log "INFO" "║       RTX 5090 Blackwell Edition         ║"
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
    log "INFO" "  • ComfyUI Port: $COMFYUI_PORT"
    log "INFO" "  • File Browser Port: $FILEBROWSER_PORT"
    log "INFO" "  • Privacy Protection: ${PRIVACY_ENABLED}"
    log "INFO" ""
}

check_system() {
    log "INFO" "🔍 Checking system requirements..."

    if [[ ! -d "$COMFYUI_ROOT" ]]; then
        log "ERROR" "ComfyUI directory not found: $COMFYUI_ROOT"
        exit 1
    fi

    # Check GPU availability
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 || echo "Unknown")
        log "INFO" "  • GPU Detected: $GPU_INFO"
    else
        log "WARN" "  • No NVIDIA GPU detected"
    fi

    # Optional RTX 5090 Blackwell sanity check (runtime only)
    if [[ "${SANITY:-0}" == "1" ]]; then
        log "INFO" "  • Running RTX 5090 Blackwell sanity check..."
        python3 /workspace/scripts/sanity.py || log "WARN" "Sanity check failed"

        log "INFO" "  • Running post-boot acceptance checks..."
        log "INFO" "    - Torch version: $(python3 -c 'import torch; print(torch.__version__)')"
        log "INFO" "    - CUDA version: $(python3 -c 'import torch; print(torch.version.cuda)')"
        log "INFO" "    - Device: $(python3 -c 'import torch; print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else "No GPU")')"
        log "INFO" "    - Capability: $(python3 -c 'import torch; print(torch.cuda.get_device_capability(0) if torch.cuda.is_available() else "N/A")')"

        # Validate no fragile packages are present
        log "INFO" "  • Checking for fragile CUDA packages..."
        FRAGILE_FOUND=$(python3 -m pip freeze | grep -i -E 'torch|triton|xformers|flash|onnxruntime' || true)
        if [[ -n "$FRAGILE_FOUND" ]]; then
            log "INFO" "    - Found packages: $FRAGILE_FOUND"
            # Check for specifically denied packages
            DENIED_FOUND=$(echo "$FRAGILE_FOUND" | grep -i -E 'xformers|flash-attn|flash_attn|onnxruntime-gpu' || true)
            if [[ -n "$DENIED_FOUND" ]]; then
                log "WARN" "    - ⚠️ Found denied packages: $DENIED_FOUND"
            else
                log "INFO" "    - ✅ No denied packages found"
            fi
        else
            log "INFO" "    - ✅ No torch-related packages detected"
        fi
    fi

    log "INFO" "✅ System requirements check complete"
    log "INFO" ""
}

setup_storage() {
    log "INFO" "💾 Setting up model directories..."

    mkdir -p "$COMFYUI_ROOT/models"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models,diffusion_models,text_encoders,clip,unet}

    log "INFO" "✅ Model directories ready"
    log "INFO" ""
}

# Initialize minimal privacy system
initialize_privacy() {
    if [[ "${PRIVACY_BYPASS:-0}" == "1" ]]; then
        log "WARN" "⚠️ PRIVACY BYPASS ACTIVE - ALL NETWORK MONITORING DISABLED"
        log "INFO" ""
        return
    fi

    if [[ "$PRIVACY_ENABLED" == "true" ]]; then
        log "INFO" "🛡️ Initializing minimal privacy system..."
        log "INFO" "  • STRICT_MODE: ${STRICT_MODE:-0}"
        log "INFO" "  • PROXY_PORT: ${PROXY_PORT:-8888}"

        # Setup log management and daily rotation
        log "INFO" "  • Setting up privacy logs..."
        if [[ -x "$SCRIPT_DIR/privacy-logs.sh" ]]; then
            "$SCRIPT_DIR/privacy-logs.sh" setup
            # Run daily maintenance on startup
            "$SCRIPT_DIR/privacy-logs.sh" daily &
        fi

        # Apply firewall rules if STRICT_MODE enabled
        if [[ "${STRICT_MODE:-0}" == "1" ]]; then
            log "INFO" "  • Applying STRICT_MODE firewall rules..."
            if [[ -x "$SCRIPT_DIR/minimal-firewall.sh" ]]; then
                "$SCRIPT_DIR/minimal-firewall.sh" start
            else
                log "ERROR" "STRICT_MODE enabled but minimal-firewall.sh not found"
                exit 1
            fi
        fi

        # Start proxy system
        log "INFO" "  • Starting minimal proxy..."
        if [[ -x "$SCRIPT_DIR/minimal-proxy.sh" ]]; then
            "$SCRIPT_DIR/minimal-proxy.sh" start

            # Verify proxy is working
            sleep 2
            if [[ -f /tmp/proxy.pid ]]; then
                log "INFO" "✅ Minimal privacy system active"

                # Set proxy environment for ComfyUI process tree
                if [[ "${STRICT_MODE:-0}" == "1" ]] || [[ "${FORCE_PROXY:-0}" == "1" ]]; then
                    export HTTP_PROXY="http://127.0.0.1:${PROXY_PORT:-8888}"
                    export HTTPS_PROXY="http://127.0.0.1:${PROXY_PORT:-8888}"
                    export NO_PROXY="127.0.0.1,localhost,::1"
                    log "INFO" "  • Proxy environment configured for all processes"
                fi
            else
                log "ERROR" "Failed to start minimal proxy"
                if [[ "${STRICT_MODE:-0}" == "1" ]]; then
                    log "ERROR" "STRICT_MODE requires proxy - failing closed"
                    exit 1
                fi
            fi
        else
            log "ERROR" "Privacy system enabled but minimal-proxy.sh not found"
            exit 1
        fi
    else
        log "INFO" "🔓 Privacy protection disabled"
    fi

    # Generate privacy system status banner
    print_privacy_banner
    log "INFO" ""
}

# Print privacy system status banner
print_privacy_banner() {
    local strict_mode="${STRICT_MODE:-0}"
    local proxy_port="${PROXY_PORT:-8888}"
    local enforcement_mode="disabled"
    local allowlist_count="0"

    if [[ "$PRIVACY_ENABLED" == "true" ]]; then
        # Count allowlist domains
        if [[ -f "/workspace/privacy/allowlist.txt" ]]; then
            allowlist_count=$(grep -v '^#' /workspace/privacy/allowlist.txt | grep -v '^$' | wc -l)
        fi

        # Determine enforcement mode
        if [[ "$strict_mode" == "1" ]]; then
            if [[ -f /tmp/privacy_enforcement_mode ]]; then
                enforcement_mode=$(cat /tmp/privacy_enforcement_mode | cut -d'=' -f2)
            else
                enforcement_mode="user-space"
            fi
        else
            enforcement_mode="monitoring"
        fi

        log "INFO" "🛡️ STRICT_MODE=$strict_mode ENFORCEMENT=$enforcement_mode PROXY=127.0.0.1:$proxy_port ALLOWLIST=$allowlist_count"
    else
        log "INFO" "🔓 STRICT_MODE=0 ENFORCEMENT=disabled PROXY=none ALLOWLIST=0"
    fi
}

# Download models using existing script
download_models() {
    if [[ -z "$CIVITAI_MODELS$HUGGINGFACE_MODELS" ]]; then
        log "INFO" "📥 No models requested; skipping downloads."
        log "INFO" ""
        return
    fi

    log "INFO" "📥 Starting model downloads..."
    if [[ -x "$SCRIPT_DIR/download_models_once.sh" ]]; then
        bash "$SCRIPT_DIR/download_models_once.sh"
        log "INFO" "✅ Model downloads completed"
    else
        log "WARN" "⚠️ Download script not found, skipping model downloads"
    fi
    log "INFO" ""
}

start_filebrowser() {
    log "INFO" "📁 Starting file browser..."

    # Use centralized state directory for IEC cleanup
    local config_dir="/workspace/data/state/filebrowser"
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

        log "INFO" "  • Admin user created"
    fi

    log "INFO" "  • Starting filebrowser on port $FILEBROWSER_PORT"
    filebrowser \
        --database "$db_path" \
        --root "$WORKSPACE_ROOT" \
        --address "0.0.0.0" \
        --port "$FILEBROWSER_PORT" &

    log "INFO" "✅ File browser started"
    log "INFO" ""
}

gpu_preflight() {
    log "INFO" "🔧 GPU preflight check..."

    # GPU detection
    nvidia-smi -L || log "WARN" "nvidia-smi device listing failed; continuing"

    # Set CUDA device if not specified
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

    log "INFO" "  • Using Python at: $PYBIN"

    # Verify PyTorch CUDA
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

    # Check if port is already in use
    if command -v ss >/dev/null 2>&1 && ss -tulpn 2>/dev/null | grep -q ":$COMFYUI_PORT "; then
        log "ERROR" "Port $COMFYUI_PORT already in use"
        exit 4
    fi

    cd "$COMFYUI_ROOT"
    log "INFO" "  • Starting with CUDA support on port $COMFYUI_PORT"
    exec "$PYBIN" main.py --listen "0.0.0.0" --port "$COMFYUI_PORT"
}

# Signal handlers with IEC cleanup integration
cleanup() {
    log "INFO" "🛑 Shutting down Ignition..."

    # Stop all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true

    # Run IEC cleanup on exit if enabled
    if [[ "$IEC_AVAILABLE" == "true" && "$IEC_MODE_ON_EXIT" != "off" ]]; then
        log "INFO" "🧹 Running IEC cleanup mode: $IEC_MODE_ON_EXIT"

        # Run cleanup in background to avoid hanging the shutdown
        timeout 10s ignition-cleanup "$IEC_MODE_ON_EXIT" 2>/dev/null || {
            log "WARN" "IEC cleanup timed out or failed during shutdown"
        } &

        # Wait briefly for cleanup to start, then continue shutdown
        sleep 1
    fi

    # Mark session end for crash detection
    if [[ "$IEC_AVAILABLE" == "true" ]]; then
        mark_session_end
    fi

    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
main() {
    # Mark session start for crash detection
    if [[ "$IEC_AVAILABLE" == "true" ]]; then
        mark_session_start

        # Check for stale session and run deferred cleanup if needed
        if check_stale_session; then
            log "INFO" "🧹 Running deferred cleanup from previous session..."
            timeout 30s ignition-cleanup enhanced 2>/dev/null || {
                log "WARN" "Deferred cleanup failed, continuing startup"
            }
        fi
    fi

    print_banner
    print_config
    check_system
    initialize_privacy
    setup_storage
    download_models
    start_filebrowser
    gpu_preflight
    start_comfyui
}

main "$@"