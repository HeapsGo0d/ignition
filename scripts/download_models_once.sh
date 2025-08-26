#!/bin/bash
# Simple one-shot model download script for Ignition
# Uses aria2c-based downloaders for reliability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
COMFYUI_MODELS_DIR="${COMFYUI_MODELS_DIR:-$WORKSPACE_ROOT/ComfyUI/models}"

# Environment variables
export CIVITAI_MODELS="${CIVITAI_MODELS:-}"
export HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-}"
export CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
export HF_TOKEN="${HF_TOKEN:-}"

# Status indicators
SUCCESS='✅'
ERROR='❌'
WARNING='⚠️'
INFO='🔍'
DOWNLOAD='📥'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# Check if downloads are needed
check_if_downloads_needed() {
    local civitai_needed=false
    local hf_needed=false
    
    log "INFO" "Checking if model downloads are needed..."
    
    # Count existing model files
    local model_count=0
    if [[ -d "$COMFYUI_MODELS_DIR" ]]; then
        model_count=$(find "$COMFYUI_MODELS_DIR" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.bin" 2>/dev/null | wc -l)
    fi
    
    log "INFO" "Found $model_count existing model files"
    
    # Check CivitAI downloads needed
    if [[ -n "$CIVITAI_MODELS" ]]; then
        local civitai_count=$(echo "$CIVITAI_MODELS" | tr ',' '\n' | wc -l)
        log "INFO" "$civitai_count CivitAI models requested"
        
        if [[ $model_count -eq 0 ]] || [[ "${FORCE_MODEL_SYNC:-false}" == "true" ]]; then
            civitai_needed=true
            log "INFO" "CivitAI downloads needed"
        fi
    fi
    
    # Check HuggingFace downloads needed  
    if [[ -n "$HUGGINGFACE_MODELS" ]]; then
        local hf_count=$(echo "$HUGGINGFACE_MODELS" | tr ',' '\n' | wc -l)
        log "INFO" "$hf_count HuggingFace models requested"
        
        if [[ $model_count -eq 0 ]] || [[ "${FORCE_MODEL_SYNC:-false}" == "true" ]]; then
            hf_needed=true
            log "INFO" "HuggingFace downloads needed"
        fi
    fi
    
    echo "$civitai_needed $hf_needed"
}

# Download models
download_models() {
    log "INFO" "$DOWNLOAD Starting model downloads..."
    
    # Create model directories
    mkdir -p "$COMFYUI_MODELS_DIR"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
    
    # Check what downloads are needed
    local needs_check=$(check_if_downloads_needed)
    local civitai_needed=$(echo "$needs_check" | cut -d' ' -f1)
    local hf_needed=$(echo "$needs_check" | cut -d' ' -f2)
    
    local download_processes=()
    local download_needed=false
    
    # Start CivitAI downloads
    if [[ -n "$CIVITAI_MODELS" && "$civitai_needed" == "true" ]]; then
        log "INFO" "$DOWNLOAD Starting CivitAI downloads..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_civitai_simple.py" \
            --models "$CIVITAI_MODELS" \
            --token "$CIVITAI_TOKEN" \
            --output-dir "$COMFYUI_MODELS_DIR/checkpoints" &
        
        civitai_pid=$!
        download_processes+=($civitai_pid)
        log "INFO" "CivitAI download started (PID: $civitai_pid)"
    fi
    
    # Start HuggingFace downloads
    if [[ -n "$HUGGINGFACE_MODELS" && "$hf_needed" == "true" ]]; then
        log "INFO" "$DOWNLOAD Starting HuggingFace downloads..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_huggingface_simple.py" \
            --repos "$HUGGINGFACE_MODELS" \
            --token "$HF_TOKEN" \
            --output-dir "$COMFYUI_MODELS_DIR/checkpoints" &
        
        hf_pid=$!
        download_processes+=($hf_pid)
        log "INFO" "HuggingFace download started (PID: $hf_pid)"
    fi
    
    # Wait for downloads if any started
    if [[ "$download_needed" == true ]]; then
        log "INFO" "Waiting for downloads to complete..."
        
        local all_success=true
        for pid in "${download_processes[@]}"; do
            if wait $pid; then
                log "INFO" "Download process $pid completed successfully"
            else
                log "ERROR" "Download process $pid failed"
                all_success=false
            fi
        done
        
        if [[ "$all_success" == true ]]; then
            log "INFO" "$SUCCESS All downloads completed successfully"
            return 0
        else
            log "ERROR" "$ERROR Some downloads failed"
            return 1
        fi
    else
        log "INFO" "$SUCCESS No downloads needed - models already present"
        return 0
    fi
}

# Main execution
main() {
    log "INFO" "Starting one-shot model download..."
    
    if download_models; then
        log "INFO" "$SUCCESS Model download process completed"
        exit 0
    else
        log "ERROR" "$ERROR Model download process failed"
        exit 1
    fi
}

main "$@"