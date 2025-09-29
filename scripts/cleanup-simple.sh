#!/bin/bash
# Simple, Fast Cleanup System
# Minimal, reliable cleanup that completes in <5 seconds

set -euo pipefail

# Essential configuration only
IEC_DATA_ROOT="${IEC_DATA_ROOT:-/workspace/data}"
IEC_DATA_OUTPUTS="${IEC_DATA_OUTPUTS:-$IEC_DATA_ROOT/outputs}"
IEC_DATA_UPLOADS="${IEC_DATA_UPLOADS:-$IEC_DATA_ROOT/uploads}"
IEC_DATA_CACHE="${IEC_DATA_CACHE:-$IEC_DATA_ROOT/cache}"
IEC_DATA_STATE="${IEC_DATA_STATE:-$IEC_DATA_ROOT/state}"
IEC_MODELS="${IEC_MODELS:-/workspace/models}"
IEC_TMP="${IEC_TMP:-/workspace/tmp}"
IEC_DATA_LOGS="${IEC_DATA_LOGS:-$IEC_DATA_ROOT/logs}"

# Model optimization - skip scanning by default
MODEL_DIRS_SKIP="${MODEL_DIRS_SKIP:-/workspace/ComfyUI/models /workspace/models}"
CLEANUP_SCAN_MODELS="${CLEANUP_SCAN_MODELS:-0}"

# Simple timeout wrapper
run_with_timeout() {
    local timeout_sec=$1; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=5s "${timeout_sec}s" bash -c "$@"
    else
        bash -c "$@"
    fi
}

# Fast model directory check
is_model_directory() {
    local path="$1"
    local model_dirs_array
    read -ra model_dirs_array <<< "$MODEL_DIRS_SKIP"
    for model_dir in "${model_dirs_array[@]}"; do
        if [[ "$path" == "$model_dir"* ]]; then
            return 0
        fi
    done
    return 1
}

# Fast size calculation with model optimization
get_size_gb_fast() {
    local path="$1"

    # IMMEDIATE return for model directories - this eliminates 90% of scan time
    if is_model_directory "$path" && [[ "${CLEANUP_SCAN_MODELS:-0}" != "1" ]]; then
        echo "0.00"
        return 0
    fi

    # Quick calculation for non-model paths
    if [[ ! -e "$path" ]]; then
        echo "0.00"
        return 0
    fi

    local size_bytes=$(du -sb "$path" 2>/dev/null | awk '{print $1}' || echo "0")
    awk "BEGIN {printf \"%.2f\", $size_bytes/1024/1024/1024}" 2>/dev/null || echo "0.00"
}

