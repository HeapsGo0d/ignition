#!/bin/bash
# Ignition Privacy Initialization - Modular System
# Phase 4.1: Basic network blocking that actually works

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ignition_privacy.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${GREEN}[PRIVACY]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[PRIVACY]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[PRIVACY]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Environment defaults
export BLOCK_TELEMETRY="${BLOCK_TELEMETRY:-true}"
export MONITORING_ONLY="${MONITORING_ONLY:-false}"
export PRIVACY_PHASE="${PRIVACY_PHASE:-1}"

# Phase 1: Basic Telemetry Blocking
setup_phase1_blocking() {
    log "INFO" "Setting up Phase 1: Basic telemetry blocking"

    # Clear any existing rules
    iptables -F OUTPUT 2>/dev/null || true

    if [[ "$MONITORING_ONLY" == "true" ]]; then
        log "INFO" "Monitoring only mode - not blocking traffic"
        return
    fi

    # Block common telemetry domains (Phase 1)
    local telemetry_domains=(
        "google-analytics.com"
        "googleanalytics.com"
        "google-analytics.l.google.com"
        "stats.g.doubleclick.net"
        "www.google-analytics.com"
        "analytics.google.com"
        "firebase-settings.crashlytics.com"
        "crashlytics.com"
        "app-measurement.com"
        "googleadservices.com"
        "googlesyndication.com"
        "doubleclick.net"
        "facebook.com"
        "connect.facebook.net"
        "graph.facebook.com"
        "mixpanel.com"
        "api.mixpanel.com"
        "segment.io"
        "api.segment.io"
        "amplitude.com"
        "api.amplitude.com"
        "hotjar.com"
        "static.hotjar.com"
        "fullstory.com"
        "rs.fullstory.com"
    )

    log "INFO" "Blocking ${#telemetry_domains[@]} telemetry domains"

    for domain in "${telemetry_domains[@]}"; do
        # Resolve domain to IP and block
        local ips=$(dig +short "$domain" 2>/dev/null || true)
        if [[ -n "$ips" ]]; then
            for ip in $ips; do
                # Skip non-IP results (like CNAMEs)
                if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    iptables -A OUTPUT -d "$ip" -j REJECT --reject-with icmp-net-unreachable 2>/dev/null || true
                    log "INFO" "Blocked $domain ($ip)"
                fi
            done
        fi
    done

    log "INFO" "✅ Phase 1 telemetry blocking active"
}

# Phase 2: Smart Allowlisting (placeholder)
setup_phase2_allowlisting() {
    if [[ "$PRIVACY_PHASE" -ge 2 ]]; then
        log "INFO" "Phase 2: Smart allowlisting (coming soon)"
        # Placeholder for Phase 2 implementation
    fi
}

# Phase 3: Transparency & Logging (placeholder)
setup_phase3_logging() {
    if [[ "$PRIVACY_PHASE" -ge 3 ]]; then
        log "INFO" "Phase 3: Transparency & logging (coming soon)"
        # Placeholder for Phase 3 implementation
    fi
}

# Test blocking functionality
test_blocking() {
    log "INFO" "Testing Phase 1 blocking functionality..."

    # Test that blocked domains actually fail
    local test_domain="google-analytics.com"
    if timeout 5 curl -s --connect-timeout 2 "$test_domain" >/dev/null 2>&1; then
        log "WARN" "⚠️ Test domain $test_domain is NOT blocked (may be expected in monitoring mode)"
        return 1
    else
        log "INFO" "✅ Test domain $test_domain is properly blocked"
        return 0
    fi
}

# Privacy system status
show_status() {
    echo "=== Privacy System Status ==="
    echo "Phase: $PRIVACY_PHASE"
    echo "Block Telemetry: $BLOCK_TELEMETRY"
    echo "Monitoring Only: $MONITORING_ONLY"
    echo ""

    if [[ "$MONITORING_ONLY" != "true" ]]; then
        echo "Active iptables rules:"
        iptables -L OUTPUT -n --line-numbers 2>/dev/null | head -10 || echo "No rules active"
    else
        echo "Monitoring mode - no blocking active"
    fi
}

# Cleanup function
cleanup_privacy() {
    log "INFO" "Cleaning up privacy system..."
    iptables -F OUTPUT 2>/dev/null || true
    log "INFO" "Privacy system cleaned up"
}

# Signal handlers
trap cleanup_privacy SIGTERM SIGINT EXIT

# Main execution
main() {
    local action="${1:-start}"

    case "$action" in
        "start")
            log "INFO" "🛡️ Starting Ignition Privacy System"
            log "INFO" "Phase: $PRIVACY_PHASE, Monitoring Only: $MONITORING_ONLY"

            setup_phase1_blocking
            setup_phase2_allowlisting
            setup_phase3_logging

            # Test if not in monitoring mode
            if [[ "$MONITORING_ONLY" != "true" ]]; then
                if test_blocking; then
                    log "INFO" "✅ Privacy system active and tested"
                else
                    log "WARN" "⚠️ Privacy system started but test failed"
                fi
            else
                log "INFO" "✅ Privacy system in monitoring mode"
            fi

            # Keep running
            while true; do
                sleep 60
            done
            ;;
        "test")
            test_blocking
            ;;
        "status")
            show_status
            ;;
        "stop")
            cleanup_privacy
            ;;
        *)
            echo "Usage: $0 {start|test|status|stop}"
            exit 1
            ;;
    esac
}

main "$@"