#!/bin/bash
# One-shot model download script
# Returns 0 on success, non-zero on failure for retry logic

set -euo pipefail

# Configuration from parent environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
COMFYUI_ROOT="${COMFYUI_ROOT:-/workspace/ComfyUI}"
COMFYUI_MODELS_DIR="${COMFYUI_MODELS_DIR:-$WORKSPACE_ROOT/ComfyUI/models}"

# Environment variable defaults
export CIVITAI_MODELS="${CIVITAI_MODELS:-}"
export HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-}"
export CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
export HF_TOKEN="${HF_TOKEN:-}"
export FORCE_MODEL_SYNC="${FORCE_MODEL_SYNC:-false}"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# File-level model presence checking
check_downloads_needed() {
    {
        log "DEBUG" "check_downloads_needed() function started"
        
        local civitai_needed=false
        local hf_needed=false
        
        log "INFO" "Performing file-level model availability check..."
        log "INFO" "Using models directory: $COMFYUI_MODELS_DIR"
        log "DEBUG" "FORCE_MODEL_SYNC current value: $FORCE_MODEL_SYNC"
        log "DEBUG" "CIVITAI_MODELS current value: $CIVITAI_MODELS"
        log "DEBUG" "HUGGINGFACE_MODELS current value: $HUGGINGFACE_MODELS"
        
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
        
        log "DEBUG" "Checking ${#must_have[@]} essential files for presence"
        
        # Check if we need sync based on missing files
        local need_sync=false
        local missing_files=0
        local present_files=0
        local missing_list=()
        
        for file in "${must_have[@]}"; do
            local full_path="$COMFYUI_MODELS_DIR/$file"
            log "DEBUG" "Checking: $full_path"
            if [[ -f "$full_path" ]]; then
                ((present_files++))
                log "DEBUG" "✓ Present"
            else
                ((missing_files++))
                need_sync=true
                missing_list+=("$file")
                log "INFO" "Missing: $file"
                log "DEBUG" "✗ Missing (need_sync=true)"
            fi
        done
        
        log "INFO" "Essential files: $present_files present, $missing_files missing"
        log "DEBUG" "need_sync after file check: $need_sync"
        
        # Log missing files summary for debugging
        if [[ $missing_files -gt 0 ]]; then
            log "DEBUG" "Missing files that triggered download:"
            for missing_file in "${missing_list[@]}"; do
                log "DEBUG" "  - $missing_file"
            done
        fi
        
        # Force sync if environment variable is set (one-shot only)
        if [[ "$FORCE_MODEL_SYNC" == "true" ]]; then
            need_sync=true
            log "INFO" "FORCE_MODEL_SYNC=true - forcing download"
            log "DEBUG" "need_sync set to true by FORCE_MODEL_SYNC"
            # Disable for remainder of session
            export FORCE_MODEL_SYNC="false"
            log "INFO" "FORCE_MODEL_SYNC disabled for remainder of session"
        else
            log "DEBUG" "FORCE_MODEL_SYNC is not 'true', no forced sync"
        fi
        
        log "DEBUG" "Final need_sync value: $need_sync"
        
        # Check for any additional models from CivitAI
        if [[ -n "$CIVITAI_MODELS" && "$need_sync" == "true" ]]; then
            civitai_needed=true
            log "INFO" "Will download CivitAI models: $CIVITAI_MODELS"
            log "DEBUG" "civitai_needed set to true"
        else
            log "DEBUG" "CivitAI check: CIVITAI_MODELS='$CIVITAI_MODELS', need_sync='$need_sync' -> civitai_needed=false"
        fi
        
        # Check for HuggingFace models
        if [[ -n "$HUGGINGFACE_MODELS" && "$need_sync" == "true" ]]; then
            hf_needed=true
            log "INFO" "Will download HuggingFace models: $HUGGINGFACE_MODELS"
            log "DEBUG" "hf_needed set to true"
        else
            log "DEBUG" "HuggingFace check: HUGGINGFACE_MODELS='$HUGGINGFACE_MODELS', need_sync='$need_sync' -> hf_needed=false"
        fi
        
        if [[ "$need_sync" == "false" ]]; then
            log "INFO" "✅ All essential models present - skipping downloads"
            log "DEBUG" "No downloads needed"
        else
            log "DEBUG" "Downloads needed: civitai_needed=$civitai_needed, hf_needed=$hf_needed"
        fi
    
        log "DEBUG" "check_downloads_needed() function returning: '$civitai_needed $hf_needed'"
    } >&2
    
    # Return clean values to stdout only
    echo "$civitai_needed $hf_needed"
}

# Main download function
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
        log "INFO" "CivitAI download started (PID: $civitai_pid)"
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
        log "INFO" "HuggingFace download started (PID: $hf_pid)"
    fi
    
    # Wait for all downloads to complete if any were started
    if [[ "$download_needed" == true ]]; then
        log "INFO" "⏳ Waiting for downloads to complete..."
        
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
            log "INFO" "✅ All model downloads completed successfully"
        else
            log "ERROR" "⚠️ Some model downloads failed"
            return 1
        fi
    else
        log "INFO" "✅ No downloads needed"
    fi
    
    # Fix model permissions after downloads
    log "INFO" "🔧 Setting model permissions..."
    chown -R "$(id -u)":"$(id -g)" "$COMFYUI_MODELS_DIR" 2>/dev/null || true
    chmod -R u+rwX,go+rX "$COMFYUI_MODELS_DIR" 2>/dev/null || true
    log "INFO" "✅ Model permissions updated"
    
    return 0
}

# Main execution
main() {
    log "INFO" "Starting one-shot model download..."
    
    # Ensure model directories exist
    mkdir -p "$COMFYUI_MODELS_DIR"/{checkpoints,loras,vae,embeddings,controlnet,upscale_models}
    
    if download_models; then
        log "INFO" "✅ Model download completed successfully"
        exit 0
    else
        log "ERROR" "❌ Model download failed"
        exit 1
    fi
}

# Run main function
main "$@"