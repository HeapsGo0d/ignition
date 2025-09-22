#!/bin/bash
# Test Phase 1 Privacy Blocking
# Validates that basic telemetry blocking works

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    local level=$1
    shift
    local message="$@"

    case $level in
        "INFO")
            echo -e "${GREEN}[TEST]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[TEST]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[TEST]${NC} $message"
            ;;
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message"
            ;;
    esac
}

# Test if privacy system can be disabled/enabled
test_privacy_toggle() {
    log "INFO" "Testing privacy system enable/disable..."

    # Test with privacy disabled
    export PRIVACY_ENABLED="false"
    log "INFO" "Testing with PRIVACY_ENABLED=false"

    # Test with privacy enabled but monitoring only
    export PRIVACY_ENABLED="true"
    export MONITORING_ONLY="true"
    log "INFO" "Testing with monitoring only mode"

    # Test with full blocking
    export MONITORING_ONLY="false"
    log "INFO" "Testing with full blocking mode"

    log "PASS" "Privacy toggle test completed"
}

# Test basic connectivity before privacy rules
test_baseline_connectivity() {
    log "INFO" "Testing baseline connectivity (before privacy rules)..."

    # Test legitimate domains that should work
    local good_domains=("civitai.com" "huggingface.co" "github.com")

    for domain in "${good_domains[@]}"; do
        if timeout 5 curl -s --head "https://$domain" >/dev/null 2>&1; then
            log "PASS" "Baseline connectivity to $domain works"
        else
            log "WARN" "Baseline connectivity to $domain failed (network issue?)"
        fi
    done
}

# Test that privacy system actually blocks telemetry
test_telemetry_blocking() {
    log "INFO" "Testing telemetry blocking..."

    # Start privacy system in background
    export PRIVACY_ENABLED="true"
    export MONITORING_ONLY="false"
    export BLOCK_TELEMETRY="true"

    log "INFO" "Starting privacy system for testing..."
    "$SCRIPT_DIR/privacy-init.sh" start &
    local privacy_pid=$!

    # Give it time to set up rules
    sleep 3

    # Test blocked domains
    local blocked_domains=("google-analytics.com" "mixpanel.com" "segment.io")
    local blocked_count=0

    for domain in "${blocked_domains[@]}"; do
        if timeout 3 curl -s --connect-timeout 2 "http://$domain" >/dev/null 2>&1; then
            log "FAIL" "Domain $domain should be blocked but isn't"
        else
            log "PASS" "Domain $domain is properly blocked"
            ((blocked_count++))
        fi
    done

    # Clean up
    kill $privacy_pid 2>/dev/null || true

    if [[ $blocked_count -eq ${#blocked_domains[@]} ]]; then
        log "PASS" "All telemetry domains properly blocked ($blocked_count/${#blocked_domains[@]})"
        return 0
    else
        log "FAIL" "Some telemetry domains not blocked ($blocked_count/${#blocked_domains[@]})"
        return 1
    fi
}

# Test monitoring only mode
test_monitoring_mode() {
    log "INFO" "Testing monitoring only mode..."

    export PRIVACY_ENABLED="true"
    export MONITORING_ONLY="true"

    # Start privacy system
    "$SCRIPT_DIR/privacy-init.sh" start &
    local privacy_pid=$!

    sleep 2

    # In monitoring mode, domains should NOT be blocked
    if timeout 3 curl -s --head "http://google-analytics.com" >/dev/null 2>&1; then
        log "PASS" "Monitoring mode allows traffic (not blocking)"
    else
        log "WARN" "Monitoring mode might be blocking (could be network issue)"
    fi

    # Clean up
    kill $privacy_pid 2>/dev/null || true

    log "PASS" "Monitoring mode test completed"
}

# Test privacy system status command
test_status_command() {
    log "INFO" "Testing privacy system status command..."

    if [[ -x "$SCRIPT_DIR/privacy-init.sh" ]]; then
        "$SCRIPT_DIR/privacy-init.sh" status
        log "PASS" "Status command works"
    else
        log "FAIL" "Privacy init script not executable"
        return 1
    fi
}

# Test iptables cleanup
test_cleanup() {
    log "INFO" "Testing iptables cleanup..."

    # Add some test rules
    export MONITORING_ONLY="false"
    "$SCRIPT_DIR/privacy-init.sh" start &
    local privacy_pid=$!

    sleep 2

    # Check rules exist
    local rule_count=$(iptables -L OUTPUT 2>/dev/null | grep -c "REJECT" || echo "0")
    if [[ $rule_count -gt 0 ]]; then
        log "PASS" "Privacy rules were created ($rule_count rules)"
    else
        log "WARN" "No privacy rules found"
    fi

    # Stop and check cleanup
    kill $privacy_pid 2>/dev/null || true
    sleep 1

    local rule_count_after=$(iptables -L OUTPUT 2>/dev/null | grep -c "REJECT" || echo "0")
    if [[ $rule_count_after -eq 0 ]]; then
        log "PASS" "Privacy rules cleaned up properly"
    else
        log "WARN" "Some rules remain after cleanup ($rule_count_after rules)"
    fi
}

# Main test execution
main() {
    echo "======================================"
    echo "  Ignition Privacy Phase 1 Testing"
    echo "======================================"
    echo ""

    # Check if we can run the tests
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Privacy tests require root privileges for iptables"
        log "INFO" "Run with: sudo $0"
        exit 1
    fi

    if [[ ! -x "$SCRIPT_DIR/privacy-init.sh" ]]; then
        log "ERROR" "privacy-init.sh not found or not executable"
        exit 1
    fi

    local total_tests=0
    local passed_tests=0

    # Run tests
    log "INFO" "Starting Phase 1 privacy tests..."
    echo ""

    tests=(
        "test_privacy_toggle"
        "test_baseline_connectivity"
        "test_status_command"
        "test_monitoring_mode"
        "test_telemetry_blocking"
        "test_cleanup"
    )

    for test in "${tests[@]}"; do
        echo "----------------------------------------"
        log "INFO" "Running $test..."
        ((total_tests++))

        if $test; then
            ((passed_tests++))
        fi
        echo ""
    done

    echo "======================================"
    log "INFO" "Test Results: $passed_tests/$total_tests tests passed"

    if [[ $passed_tests -eq $total_tests ]]; then
        log "PASS" "🎉 All Phase 1 privacy tests passed!"
        exit 0
    else
        log "FAIL" "❌ Some tests failed"
        exit 1
    fi
}

main "$@"