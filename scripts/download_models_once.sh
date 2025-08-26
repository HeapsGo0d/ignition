#!/bin/bash
# Fixed one-shot model download script for Ignition
# Properly separates logging from return values

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
COMFYUI_MODELS_DIR="${COMFYUI_MODELS_DIR:-$WORKSPACE_ROOT/ComfyUI/models}"

# Environment variables
export CIVITAI_MODELS="${CIVITAI_MODELS:-}"
export HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-}"
export CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
export HF_TOKEN="${HF_TOKEN:-}"
export FORCE_MODEL_SYNC="${FORCE_MODEL_SYNC:-false}"

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

# Check if downloads are needed - returns to stdout ONLY the decision
check_if_downloads_needed() {
    local civitai_needed=false
    local hf_needed=false
    
    log "INFO" "🔍 Checking if model downloads are needed..." >&2
    log "INFO" "Models directory: $COMFYUI_MODELS_DIR" >&2
    
    # Count existing model files
    local model_count=0
    if [[ -d "$COMFYUI_MODELS_DIR" ]]; then
        model_count=$(find "$COMFYUI_MODELS_DIR" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.bin" 2>/dev/null | wc -l)
    fi
    
    log "INFO" "Found $model_count existing model files" >&2
    
    # Check FORCE_MODEL_SYNC first
    if [[ "${FORCE_MODEL_SYNC}" == "true" ]]; then
        log "INFO" "🔄 FORCE_MODEL_SYNC=true - forcing all downloads" >&2
        civitai_needed=true
        hf_needed=true
    else
        # Check CivitAI downloads needed
        if [[ -n "$CIVITAI_MODELS" ]]; then
            local civitai_count=$(echo "$CIVITAI_MODELS" | tr ',' '\n' | wc -l)
            log "INFO" "📥 $civitai_count CivitAI models requested: $CIVITAI_MODELS" >&2
            
            if [[ $model_count -eq 0 ]]; then
                civitai_needed=true
                log "INFO" "✅ CivitAI downloads needed (no models found)" >&2
            else
                log "INFO" "⏭️ CivitAI downloads skipped ($model_count models present)" >&2
            fi
        fi
        
        # Check HuggingFace downloads needed  
        if [[ -n "$HUGGINGFACE_MODELS" ]]; then
            local hf_count=$(echo "$HUGGINGFACE_MODELS" | tr ',' '\n' | wc -l)
            log "INFO" "🤗 $hf_count HuggingFace models requested: $HUGGINGFACE_MODELS" >&2
            
            if [[ $model_count -eq 0 ]]; then
                hf_needed=true
                log "INFO" "✅ HuggingFace downloads needed (no models found)" >&2
            else
                log "INFO" "⏭️ HuggingFace downloads skipped ($model_count models present)" >&2
            fi
        fi
    fi
    
    log "INFO" "📋 Download decision: CivitAI=$civitai_needed, HuggingFace=$hf_needed" >&2
    
    # Return ONLY the decision to stdout
    echo "$civitai_needed $hf_needed"
}

# Download models
download_models() {
    log "INFO" "$DOWNLOAD Starting model downloads..."
    
    # Create model directories
    mkdir -p "$COMFYUI_MODELS_DIR"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
    
    # Get download decisions properly
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
    
    # Start HuggingFace downloads (using FLUX model keys: flux1-dev,clip_l,t5xxl_fp8,ae)
    if [[ -n "$HUGGINGFACE_MODELS" && "$hf_needed" == "true" ]]; then
        log "INFO" "$DOWNLOAD Starting HuggingFace downloads..."
        download_needed=true
        
        python3 "$SCRIPT_DIR/download_huggingface_simple.py" \
            --repos "$HUGGINGFACE_MODELS" \
            --token "$HF_TOKEN" \
            --output-dir "$COMFYUI_MODELS_DIR" &
        
        hf_pid=$!
        download_processes+=($hf_pid)
        log "INFO" "HuggingFace download started (PID: $hf_pid)"
    fi
    
    # Wait for downloads if any started
    if [[ "$download_needed" == true ]]; then
        log "INFO" "Waiting for downloads to complete..."
        
        local success_count=0
        local total_processes=${#download_processes[@]}
        
        for pid in "${download_processes[@]}"; do
            if wait $pid; then
                log "INFO" "Download process $pid completed successfully"
                ((success_count++))
            else
                log "ERROR" "Download process $pid failed"
            fi
        done
        
        # Final model count
        local final_count=$(find "$COMFYUI_MODELS_DIR" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.bin" 2>/dev/null | wc -l)
        log "INFO" "Final model count: $final_count files"
        log "INFO" "Download summary: $success_count/$total_processes processes succeeded"
        
        if [[ $success_count -eq $total_processes ]]; then
            log "INFO" "$SUCCESS All downloads completed successfully"
            return 0
        elif [[ $success_count -gt 0 ]]; then
            log "INFO" "$WARNING Partial success: $success_count/$total_processes downloads completed"
            return 0  # Consider partial success as overall success
        else
            log "ERROR" "$ERROR All downloads failed"
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