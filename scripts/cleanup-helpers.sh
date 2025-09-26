#!/bin/bash
# Intelligent Ephemeral Cleanup (IEC) - Core Utilities
# Shared functions for path management, size calculation, and safe cleanup operations

set -euo pipefail

# IEC Configuration - Default paths for centralized writes
IEC_DATA_ROOT="${IEC_DATA_ROOT:-/workspace/data}"
IEC_DATA_OUTPUTS="${IEC_DATA_OUTPUTS:-$IEC_DATA_ROOT/outputs}"
IEC_DATA_UPLOADS="${IEC_DATA_UPLOADS:-$IEC_DATA_ROOT/uploads}"
IEC_DATA_LOGS="${IEC_DATA_LOGS:-$IEC_DATA_ROOT/logs}"
IEC_DATA_CACHE="${IEC_DATA_CACHE:-$IEC_DATA_ROOT/cache}"
IEC_DATA_STATE="${IEC_DATA_STATE:-$IEC_DATA_ROOT/state}"
IEC_MODELS="${IEC_MODELS:-/workspace/models}"
IEC_TMP="${IEC_TMP:-/workspace/tmp}"

# IEC Runtime Configuration
IEC_POLICY_DIR="${IEC_POLICY_DIR:-/workspace/policy}"
IEC_PINS_FILE="${IEC_PINS_FILE:-$IEC_POLICY_DIR/pins.txt}"
IEC_CLEANUP_LOG="${IEC_CLEANUP_LOG:-$IEC_DATA_LOGS/cleanup.log}"
IEC_LOCK_FILE="${IEC_LOCK_FILE:-/tmp/cleanup-$$-$(id -u).lock}"
IEC_SESSION_LOCK="${IEC_SESSION_LOCK:-/tmp/stale_session.lock}"
IEC_MODEL_CACHE="${IEC_MODEL_CACHE:-$IEC_POLICY_DIR/model_sizes.cache}"
IEC_MODEL_CACHE_INVALIDATE="${IEC_MODEL_CACHE_INVALIDATE:-$IEC_POLICY_DIR/model_sizes.cache.invalidate}"

# Environment defaults
export IEC_MODE_ON_EXIT="${IEC_MODE_ON_EXIT:-basic}"
export IEC_BUDGET_GB="${IEC_BUDGET_GB:-10}"
export IEC_TIMEOUT_SEC="${IEC_TIMEOUT_SEC:-30}"
export IEC_DRY_RUN="${IEC_DRY_RUN:-0}"
export CLEANUP_IGNORE_PINS="${CLEANUP_IGNORE_PINS:-0}"

# Model directory optimization
export MODEL_DIRS_SKIP="${MODEL_DIRS_SKIP:-/workspace/ComfyUI/models /workspace/models}"
export MODEL_CACHE_TTL_SEC="${MODEL_CACHE_TTL_SEC:-3600}"
export CLEANUP_SCAN_MODELS="${CLEANUP_SCAN_MODELS:-0}"
export CLEANUP_DELETE_MODELS="${CLEANUP_DELETE_MODELS:-0}"
export CLEANUP_ALLOW_MOUNTS="${CLEANUP_ALLOW_MOUNTS:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Always log to cleanup log if available
    if [[ -w "$(dirname "$IEC_CLEANUP_LOG")" ]]; then
        echo "[$timestamp] [$level] $message" >> "$IEC_CLEANUP_LOG" 2>/dev/null || true
    fi

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "DEBUG")
            if [[ "${IEC_DEBUG:-0}" == "1" ]]; then
                echo -e "${CYAN}[DEBUG]${NC} $message" >&2
            fi
            ;;
        *)
            echo -e "$message" >&2
            ;;
    esac
}