# Simple basic cleanup
cleanup_basic_fast() {
    local start=$(date +%s.%N)

    echo "🧹 Basic cleanup: outputs, uploads, temp"

    # Direct removal operations
    [[ -d "$IEC_DATA_OUTPUTS" ]] && rm -rf "$IEC_DATA_OUTPUTS"/* 2>/dev/null || true
    [[ -d "$IEC_DATA_UPLOADS" ]] && rm -rf "$IEC_DATA_UPLOADS"/* 2>/dev/null || true
    [[ -d "$IEC_TMP" ]] && rm -rf "$IEC_TMP"/* 2>/dev/null || true

    # Quick log cleanup
    if [[ -d "$IEC_DATA_LOGS" ]]; then
        find "$IEC_DATA_LOGS" -name "session*" -mtime +0 -type f -exec rm -f {} + 2>/dev/null || true
        find "$IEC_DATA_LOGS" -name "startup*" -mtime +0 -type f -exec rm -f {} + 2>/dev/null || true
    fi

    # Temp files
    rm -f /tmp/ignition_startup.log /tmp/*.tmp 2>/dev/null || true

    local duration=$(echo "$(date +%s.%N) - $start" | bc 2>/dev/null || echo "0")
    echo "✅ Basic cleanup completed in ${duration}s"
}

# Simple enhanced cleanup
cleanup_enhanced_fast() {
    local start=$(date +%s.%N)

    echo "🧹 Enhanced cleanup: basic + caches"

    # Run basic first
    cleanup_basic_fast

    # Add cache cleanup
    [[ -d "$IEC_DATA_CACHE" ]] && rm -rf "$IEC_DATA_CACHE"/* 2>/dev/null || true

    # Quick cache search and cleanup
    find /workspace -maxdepth 3 -name "*cache*" -type d 2>/dev/null | head -5 | \
        while read -r cache_dir; do
            [[ "$cache_dir" != "$IEC_DATA_CACHE"* ]] && rm -rf "$cache_dir"/* 2>/dev/null || true
        done

    # Pip caches
    rm -rf /tmp/pip-* /root/.cache/pip ~/.cache/pip 2>/dev/null || true

    local duration=$(echo "$(date +%s.%N) - $start" | bc 2>/dev/null || echo "0")
    echo "✅ Enhanced cleanup completed in ${duration}s"
}

# Simple nuclear cleanup
cleanup_nuclear_fast() {
    local start=$(date +%s.%N)

    echo "☢️  Nuclear cleanup: EVERYTHING"

    # Run enhanced first
    cleanup_enhanced_fast

    # Nuclear-specific deletions
    [[ -d "$IEC_DATA_STATE" ]] && rm -rf "$IEC_DATA_STATE"/* 2>/dev/null || true
    [[ -d "/workspace/.filebrowser" ]] && rm -rf "/workspace/.filebrowser" 2>/dev/null || true

    # Only delete models if explicitly enabled
    if [[ "${CLEANUP_DELETE_MODELS:-0}" == "1" ]]; then
        [[ -d "$IEC_MODELS" ]] && rm -rf "$IEC_MODELS"/* 2>/dev/null || true
        [[ -d "/workspace/ComfyUI/models" ]] && rm -rf "/workspace/ComfyUI/models"/* 2>/dev/null || true
    fi

    # Quick credential cleanup
    find /workspace -maxdepth 2 -name "*token*" -o -name "*key*" -o -name "*secret*" 2>/dev/null | \
        head -5 | while read -r file; do
            [[ -f "$file" ]] && rm -f "$file" 2>/dev/null || true
        done

    local duration=$(echo "$(date +%s.%N) - $start" | bc 2>/dev/null || echo "0")
    echo "✅ Nuclear cleanup completed in ${duration}s"
}

# Recreate essential directories
recreate_directories() {
    mkdir -p "$IEC_DATA_OUTPUTS" "$IEC_DATA_UPLOADS" "$IEC_DATA_LOGS" \
             "$IEC_DATA_CACHE" "$IEC_DATA_STATE" "$IEC_MODELS" "$IEC_TMP" 2>/dev/null || true
}

# Main cleanup function
cleanup_with_mode() {
    local mode="$1"
    local timeout_sec="${2:-30}"
    local dry_run="${3:-0}"

    if [[ "$dry_run" == "1" ]]; then
        echo "[DRY RUN] Would clean mode=$mode"
        return 0
    fi

    # Use timeout wrapper
    case "$mode" in
        basic)
            run_with_timeout "$timeout_sec" "cleanup_basic_fast"
            ;;
        enhanced)
            run_with_timeout "$timeout_sec" "cleanup_enhanced_fast"
            ;;
        nuclear)
            run_with_timeout "$timeout_sec" "cleanup_nuclear_fast"
            ;;
        *)
            echo "Error: Unknown mode $mode"
            return 1
            ;;
    esac

    # Always recreate directories
    recreate_directories
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced - export functions
    export -f cleanup_with_mode cleanup_basic_fast cleanup_enhanced_fast cleanup_nuclear_fast
    export -f get_size_gb_fast is_model_directory run_with_timeout
fi