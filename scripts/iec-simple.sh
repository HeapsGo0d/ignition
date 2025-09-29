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
    local space_before=$(df -k /workspace 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local errors=0
    rm -rf "$IEC_DATA_ROOT/outputs"/* 2>/dev/null || ((errors++))
    rm -rf "$IEC_DATA_ROOT/uploads"/* 2>/dev/null || ((errors++))
    rm -rf "$IEC_TMP"/* 2>/dev/null || ((errors++))
    local space_after=$(df -k /workspace 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local freed=$((space_before - space_after))
    local freed_mb=$((freed / 1024))
    local duration=$(($(date +%s) - start))
    if [[ $errors -gt 0 ]]; then
        echo "⚠️  Basic cleanup completed with $errors errors in ${duration}s"
        return 1
    fi
    echo "✅ Basic cleanup complete in ${duration}s (freed ${freed_mb}MB)"
}
cleanup_enhanced() {
    echo "🧹 Enhanced cleanup: basic + caches"
    local basic_result=0
    cleanup_basic || basic_result=$?
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: caches"
        return 0
    fi
    local errors=0
    rm -rf "$IEC_DATA_ROOT/cache"/* 2>/dev/null || ((errors++))
    rm -rf /tmp/pip-* /root/.cache/pip ~/.cache/pip 2>/dev/null || ((errors++))
    if [[ $errors -gt 0 || $basic_result -ne 0 ]]; then
        echo "⚠️  Enhanced cleanup completed with issues"
        return 1
    fi
    echo "✅ Enhanced cleanup complete"
}
cleanup_nuclear() {
    echo "☢️  Nuclear cleanup: EVERYTHING"
    local enhanced_result=0
    cleanup_enhanced || enhanced_result=$?
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: models, state"
        return 0
    fi
    local errors=0
    if [[ "${IEC_DELETE_MODELS:-0}" == "1" ]]; then
        rm -rf "$IEC_MODELS"/* 2>/dev/null || ((errors++))
        echo "⚠️  Models deleted"
    else
        echo "ℹ️  Models preserved (set IEC_DELETE_MODELS=1 to delete)"
    fi
    rm -rf "$IEC_DATA_ROOT/state"/* 2>/dev/null || ((errors++))
    if [[ $errors -gt 0 || $enhanced_result -ne 0 ]]; then
        echo "⚠️  Nuclear cleanup completed with issues"
        return 1
    fi
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