# Banner printing
print_iec_banner() {
    local mode=$1
    local action=${2:-"cleanup"}
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║         🧹 INTELLIGENT EPHEMERAL         ║"
    echo "║              CLEANUP (IEC)                ║"
    echo "║            Mode: $(printf "%-15s" "$mode")        ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Size calculation utilities with robust error handling
get_size_gb() {
    local path="$1"

    # Check if this is a model directory and use cached size if available
    if is_model_directory "$path" && [[ "$CLEANUP_SCAN_MODELS" != "1" ]]; then
        log "DEBUG" "Using cached size for model directory: $path"
        get_cached_model_size
        return 0
    fi

    # Fall back to direct calculation for non-model paths
    get_size_gb_direct "$path"
}

get_size_mb() {
    local path="$1"

    # Check if this is a model directory and use cached size if available
    if is_model_directory "$path" && [[ "$CLEANUP_SCAN_MODELS" != "1" ]]; then
        log "DEBUG" "Using cached size for model directory (MB): $path"
        local cached_gb=$(get_cached_model_size)
        awk "BEGIN {printf \"%.1f\", $cached_gb * 1024}"
        return 0
    fi

    # Fall back to direct calculation for non-model paths
    if [[ ! -e "$path" ]]; then
        echo "0.0"
        return 0
    fi

    local du_output
    du_output=$(du -sb "$path" 2>/dev/null)
    local du_exit=$?

    if [[ $du_exit -ne 0 || -z "$du_output" ]]; then
        log "DEBUG" "du command failed for path: $path"
        echo "0.0"
        return 0
    fi

    # Validate du output format
    local size_bytes=$(echo "$du_output" | awk '{print $1}')
    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]]; then
        log "DEBUG" "Invalid du output for path: $path (output: $du_output)"
        echo "0.0"
        return 0
    fi

    # Convert to MB with error handling
    local size_mb
    size_mb=$(awk "BEGIN {printf \"%.1f\", $size_bytes/1024/1024}" 2>/dev/null)
    if [[ $? -ne 0 || -z "$size_mb" ]]; then
        log "DEBUG" "awk conversion failed for bytes: $size_bytes"
        echo "0.0"
    else
        echo "$size_mb"
    fi
}

count_files() {
    local path="$1"
    local exclude_models="${2:-1}"  # Default: exclude models

    if [[ ! -d "$path" ]]; then
        echo "0"
        return 0
    fi

    # Build find command with exclusions
    local find_cmd="find \"$path\" -type f"

    # Add model directory exclusions unless specifically requested to include them
    if [[ "$exclude_models" == "1" && "$CLEANUP_SCAN_MODELS" != "1" ]]; then
        local exclude_pattern=$(build_model_exclude_pattern)
        if [[ -n "$exclude_pattern" ]]; then
            find_cmd="find \"$path\" \\( $exclude_pattern \\) -prune -o -type f -print"
        fi
    fi

    # Add mount boundary restriction unless explicitly allowed
    if [[ "$CLEANUP_ALLOW_MOUNTS" != "1" ]]; then
        find_cmd="$find_cmd -xdev"
    fi

    # Execute and count
    eval "$find_cmd" 2>/dev/null | wc -l
}

# Model cache management
is_model_cache_valid() {
    local cache_file="$IEC_MODEL_CACHE"
    local invalidate_file="$IEC_MODEL_CACHE_INVALIDATE"

    # Check if cache file exists
    [[ -f "$cache_file" ]] || return 1

    # Check manual invalidation trigger
    if [[ -f "$invalidate_file" && "$invalidate_file" -nt "$cache_file" ]]; then
        log "DEBUG" "Model cache manually invalidated"
        return 1
    fi

    # Check directory modification times
    local model_dirs_array
    read -ra model_dirs_array <<< "$MODEL_DIRS_SKIP"
    for model_dir in "${model_dirs_array[@]}"; do
        if [[ -d "$model_dir" && "$model_dir" -nt "$cache_file" ]]; then
            log "DEBUG" "Model directory modified: $model_dir"
            return 1
        fi
    done

    # Check TTL
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo "0")))
    if [[ $cache_age -gt $MODEL_CACHE_TTL_SEC ]]; then
        log "DEBUG" "Model cache expired (age: ${cache_age}s, TTL: ${MODEL_CACHE_TTL_SEC}s)"
        return 1
    fi

    log "DEBUG" "Model cache is valid (age: ${cache_age}s)"
    return 0
}

