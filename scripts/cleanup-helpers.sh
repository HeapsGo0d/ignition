#!/bin/bash
# Intelligent Ephemeral Cleanup (IEC) - Core Utilities
# Shared functions for path management, size calculation, and safe cleanup operations

set -euo pipefail

# IEC Configuration - Default paths for centralized writes
readonly IEC_DATA_ROOT="/workspace/data"
readonly IEC_DATA_OUTPUTS="$IEC_DATA_ROOT/outputs"
readonly IEC_DATA_UPLOADS="$IEC_DATA_ROOT/uploads"
readonly IEC_DATA_LOGS="$IEC_DATA_ROOT/logs"
readonly IEC_DATA_CACHE="$IEC_DATA_ROOT/cache"
readonly IEC_DATA_STATE="$IEC_DATA_ROOT/state"
readonly IEC_MODELS="/workspace/models"
readonly IEC_TMP="/workspace/tmp"

# IEC Runtime Configuration
readonly IEC_POLICY_DIR="/workspace/policy"
readonly IEC_PINS_FILE="$IEC_POLICY_DIR/pins.txt"
readonly IEC_CLEANUP_LOG="$IEC_DATA_LOGS/cleanup.log"
readonly IEC_LOCK_FILE="/tmp/cleanup.lock"
readonly IEC_SESSION_LOCK="/tmp/stale_session.lock"

# Environment defaults
export IEC_MODE_ON_EXIT="${IEC_MODE_ON_EXIT:-basic}"
export IEC_BUDGET_GB="${IEC_BUDGET_GB:-10}"
export IEC_TIMEOUT_SEC="${IEC_TIMEOUT_SEC:-30}"
export IEC_DRY_RUN="${IEC_DRY_RUN:-0}"
export CLEANUP_IGNORE_PINS="${CLEANUP_IGNORE_PINS:-0}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

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

# Size calculation utilities
get_size_gb() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sb "$path" 2>/dev/null | awk '{printf "%.2f", $1/1024/1024/1024}'
    else
        echo "0.00"
    fi
}

get_size_mb() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sb "$path" 2>/dev/null | awk '{printf "%.1f", $1/1024/1024}'
    else
        echo "0.0"
    fi
}

count_files() {
    local path="$1"
    if [[ -d "$path" ]]; then
        find "$path" -type f 2>/dev/null | wc -l
    else
        echo "0"
    fi
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
        "/workspace/ComfyUI"
        "/workspace/scripts"
        ""
    )

    for forbidden in "${forbidden_paths[@]}"; do
        if [[ "$path" == "$forbidden" ]] || [[ "$path" == "$forbidden"/* ]]; then
            log "ERROR" "Forbidden path: $path"
            return 1
        fi
    done

    # Resolve path safely
    local resolved_path
    if [[ -e "$path" ]]; then
        resolved_path=$(realpath "$path" 2>/dev/null || echo "$path")
    else
        resolved_path="$path"
    fi

    # Check if under /workspace (unless specifically allowing root paths)
    if [[ "$allow_root_paths" != "true" ]] && [[ "$resolved_path" != "/workspace"* ]]; then
        log "ERROR" "Path outside workspace: $resolved_path"
        return 1
    fi

    log "DEBUG" "Path validated: $resolved_path"
    return 0
}

# Pin system
load_pins() {
    local pins=()

    if [[ -f "$IEC_PINS_FILE" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            pins+=("$line")
        done < "$IEC_PINS_FILE"
        log "DEBUG" "Loaded ${#pins[@]} pins from $IEC_PINS_FILE"
    else
        log "DEBUG" "No pins file found at $IEC_PINS_FILE"
    fi

    printf '%s\n' "${pins[@]}"
}

is_pinned() {
    local path="$1"
    local pins

    # If ignoring pins, nothing is pinned
    if [[ "$CLEANUP_IGNORE_PINS" == "1" ]]; then
        return 1
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

    while [[ $count -lt $timeout ]]; do
        if (set -C; echo $$ > "$IEC_LOCK_FILE") 2>/dev/null; then
            log "DEBUG" "Acquired cleanup lock"
            return 0
        fi

        # Check if existing lock is stale
        if [[ -f "$IEC_LOCK_FILE" ]]; then
            local lock_pid=$(cat "$IEC_LOCK_FILE" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log "WARN" "Removing stale lock (PID $lock_pid)"
                rm -f "$IEC_LOCK_FILE" 2>/dev/null || true
                continue
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

    # Brief pause for file handles to close
    sleep 1
    log "INFO" "Services quiesced"
}

# Safe deletion with validation
safe_delete() {
    local path="$1"
    local mode="${2:-basic}"
    local dry_run="${3:-$IEC_DRY_RUN}"

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

    # Calculate size before deletion
    local size_mb=$(get_size_mb "$path")
    local file_count=$(count_files "$path")

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

# Timeout handling
setup_timeout() {
    local timeout_sec="$1"
    local cleanup_func="${2:-cleanup_timeout}"

    if [[ "$timeout_sec" -gt 0 ]]; then
        log "DEBUG" "Setting up timeout: ${timeout_sec}s"
        (
            sleep "$timeout_sec"
            log "WARN" "Cleanup timeout reached (${timeout_sec}s), stopping"
            kill -USR1 $$ 2>/dev/null || true
        ) &
        local timeout_pid=$!
        trap "$cleanup_func $timeout_pid" USR1
        echo "$timeout_pid"
    fi
}

cleanup_timeout() {
    local timeout_pid="$1"
    log "WARN" "Cleanup stopped due to timeout budget"
    kill "$timeout_pid" 2>/dev/null || true
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