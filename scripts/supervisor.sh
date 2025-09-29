#!/bin/bash
# ComfyUI Supervisor - Lightweight Process Manager with Signal Handling
# Maintains signal handlers while running ComfyUI as child process
# Ensures IEC cleanup executes on container termination

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFYUI_ROOT="/workspace/ComfyUI"
LOG_FILE="/tmp/ignition_startup.log"
CHILD_PID=""
CLEANUP_EXECUTED=0

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Cleanup function with IEC integration
cleanup() {
    local signal=${1:-"TERM"}

    # Prevent multiple cleanup executions
    if [[ $CLEANUP_EXECUTED -eq 1 ]]; then
        return 0
    fi
    CLEANUP_EXECUTED=1

    log "INFO" "🛑 Supervisor received SIG$signal - initiating shutdown sequence"

    # Gracefully terminate ComfyUI child process
    if [[ -n "$CHILD_PID" ]]; then
        log "INFO" "🔄 Gracefully terminating ComfyUI (PID: $CHILD_PID)"

        # Send TERM signal to child and wait briefly
        kill -TERM "$CHILD_PID" 2>/dev/null || true

        # Wait up to 10 seconds for graceful shutdown
        local wait_count=0
        while kill -0 "$CHILD_PID" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
            sleep 1
            ((wait_count++))
        done

        # Force kill if still running
        if kill -0 "$CHILD_PID" 2>/dev/null; then
            log "WARN" "⚠️ ComfyUI not responding - force terminating"
            kill -KILL "$CHILD_PID" 2>/dev/null || true
        fi

        log "INFO" "✅ ComfyUI terminated successfully"
    fi

    # Execute IEC cleanup if enabled
    if [[ "${IEC_MODE_ON_EXIT:-basic}" != "off" ]]; then
        log "INFO" "🧹 Running IEC cleanup mode: ${IEC_MODE_ON_EXIT}"

        # Execute cleanup with timeout
        timeout 45s "$SCRIPT_DIR/ignition-cleanup-simple" "${IEC_MODE_ON_EXIT}" 2>/dev/null || {
            log "WARN" "⚠️ IEC cleanup timed out (45s) or failed during shutdown"
        }
    else
        log "INFO" "🚫 IEC cleanup disabled (IEC_MODE_ON_EXIT=off)"
    fi

    log "INFO" "🏁 Shutdown sequence complete"
    exit 0
}

# Signal handlers
trap 'cleanup TERM' SIGTERM
trap 'cleanup INT' SIGINT
trap 'cleanup HUP' SIGHUP

# Child process reaping handler
reap_child() {
    if [[ -n "$CHILD_PID" ]]; then
        wait "$CHILD_PID" 2>/dev/null || true
        local exit_code=$?
        log "INFO" "🔄 ComfyUI process exited with code: $exit_code"

        # If child exits normally, we should also exit
        if [[ $CLEANUP_EXECUTED -eq 0 ]]; then
            cleanup "CHILD_EXIT"
        fi
    fi
}

trap 'reap_child' SIGCHLD

# Validate environment
validate_environment() {
    if [[ -z "${PYBIN:-}" ]]; then
        log "ERROR" "❌ PYBIN environment variable not set"
        exit 1
    fi

    if [[ ! -d "$COMFYUI_ROOT" ]]; then
        log "ERROR" "❌ ComfyUI directory not found: $COMFYUI_ROOT"
        exit 1
    fi

    if [[ ! -f "$COMFYUI_ROOT/main.py" ]]; then
        log "ERROR" "❌ ComfyUI main.py not found: $COMFYUI_ROOT/main.py"
        exit 1
    fi

    if [[ ! -x "$SCRIPT_DIR/ignition-cleanup-simple" ]]; then
        log "WARN" "⚠️ IEC cleanup script not found - cleanup will be skipped"
    fi
}

# Start ComfyUI as child process
start_comfyui() {
    log "INFO" "🎨 Supervisor starting ComfyUI..."
    log "INFO" "  • Working directory: $COMFYUI_ROOT"
    log "INFO" "  • Python binary: $PYBIN"
    log "INFO" "  • Listen address: 0.0.0.0:${COMFYUI_PORT:-8188}"

    cd "$COMFYUI_ROOT"

    # Start ComfyUI in background and capture PID
    "$PYBIN" main.py --listen "0.0.0.0" --port "${COMFYUI_PORT:-8188}" &
    CHILD_PID=$!

    log "INFO" "✅ ComfyUI started successfully (PID: $CHILD_PID)"
    log "INFO" "🔒 Supervisor maintaining signal handlers for cleanup"
}

# Main supervisor loop
main() {
    log "INFO" "🚀 Starting ComfyUI Supervisor v1.0"
    log "INFO" "  • Supervisor PID: $$"
    log "INFO" "  • IEC cleanup mode: ${IEC_MODE_ON_EXIT:-basic}"

    # Validate environment before starting
    validate_environment

    # Start ComfyUI as child process
    start_comfyui

    # Main supervisor loop - wait for signals or child exit
    log "INFO" "🔄 Supervisor entering main loop - waiting for signals"
    while true; do
        if [[ -n "$CHILD_PID" ]] && ! kill -0 "$CHILD_PID" 2>/dev/null; then
            log "WARN" "⚠️ ComfyUI process died unexpectedly"
            cleanup "CHILD_DIED"
        fi
        sleep 1
    done
}

# Execute main function
main "$@"