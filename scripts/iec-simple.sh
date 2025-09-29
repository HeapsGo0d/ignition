#!/bin/bash
# IEC Simple - Minimal, Fast, Reliable Cleanup
set -euo pipefail

# Simple environment setup
IEC_DATA_ROOT="/workspace/data"
IEC_MODELS="/workspace/models"
IEC_TMP="/workspace/tmp"
cleanup_basic() {
    echo "🧹 Basic cleanup: outputs, uploads, temp"
    local start=$(date +%s)
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would delete: outputs, uploads, tmp"
        return 0
    fi
    rm -rf "$IEC_DATA_ROOT/outputs"/* 2>/dev/null || true
    rm -rf "$IEC_DATA_ROOT/uploads"/* 2>/dev/null || true
    rm -rf "$IEC_TMP"/* 2>/dev/null || true
    local duration=$(($(date +%s) - start))
    echo "✅ Basic cleanup complete in ${duration}s"
}
cleanup_enhanced() {
    echo "🧹 Enhanced cleanup: basic + caches"
    cleanup_basic
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: caches"
        return 0
    fi
    rm -rf "$IEC_DATA_ROOT/cache"/* 2>/dev/null || true
    rm -rf /tmp/pip-* /root/.cache/pip ~/.cache/pip 2>/dev/null || true
    echo "✅ Enhanced cleanup complete"
}
cleanup_nuclear() {
    echo "☢️  Nuclear cleanup: EVERYTHING"
    cleanup_enhanced
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: models, state"
        return 0
    fi
    if [[ "${CLEANUP_DELETE_MODELS:-0}" == "1" ]]; then
        rm -rf "$IEC_MODELS"/* 2>/dev/null || true
        echo "⚠️  Models deleted"
    fi
    rm -rf "$IEC_DATA_ROOT/state"/* 2>/dev/null || true
    echo "✅ Nuclear cleanup complete"
}
run_with_timeout() {
    local timeout_sec=$1; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=3s "${timeout_sec}s" "$@"
    else
        "$@"
    fi
}
main() {
    local mode="${1:-basic}"
    case "$mode" in
        basic|enhanced|nuclear)
            cleanup_"$mode"
            ;;
        *)
            echo "Usage: $0 {basic|enhanced|nuclear}"
            echo "Environment: IEC_DRY_RUN=1 for dry run"
            exit 1
            ;;
    esac
}
main "$@"