get_cached_model_size() {
    local cache_file="$IEC_MODEL_CACHE"

    if is_model_cache_valid; then
        cat "$cache_file" 2>/dev/null || echo "0.00"
    else
        # Cache invalid, recalculate
        calculate_model_sizes
    fi
}

calculate_model_sizes() {
    local cache_file="$IEC_MODEL_CACHE"
    local total_gb="0.00"

    log "DEBUG" "Calculating model directory sizes..."

    # Ensure cache directory exists
    mkdir -p "$(dirname "$cache_file")"

    local model_dirs_array
    read -ra model_dirs_array <<< "$MODEL_DIRS_SKIP"

    for model_dir in "${model_dirs_array[@]}"; do
        if [[ -d "$model_dir" ]]; then
            local dir_size_gb=$(get_size_gb_direct "$model_dir")
            log "DEBUG" "Model directory $model_dir: ${dir_size_gb}GB"
            total_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb + $dir_size_gb}")
        fi
    done

    # Cache the result
    echo "$total_gb" > "$cache_file"

    # Clean up invalidation trigger
    rm -f "$IEC_MODEL_CACHE_INVALIDATE" 2>/dev/null || true

    log "DEBUG" "Model cache updated: ${total_gb}GB"
    echo "$total_gb"
}

# Direct size calculation without cache (for cache population)
get_size_gb_direct() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        echo "0.00"
        return 0
    fi

    local du_output
    du_output=$(du -sb "$path" 2>/dev/null)
    local du_exit=$?

    if [[ $du_exit -ne 0 || -z "$du_output" ]]; then
        echo "0.00"
        return 0
    fi

    local size_bytes=$(echo "$du_output" | awk '{print $1}')
    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]]; then
        echo "0.00"
        return 0
    fi

    awk "BEGIN {printf \"%.2f\", $size_bytes/1024/1024/1024}" 2>/dev/null || echo "0.00"
}

# Model directory utilities
is_model_directory() {
    local path="$1"
    local resolved_path

    # Resolve path
    if [[ -L "$path" ]]; then
        resolved_path=$(readlink -f "$path" 2>/dev/null)
    else
        resolved_path="$path"
    fi

    # Check against model directories
    local model_dirs_array
    read -ra model_dirs_array <<< "$MODEL_DIRS_SKIP"
    for model_dir in "${model_dirs_array[@]}"; do
        local resolved_model_dir=$(readlink -f "$model_dir" 2>/dev/null || echo "$model_dir")
        if [[ "$resolved_path" == "$resolved_model_dir"* ]]; then
            return 0
        fi
    done
    return 1
}

build_model_exclude_pattern() {
    local pattern=""
    local model_dirs_array
    read -ra model_dirs_array <<< "$MODEL_DIRS_SKIP"

    for model_dir in "${model_dirs_array[@]}"; do
        if [[ -d "$model_dir" ]]; then
            if [[ -n "$pattern" ]]; then
                pattern="$pattern -o -path $model_dir/*"
            else
                pattern="-path $model_dir/*"
            fi
        fi
    done

    echo "$pattern"
}

# Invalidate model cache (for external use)
invalidate_model_cache() {
    log "INFO" "Invalidating model cache"
    touch "$IEC_MODEL_CACHE_INVALIDATE" 2>/dev/null || true
}

