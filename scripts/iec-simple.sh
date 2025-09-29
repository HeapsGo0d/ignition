#!/bin/bash
# IEC Simple - Minimal, Fast, Reliable Cleanup with Privacy-Sensitive Scope
set -euo pipefail

# Environment setup
IEC_DATA_ROOT="/workspace/data"
IEC_MODELS="/workspace/models"
IEC_TMP="/workspace/tmp"
IEC_PRIVACY_LOGS="/workspace/logs/privacy"
IEC_CACHE_DIRS="/workspace/.cache /root/.cache /tmp"
IEC_BROWSER_DIRS="/root/.config/google-chrome /root/.mozilla /root/.config/chromium"
IEC_SESSION_DIRS="/root/.ssh /root/.config /root/.local"
cleanup_basic() {
    echo "🧹 Basic cleanup: outputs, uploads, temp, recent session data"
    local start=$(date +%s)
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would delete: outputs, uploads, tmp, bash_history, recent logs"
        return 0
    fi
    local space_before=$(df -k /workspace 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local errors=0

    # Original basic targets
    rm -rf "$IEC_DATA_ROOT/outputs"/* 2>/dev/null || ((errors++))
    rm -rf "$IEC_DATA_ROOT/uploads"/* 2>/dev/null || ((errors++))
    rm -rf "$IEC_TMP"/* 2>/dev/null || ((errors++))

    # Privacy-sensitive additions for basic cleanup
    rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || ((errors++))
    rm -rf "$IEC_PRIVACY_LOGS"/*.log 2>/dev/null || ((errors++))
    rm -rf /tmp/ignition_*.log /tmp/privacy_*.log 2>/dev/null || ((errors++))

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
    echo "🧹 Enhanced cleanup: basic + caches + browser data + session artifacts"
    local basic_result=0
    cleanup_basic || basic_result=$?
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: caches, browser data, config files"
        return 0
    fi
    local errors=0

    # Original enhanced targets
    rm -rf "$IEC_DATA_ROOT/cache"/* 2>/dev/null || ((errors++))
    rm -rf /tmp/pip-* /root/.cache/pip ~/.cache/pip 2>/dev/null || ((errors++))

    # Privacy-sensitive additions for enhanced cleanup
    for cache_dir in $IEC_CACHE_DIRS; do
        [[ -d "$cache_dir" ]] && rm -rf "$cache_dir"/* 2>/dev/null || ((errors++))
    done

    # Browser data cleanup
    for browser_dir in $IEC_BROWSER_DIRS; do
        [[ -d "$browser_dir" ]] && rm -rf "$browser_dir"/* 2>/dev/null || ((errors++))
    done

    # Session and config cleanup
    rm -rf /root/.config/Code /root/.vscode* 2>/dev/null || ((errors++))
    rm -rf /root/.local/share/recently-used.xbel 2>/dev/null || ((errors++))
    rm -f /root/.python_history /root/.lesshst 2>/dev/null || ((errors++))

    if [[ $errors -gt 0 || $basic_result -ne 0 ]]; then
        echo "⚠️  Enhanced cleanup completed with issues"
        return 1
    fi
    echo "✅ Enhanced cleanup complete"
}
cleanup_nuclear() {
    echo "☢️  Nuclear cleanup: enhanced + models + state + deep session cleanup"
    local enhanced_result=0
    cleanup_enhanced || enhanced_result=$?
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also delete: models, state, deep session data"
        return 0
    fi
    local errors=0

    # Original nuclear targets
    if [[ "${IEC_DELETE_MODELS:-0}" == "1" ]]; then
        rm -rf "$IEC_MODELS"/* 2>/dev/null || ((errors++))
        echo "⚠️  Models deleted"
    else
        echo "ℹ️  Models preserved (set IEC_DELETE_MODELS=1 to delete)"
    fi
    rm -rf "$IEC_DATA_ROOT/state"/* 2>/dev/null || ((errors++))

    # Privacy-sensitive additions for nuclear cleanup
    for session_dir in $IEC_SESSION_DIRS; do
        [[ -d "$session_dir" ]] && rm -rf "$session_dir"/* 2>/dev/null || ((errors++))
    done

    # Deep privacy cleanup
    rm -rf "$IEC_PRIVACY_LOGS" 2>/dev/null || ((errors++))
    rm -rf /var/log/* /var/tmp/* 2>/dev/null || ((errors++))
    rm -f /root/.viminfo /root/.nano_history 2>/dev/null || ((errors++))

    # Process and system state
    rm -rf /tmp/* /var/tmp/* 2>/dev/null || ((errors++))

    if [[ $errors -gt 0 || $enhanced_result -ne 0 ]]; then
        echo "⚠️  Nuclear cleanup completed with issues"
        return 1
    fi
    echo "✅ Nuclear cleanup complete"
}

cleanup_forensic() {
    echo "🔬 Forensic cleanup: nuclear + secure deletion + metadata scrubbing"
    local nuclear_result=0
    cleanup_nuclear || nuclear_result=$?
    if [[ "${IEC_DRY_RUN:-0}" == "1" ]]; then
        echo "  [DRY] Would also perform: secure deletion, metadata scrubbing, journal cleanup"
        return 0
    fi
    local errors=0

    # Secure deletion attempts (if shred available)
    if command -v shred >/dev/null 2>&1; then
        echo "🔒 Attempting secure deletion of sensitive files..."
        find /root -name "*.key" -o -name "*.pem" -o -name "*.p12" -o -name "*.pfx" 2>/dev/null | \
            while read -r sensitive_file; do
                shred -vfz -n 3 "$sensitive_file" 2>/dev/null || ((errors++))
            done
    fi

    # Metadata and journal cleanup
    journalctl --vacuum-time=1s 2>/dev/null || ((errors++))
    rm -rf /var/log/journal/* 2>/dev/null || ((errors++))

    # Extended filesystem cleanup
    find /workspace -name "*.tmp" -o -name "*.temp" -o -name "*.swp" -o -name "*~" \
        -exec rm -f {} \; 2>/dev/null || ((errors++))

    # Clear environment history
    unset HISTFILE
    history -c 2>/dev/null || true

    if [[ $errors -gt 0 || $nuclear_result -ne 0 ]]; then
        echo "⚠️  Forensic cleanup completed with issues"
        return 1
    fi
    echo "✅ Forensic cleanup complete"
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
        basic|enhanced|nuclear|forensic)
            cleanup_"$mode"
            ;;
        *)
            echo "Usage: $0 {basic|enhanced|nuclear|forensic}"
            echo "Cleanup modes:"
            echo "  basic    - outputs, uploads, temp, bash history, recent logs"
            echo "  enhanced - basic + caches, browser data, session artifacts"
            echo "  nuclear  - enhanced + models*, state, deep session cleanup"
            echo "  forensic - nuclear + secure deletion, metadata scrubbing"
            echo "Environment:"
            echo "  IEC_DRY_RUN=1 for dry run"
            echo "  IEC_DELETE_MODELS=1 to delete models in nuclear/forensic"
            exit 1
            ;;
    esac
}
main "$@"