# Path validation and safety
validate_cleanup_path() {
    local path="$1"
    local allow_root_paths="${2:-false}"

    # Never allow these paths
    local forbidden_paths=(
        "/"
        "/bin"
        "/usr"
        "/etc"
        "/var"
        "/home"
        "/root"
        "/workspace/ComfyUI/main.py"
        "/workspace/ComfyUI/web"
        "/workspace/ComfyUI/nodes"
        "/workspace/scripts"
    )

    for forbidden in "${forbidden_paths[@]}"; do
        if [[ "$path" == "$forbidden" ]] || [[ "$path" == "$forbidden"/* ]]; then
            log "ERROR" "Forbidden path: $path"
            return 1
        fi
    done

    # Resolve path safely - fail-closed if realpath fails
    local resolved_path
    if [[ -e "$path" ]]; then
        resolved_path=$(realpath "$path" 2>/dev/null)
        if [[ -z "$resolved_path" ]]; then
            log "ERROR" "Failed to resolve path safely: $path"
            return 1
        fi
    else
        resolved_path="$path"
    fi

    # Resolve workspace path to handle case where /workspace itself is a symlink
    local resolved_workspace
    if [[ -e "/workspace" ]]; then
        resolved_workspace=$(readlink -f "/workspace" 2>/dev/null)
        if [[ -z "$resolved_workspace" ]]; then
            log "ERROR" "Failed to resolve workspace path /workspace"
            return 1
        fi
    else
        resolved_workspace="/workspace"
    fi
    log "DEBUG" "Resolved workspace: $resolved_workspace"

    # Check for symlinks and validate them
    if [[ -L "$path" ]]; then
        log "DEBUG" "Symlink detected: $path -> $resolved_path"
        # Additional symlink validation - ensure target is under resolved workspace
        if [[ "$resolved_path" != "$resolved_workspace"* ]]; then
            log "ERROR" "Symlink target outside workspace: $path -> $resolved_path (workspace: $resolved_workspace)"
            return 1
        fi
    fi

    # Check if under resolved workspace (unless specifically allowing root paths)
    if [[ "$allow_root_paths" != "true" ]] && [[ "$resolved_path" != "$resolved_workspace"* ]]; then
        log "ERROR" "Path outside workspace: $resolved_path (workspace: $resolved_workspace)"
        return 1
    fi

    log "DEBUG" "Path validated: $resolved_path"
    return 0
}

# Pin pattern validation
validate_pin_pattern() {
    local pattern="$1"

    # Check basic pattern structure
    if [[ -z "$pattern" ]]; then
        return 1
    fi

    case "$pattern" in
        model:*)
            # Model tag format: model:name (alphanumeric, hyphens, underscores)
            local model_tag="${pattern#model:}"
            if [[ -z "$model_tag" ]] || [[ ! "$model_tag" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                log "DEBUG" "Invalid model tag format: $pattern"
                return 1
            fi
            ;;
        folder:*)
            # Folder path format: folder:/absolute/path
            local folder_path="${pattern#folder:}"
            if [[ -z "$folder_path" ]] || [[ "$folder_path" != /* ]]; then
                log "DEBUG" "Invalid folder path format (must be absolute): $pattern"
                return 1
            fi
            # Check for dangerous folder patterns
            case "$folder_path" in
                /|/bin|/usr|/etc|/var|/home|/root)
                    log "DEBUG" "Dangerous folder path not allowed: $pattern"
                    return 1
                    ;;
            esac
            ;;
        /*)
            # Absolute path format
            # Check for dangerous absolute paths
            case "$pattern" in
                /|/bin/*|/usr/*|/etc/*|/var/*|/home/*|/root/*)
                    log "DEBUG" "Dangerous absolute path not allowed: $pattern"
                    return 1
                    ;;
            esac
            ;;
        */*)
            # Relative path with directory separator - validate basic structure
            if [[ "$pattern" =~ \.\./|\./\. ]]; then
                log "DEBUG" "Unsafe path traversal in pattern: $pattern"
                return 1
            fi
            ;;
        *.*)
            # Glob pattern with extension - basic validation
            if [[ ${#pattern} -gt 100 ]]; then
                log "DEBUG" "Pattern too long: $pattern"
                return 1
            fi
            ;;
        *)
            # Simple filename pattern
            if [[ ${#pattern} -gt 50 ]]; then
                log "DEBUG" "Pattern too long: $pattern"
                return 1
            fi
            # Check for suspicious characters
            if [[ "$pattern" =~ [[:space:]\$\`] ]]; then
                log "DEBUG" "Suspicious characters in pattern: $pattern"
                return 1
            fi
            ;;
    esac

    log "DEBUG" "Valid pin pattern: $pattern"
    return 0
}

# Pin system
load_pins() {
    local pins=()

    # Create parent directory if missing
    local pins_dir=$(dirname "$IEC_PINS_FILE")
    if [[ ! -d "$pins_dir" ]]; then
        mkdir -p "$pins_dir" 2>/dev/null || {
            log "WARN" "Failed to create pins directory: $pins_dir"
            return 0  # Return empty list on failure
        }
        log "DEBUG" "Created pins directory: $pins_dir"
    fi

    if [[ -f "$IEC_PINS_FILE" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Validate pin pattern format
            if validate_pin_pattern "$line"; then
                pins+=("$line")
            else
                log "WARN" "Invalid pin pattern skipped: $line"
            fi
        done < "$IEC_PINS_FILE" 2>/dev/null || {
            log "WARN" "Failed to read pins file: $IEC_PINS_FILE"
            return 0  # Return empty list on read failure
        }
        log "DEBUG" "Loaded ${#pins[@]} valid pins from $IEC_PINS_FILE"
    else
        log "DEBUG" "No pins file found at $IEC_PINS_FILE (this is normal)"
    fi

    printf '%s\n' "${pins[@]}"
}

is_pinned() {
    local path="$1"
    local pins

    # If ignoring pins, nothing is pinned (return 1 = false = not pinned)
    if [[ "$CLEANUP_IGNORE_PINS" == "1" ]]; then
        return 1  # Return 1 = false = not pinned, so deletion proceeds
    fi

    # Load pins into array
    readarray -t pins < <(load_pins)

    # Check each pin pattern
    for pin in "${pins[@]}"; do
        # Handle different pin types
        case "$pin" in
            model:*)
                # Model tag matching - check if path contains model reference
                local model_tag="${pin#model:}"
                if [[ "$path" == *"$model_tag"* ]]; then
                    log "DEBUG" "Path pinned by model tag: $path (pin: $pin)"
                    return 0
                fi
                ;;
            folder:*)
                # Folder pin - exact match
                local folder_path="${pin#folder:}"
                if [[ "$path" == "$folder_path" ]] || [[ "$path" == "$folder_path"/* ]]; then
                    log "DEBUG" "Path pinned by folder: $path (pin: $pin)"
                    return 0
                fi
                ;;
            /*)
                # Absolute path pin
                if [[ "$path" == "$pin" ]] || [[ "$path" == "$pin"/* ]]; then
                    log "DEBUG" "Path pinned by absolute path: $path (pin: $pin)"
                    return 0
                fi
                ;;
            *)
                # Glob pattern pin
                if [[ "$path" == $pin ]]; then
                    log "DEBUG" "Path pinned by glob: $path (pin: $pin)"
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

# Lock management
acquire_cleanup_lock() {
    local timeout=${1:-10}
    local count=0

    # Try flock first for atomic locking (if available)
    if command -v flock >/dev/null 2>&1; then
        log "DEBUG" "Using flock for atomic lock acquisition"
        if flock -x -w "$timeout" "$IEC_LOCK_FILE" echo $$ 2>/dev/null; then
            log "DEBUG" "Acquired cleanup lock (flock)"
            return 0
        else
            log "ERROR" "Failed to acquire flock after ${timeout}s"
            return 1
        fi
    fi

    # Fallback to improved noclobber method
    log "DEBUG" "Using noclobber fallback for lock acquisition"
    while [[ $count -lt $timeout ]]; do
        # Atomic test-and-set with validation
        if (set -C; echo "$$:$(date +%s)" > "$IEC_LOCK_FILE") 2>/dev/null; then
            # Validate we actually got the lock (race condition check)
            local lock_content=$(cat "$IEC_LOCK_FILE" 2>/dev/null || echo "")
            if [[ "$lock_content" == "$$:"* ]]; then
                log "DEBUG" "Acquired cleanup lock (noclobber)"
                return 0
            else
                log "WARN" "Lock acquisition race detected, retrying"
                rm -f "$IEC_LOCK_FILE" 2>/dev/null || true
            fi
        fi

        # Check for stale locks with atomic cleanup
        if [[ -f "$IEC_LOCK_FILE" ]]; then
            local lock_content=$(cat "$IEC_LOCK_FILE" 2>/dev/null || echo "")
            local lock_pid="${lock_content%%:*}"
            local lock_time="${lock_content##*:}"

            if [[ -n "$lock_pid" ]] && [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
                if ! kill -0 "$lock_pid" 2>/dev/null; then
                    # Atomic stale lock removal
                    log "WARN" "Removing stale lock (PID $lock_pid)"
                    if (set -C; rm "$IEC_LOCK_FILE" && echo "$$:$(date +%s)" > "$IEC_LOCK_FILE") 2>/dev/null; then
                        log "DEBUG" "Acquired cleanup lock after stale removal"
                        return 0
                    fi
                fi
            else
                log "WARN" "Invalid lock file format, attempting cleanup"
                rm -f "$IEC_LOCK_FILE" 2>/dev/null || true
            fi
        fi

        log "DEBUG" "Waiting for cleanup lock... ($count/$timeout)"
        sleep 1
        ((count++))
    done

    log "ERROR" "Failed to acquire cleanup lock after ${timeout}s"
    return 1
}

release_cleanup_lock() {
    if [[ -f "$IEC_LOCK_FILE" ]]; then
        rm -f "$IEC_LOCK_FILE" 2>/dev/null || true
        log "DEBUG" "Released cleanup lock"
    fi
}

# Session management
mark_session_start() {
    echo $$ > "$IEC_SESSION_LOCK" 2>/dev/null || true
}

mark_session_end() {
    rm -f "$IEC_SESSION_LOCK" 2>/dev/null || true
}

check_stale_session() {
    if [[ -f "$IEC_SESSION_LOCK" ]]; then
        local session_pid=$(cat "$IEC_SESSION_LOCK" 2>/dev/null || echo "")
        if [[ -n "$session_pid" ]] && ! kill -0 "$session_pid" 2>/dev/null; then
            log "INFO" "Detected stale session (PID $session_pid), cleanup may be needed"
            return 0
        fi
    fi
    return 1
}

# Service management
quiesce_services() {
    log "INFO" "Quiescing services before cleanup..."

    # Stop ComfyUI gracefully
    if pgrep -f "main.py.*ComfyUI" >/dev/null; then
        log "INFO" "  • Stopping ComfyUI..."
        pkill -TERM -f "main.py.*ComfyUI" 2>/dev/null || true
        sleep 2
        pkill -KILL -f "main.py.*ComfyUI" 2>/dev/null || true
    fi

    # Stop filebrowser
    if pgrep -f "filebrowser" >/dev/null; then
        log "INFO" "  • Stopping filebrowser..."
        pkill -TERM -f "filebrowser" 2>/dev/null || true
        sleep 1
        pkill -KILL -f "filebrowser" 2>/dev/null || true
    fi

    # Stop proxy if running
    if [[ -f /tmp/proxy.pid ]]; then
        local proxy_pid=$(cat /tmp/proxy.pid 2>/dev/null || echo "")
        if [[ -n "$proxy_pid" ]] && kill -0 "$proxy_pid" 2>/dev/null; then
            log "INFO" "  • Stopping proxy..."
            kill -TERM "$proxy_pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$proxy_pid" 2>/dev/null || true
        fi
        rm -f /tmp/proxy.pid 2>/dev/null || true
    fi

    # Stop aria2c download processes
    if pgrep -f "aria2c" >/dev/null; then
        log "INFO" "  • Stopping aria2c..."
        pkill -TERM -f "aria2c" 2>/dev/null || true
        sleep 2
        pkill -KILL -f "aria2c" 2>/dev/null || true
    fi

    # Stop privacy monitoring processes
    for privacy_proc in "privacy_state_manager.py" "activity_detector.py" "connection_monitor.sh"; do
        if pgrep -f "$privacy_proc" >/dev/null; then
            log "INFO" "  • Stopping $privacy_proc..."
            pkill -TERM -f "$privacy_proc" 2>/dev/null || true
        fi
    done

    # Stop any download processes that might have file handles
    for download_proc in "download_.*\\.py" "wget" "curl.*-o"; do
        if pgrep -f "$download_proc" >/dev/null; then
            log "INFO" "  • Stopping download processes..."
            pkill -TERM -f "$download_proc" 2>/dev/null || true
            sleep 1
            pkill -KILL -f "$download_proc" 2>/dev/null || true
            break  # Only log once for all download processes
        fi
    done

    # Stop any Python processes that might be holding file handles in workspace
    local workspace_python_pids=$(lsof +D /workspace 2>/dev/null | awk '/python/ {print $2}' | sort -u || true)
    if [[ -n "$workspace_python_pids" ]]; then
        log "INFO" "  • Stopping Python processes with workspace file handles..."
        echo "$workspace_python_pids" | while read -r pid; do
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
        # Force kill any remaining
        echo "$workspace_python_pids" | while read -r pid; do
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi

    # Extended pause for file handles to close properly
    sleep 2
    log "INFO" "Services quiesced"
}

# Safe deletion with validation
safe_delete() {
    local path="$1"
    local mode="${2:-basic}"
    local dry_run="${3:-$IEC_DRY_RUN}"

    # Short-circuit for model directories unless nuclear mode with explicit delete enabled
    if is_model_directory "$path" && [[ "$mode" != "nuclear" || "$CLEANUP_DELETE_MODELS" != "1" ]]; then
        log "DEBUG" "Skipping model directory: $path (mode: $mode, delete_models: ${CLEANUP_DELETE_MODELS:-0})"
        return 0
    fi

    # Validate path
    if ! validate_cleanup_path "$path"; then
        log "ERROR" "Path validation failed: $path"
        return 1
    fi

    # Check if pinned (unless overridden)
    if is_pinned "$path"; then
        local pin_override=$([[ "$CLEANUP_IGNORE_PINS" == "1" ]] && echo " (PINS IGNORED)" || echo "")
        if [[ "$CLEANUP_IGNORE_PINS" != "1" ]]; then
            log "INFO" "Skipping pinned path: $path"
            return 0
        else
            log "WARN" "Deleting pinned path: $path$pin_override"
        fi
    fi

    # Check if path exists
    if [[ ! -e "$path" ]]; then
        log "DEBUG" "Path does not exist: $path"
        return 0
    fi

    # Calculate size before deletion (with model directory exclusions for performance)
    local size_mb=$(get_size_mb "$path")
    local file_count=$(count_files "$path" 1)  # 1 = exclude models for performance

    # Dry run mode
    if [[ "$dry_run" == "1" ]]; then
        if [[ -d "$path" ]]; then
            echo "  [DRY] Would delete directory: $path ($file_count files, ${size_mb}MB)"
        else
            echo "  [DRY] Would delete file: $path (${size_mb}MB)"
        fi
        return 0
    fi

    # Perform deletion
    log "INFO" "Deleting: $path ($file_count files, ${size_mb}MB)"

    if [[ -d "$path" ]]; then
        rm -rf "$path" 2>/dev/null || {
            log "WARN" "Failed to delete directory: $path"
            return 1
        }
    else
        rm -f "$path" 2>/dev/null || {
            log "WARN" "Failed to delete file: $path"
            return 1
        }
    fi

    return 0
}

# Directory recreation with proper permissions
recreate_skeleton() {
    log "INFO" "Recreating directory skeleton..."

    # Core data directories
    mkdir -p "$IEC_DATA_OUTPUTS" "$IEC_DATA_UPLOADS" "$IEC_DATA_LOGS" \
             "$IEC_DATA_CACHE" "$IEC_DATA_STATE" "$IEC_MODELS" "$IEC_TMP" \
             "$IEC_POLICY_DIR" 2>/dev/null || true

    # Ensure proper permissions (readable/writable by user)
    chmod 755 "$IEC_DATA_ROOT" "$IEC_POLICY_DIR" 2>/dev/null || true
    chmod 750 "$IEC_DATA_OUTPUTS" "$IEC_DATA_UPLOADS" "$IEC_DATA_LOGS" \
              "$IEC_DATA_CACHE" "$IEC_DATA_STATE" "$IEC_MODELS" "$IEC_TMP" 2>/dev/null || true

    log "INFO" "Directory skeleton recreated"
}

# Cleanup reporting
generate_cleanup_report() {
    local mode="$1"
    local freed_gb="$2"
    local pinned_count="$3"
    local duration_sec="$4"
    local dry_run="${5:-$IEC_DRY_RUN}"

    local action=$([[ "$dry_run" == "1" ]] && echo "dry-run" || echo "cleaned")

    # Summary line (always printed)
    echo -e "${GREEN}✅ IEC $action mode=$mode freed=${freed_gb}GB pins=$pinned_count duration=${duration_sec}s${NC}"

    # Log to cleanup log
    log "INFO" "IEC $action mode=$mode freed=${freed_gb}GB pins=$pinned_count duration=${duration_sec}s"
}

# SSH environment detection
is_ssh_environment() {
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]
}

# Get the main script process PID (not shell PID)
get_script_pid() {
    if is_ssh_environment; then
        # In SSH environment, use current bash PID to avoid affecting SSH session
        echo "$BASHPID"
    else
        # In local environment, use shell PID
        echo "$$"
    fi
}

# Timeout handling
setup_timeout() {
    local timeout_sec="$1"
    local cleanup_func="${2:-cleanup_timeout}"

    if [[ "$timeout_sec" -gt 0 ]]; then
        # Check if we're in SSH environment and adjust behavior
        if is_ssh_environment; then
            log "DEBUG" "SSH environment detected - using file-based timeout: ${timeout_sec}s"
            # Use file-based timeout mechanism to avoid SSH session interference
            local timeout_flag="/tmp/iec-timeout-$$-$RANDOM"
            (
                sleep "$timeout_sec"
                log "WARN" "Cleanup timeout reached (${timeout_sec}s), stopping"
                touch "$timeout_flag"
                # Send signal to specific script process, not shell
                kill -USR1 $(get_script_pid) 2>/dev/null || true
            ) &
            local timeout_pid=$!
            trap "$cleanup_func $timeout_pid $timeout_flag" USR1
            echo "$timeout_pid"
        else
            log "DEBUG" "Local environment - using standard timeout: ${timeout_sec}s"
            (
                sleep "$timeout_sec"
                log "WARN" "Cleanup timeout reached (${timeout_sec}s), stopping"
                kill -USR1 $$ 2>/dev/null || true
            ) &
            local timeout_pid=$!
            trap "$cleanup_func $timeout_pid" USR1
            echo "$timeout_pid"
        fi
    fi
}

cleanup_timeout() {
    local timeout_pid="$1"
    local timeout_flag="$2"

    log "WARN" "Cleanup stopped due to timeout budget"

    # Clean up timeout process
    kill "$timeout_pid" 2>/dev/null || true

    # Clean up timeout flag file if it exists
    [[ -n "$timeout_flag" && -f "$timeout_flag" ]] && rm -f "$timeout_flag" 2>/dev/null || true

    # Use specific exit code for timeout
    exit 124  # timeout exit code
}

# Path centralization setup (for migration)
setup_centralized_paths() {
    log "INFO" "Setting up centralized paths..."

    # Ensure directories exist
    recreate_skeleton

    # Set up environment variables for centralized writes
    export XDG_CACHE_HOME="$IEC_DATA_CACHE"
    export HF_HOME="$IEC_DATA_CACHE/huggingface"
    export HUGGINGFACE_HUB_CACHE="$IEC_DATA_CACHE/huggingface"
    export TMPDIR="$IEC_TMP"

    # Create cache subdirectories
    mkdir -p "$HF_HOME" "$IEC_DATA_CACHE/pip" "$IEC_DATA_CACHE/xdg" 2>/dev/null || true

    log "INFO" "Centralized paths configured"
}

# Initialization
init_iec() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$IEC_CLEANUP_LOG")" 2>/dev/null || true

    # Set up paths if requested
    if [[ "${IEC_SETUP_PATHS:-1}" == "1" ]]; then
        setup_centralized_paths
    fi

    log "DEBUG" "IEC helpers initialized"
}

# Only run init if sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    exit 1
else
    init_iec
fi