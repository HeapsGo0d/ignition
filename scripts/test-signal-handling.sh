#!/bin/bash
# Signal Handling Test Suite - Validates IEC supervisor pattern and RunPod SIGTERM behavior
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_WORKSPACE="/tmp/test-workspace"
TEST_LOG="/tmp/signal-test.log"
SUPERVISOR_SCRIPT="$SCRIPT_DIR/supervisor.sh"
IEC_SCRIPT="$SCRIPT_DIR/iec-simple.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log() {
    local level=$1; shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] ${level} ${message}" | tee -a "$TEST_LOG"
}

log_test() { log "${BLUE}[TEST]${NC}" "$@"; }
log_pass() { log "${GREEN}[PASS]${NC}" "$@"; ((TESTS_PASSED++)); }
log_fail() { log "${RED}[FAIL]${NC}" "$@"; ((TESTS_FAILED++)); }
log_info() { log "${YELLOW}[INFO]${NC}" "$@"; }

# Test utilities
setup_test_environment() {
    log_info "Setting up test environment at $TEST_WORKSPACE"

    # Create test workspace structure
    mkdir -p "$TEST_WORKSPACE"/{data/{outputs,uploads},tmp,logs/privacy,.cache}

    # Create test files to be cleaned
    echo "test output" > "$TEST_WORKSPACE/data/outputs/test.png"
    echo "test upload" > "$TEST_WORKSPACE/data/uploads/test.txt"
    echo "test temp" > "$TEST_WORKSPACE/tmp/test.tmp"
    echo "test cache" > "$TEST_WORKSPACE/.cache/test.cache"
    echo "test privacy log" > "$TEST_WORKSPACE/logs/privacy/test.log"

    # Mock bash history
    touch /root/.bash_history
    echo "ls -la" >> /root/.bash_history
    echo "cd /workspace" >> /root/.bash_history

    log_info "Test environment created with mock files"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment"
    rm -rf "$TEST_WORKSPACE" 2>/dev/null || true
    rm -f "$TEST_LOG.backup" 2>/dev/null || true
}

# Mock ComfyUI process for testing
create_mock_comfyui() {
    local mock_script="/tmp/mock-comfyui.py"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env python3
import signal
import time
import sys

def signal_handler(signum, frame):
    print(f"Mock ComfyUI received signal {signum}", flush=True)
    if signum == signal.SIGTERM:
        print("Mock ComfyUI gracefully shutting down...", flush=True)
        sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

print("Mock ComfyUI started, PID:", sys.argv[1] if len(sys.argv) > 1 else "unknown", flush=True)
print("Listening on 0.0.0.0:8188", flush=True)

try:
    while True:
        time.sleep(1)
        print("Mock ComfyUI heartbeat", flush=True)
except KeyboardInterrupt:
    print("Mock ComfyUI interrupted", flush=True)
    sys.exit(0)
EOF
    chmod +x "$mock_script"
    echo "$mock_script"
}

# Test 1: Basic IEC cleanup functionality
test_iec_cleanup_basic() {
    log_test "Testing basic IEC cleanup functionality"
    ((TESTS_RUN++))

    # Set up test environment variables
    export IEC_DATA_ROOT="$TEST_WORKSPACE/data"
    export IEC_TMP="$TEST_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$TEST_WORKSPACE/logs/privacy"

    # Run basic cleanup
    if "$IEC_SCRIPT" basic > /tmp/cleanup-test.log 2>&1; then
        # Check if files were cleaned
        if [[ ! -f "$TEST_WORKSPACE/data/outputs/test.png" ]] && \
           [[ ! -f "$TEST_WORKSPACE/data/uploads/test.txt" ]] && \
           [[ ! -f "$TEST_WORKSPACE/tmp/test.tmp" ]] && \
           [[ ! -f "$TEST_WORKSPACE/logs/privacy/test.log" ]]; then
            log_pass "Basic IEC cleanup removed target files correctly"
            return 0
        else
            log_fail "Basic IEC cleanup did not remove all target files"
            return 1
        fi
    else
        log_fail "Basic IEC cleanup script failed to execute"
        cat /tmp/cleanup-test.log
        return 1
    fi
}

# Test 2: IEC dry-run mode
test_iec_dry_run() {
    log_test "Testing IEC dry-run mode"
    ((TESTS_RUN++))

    # Recreate test files
    echo "test output" > "$TEST_WORKSPACE/data/outputs/test.png"
    echo "test upload" > "$TEST_WORKSPACE/data/uploads/test.txt"

    # Set dry-run mode
    export IEC_DRY_RUN=1
    export IEC_DATA_ROOT="$TEST_WORKSPACE/data"
    export IEC_TMP="$TEST_WORKSPACE/tmp"

    # Run dry-run cleanup
    if "$IEC_SCRIPT" basic > /tmp/dry-run-test.log 2>&1; then
        # Check if files still exist (should not be deleted in dry-run)
        if [[ -f "$TEST_WORKSPACE/data/outputs/test.png" ]] && \
           [[ -f "$TEST_WORKSPACE/data/uploads/test.txt" ]]; then
            log_pass "IEC dry-run mode preserved files correctly"
            unset IEC_DRY_RUN
            return 0
        else
            log_fail "IEC dry-run mode incorrectly deleted files"
            unset IEC_DRY_RUN
            return 1
        fi
    else
        log_fail "IEC dry-run mode failed to execute"
        cat /tmp/dry-run-test.log
        unset IEC_DRY_RUN
        return 1
    fi
}

# Test 3: Supervisor script validation
test_supervisor_validation() {
    log_test "Testing supervisor script validation"
    ((TESTS_RUN++))

    # Test without required environment variables
    if ! PYBIN="" COMFYUI_ROOT="" "$SUPERVISOR_SCRIPT" 2>/tmp/supervisor-validation.log; then
        if grep -q "PYBIN environment variable not set" /tmp/supervisor-validation.log; then
            log_pass "Supervisor validation correctly detects missing PYBIN"
            return 0
        else
            log_fail "Supervisor validation failed with wrong error message"
            cat /tmp/supervisor-validation.log
            return 1
        fi
    else
        log_fail "Supervisor validation should have failed without environment variables"
        return 1
    fi
}

# Test 4: Mock supervisor signal handling
test_supervisor_signal_handling() {
    log_test "Testing supervisor signal handling with mock ComfyUI"
    ((TESTS_RUN++))

    local mock_comfyui=$(create_mock_comfyui)

    # Set up environment for supervisor
    export PYBIN="$mock_comfyui"
    export COMFYUI_ROOT="$TEST_WORKSPACE"
    export COMFYUI_PORT="8188"
    export IEC_MODE_ON_EXIT="basic"
    export IEC_DATA_ROOT="$TEST_WORKSPACE/data"
    export IEC_TMP="$TEST_WORKSPACE/tmp"

    # Create mock main.py for supervisor validation
    echo "# Mock ComfyUI main.py" > "$TEST_WORKSPACE/main.py"

    # Start supervisor in background
    "$SUPERVISOR_SCRIPT" > /tmp/supervisor-test.log 2>&1 &
    local supervisor_pid=$!

    log_info "Started supervisor (PID: $supervisor_pid), waiting for startup..."
    sleep 3

    # Send SIGTERM to supervisor to simulate RunPod termination
    log_info "Sending SIGTERM to supervisor to simulate RunPod shutdown"
    kill -TERM "$supervisor_pid" 2>/dev/null || true

    # Wait for supervisor to handle signal and cleanup
    local wait_count=0
    while kill -0 "$supervisor_pid" 2>/dev/null && [[ $wait_count -lt 15 ]]; do
        sleep 1
        ((wait_count++))
    done

    # Check if supervisor terminated properly
    if ! kill -0 "$supervisor_pid" 2>/dev/null; then
        # Check log for proper shutdown sequence
        if grep -q "Supervisor received SIGTERM" /tmp/supervisor-test.log && \
           grep -q "Running IEC cleanup" /tmp/supervisor-test.log; then
            log_pass "Supervisor handled SIGTERM and executed IEC cleanup"
            return 0
        else
            log_fail "Supervisor did not execute proper shutdown sequence"
            cat /tmp/supervisor-test.log
            return 1
        fi
    else
        log_fail "Supervisor did not terminate after SIGTERM"
        kill -KILL "$supervisor_pid" 2>/dev/null || true
        return 1
    fi
}

# Test 5: RunPod SIGTERM simulation
test_runpod_sigterm_simulation() {
    log_test "Testing complete RunPod SIGTERM simulation"
    ((TESTS_RUN++))

    local mock_comfyui=$(create_mock_comfyui)

    # Set up complete environment
    export PYBIN="$mock_comfyui"
    export COMFYUI_ROOT="$TEST_WORKSPACE"
    export COMFYUI_PORT="8188"
    export IEC_MODE_ON_EXIT="enhanced"
    export IEC_DATA_ROOT="$TEST_WORKSPACE/data"
    export IEC_TMP="$TEST_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$TEST_WORKSPACE/logs/privacy"

    # Create test files for cleanup verification
    echo "test output" > "$TEST_WORKSPACE/data/outputs/test.png"
    echo "test privacy log" > "$TEST_WORKSPACE/logs/privacy/request.log"

    # Create mock main.py
    echo "# Mock ComfyUI main.py" > "$TEST_WORKSPACE/main.py"

    # Start supervisor (simulating container startup)
    "$SUPERVISOR_SCRIPT" > /tmp/runpod-simulation.log 2>&1 &
    local supervisor_pid=$!

    log_info "Started supervisor for RunPod simulation (PID: $supervisor_pid)"
    sleep 3

    # Simulate RunPod sending SIGTERM to container
    log_info "Simulating RunPod SIGTERM (container termination)"
    kill -TERM "$supervisor_pid"

    # Wait for graceful shutdown
    local wait_count=0
    while kill -0 "$supervisor_pid" 2>/dev/null && [[ $wait_count -lt 20 ]]; do
        sleep 1
        ((wait_count++))
    done

    # Verify results
    local success=true

    # Check supervisor terminated
    if kill -0 "$supervisor_pid" 2>/dev/null; then
        log_fail "Supervisor did not terminate during RunPod simulation"
        kill -KILL "$supervisor_pid" 2>/dev/null || true
        success=false
    fi

    # Check cleanup was executed
    if [[ -f "$TEST_WORKSPACE/data/outputs/test.png" ]] || \
       [[ -f "$TEST_WORKSPACE/logs/privacy/request.log" ]]; then
        log_fail "RunPod simulation did not clean up test files"
        success=false
    fi

    # Check log contains proper shutdown sequence
    if ! grep -q "Supervisor received SIGTERM" /tmp/runpod-simulation.log || \
       ! grep -q "Running IEC cleanup mode: enhanced" /tmp/runpod-simulation.log; then
        log_fail "RunPod simulation did not execute proper shutdown sequence"
        cat /tmp/runpod-simulation.log
        success=false
    fi

    if [[ "$success" == "true" ]]; then
        log_pass "RunPod SIGTERM simulation completed successfully"
        return 0
    else
        return 1
    fi
}

# Test 6: Performance validation
test_cleanup_performance() {
    log_test "Testing cleanup performance requirements"
    ((TESTS_RUN++))

    # Set up larger test environment
    export IEC_DATA_ROOT="$TEST_WORKSPACE/data"
    export IEC_TMP="$TEST_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$TEST_WORKSPACE/logs/privacy"

    # Create many test files
    for i in {1..100}; do
        echo "test file $i" > "$TEST_WORKSPACE/data/outputs/test_$i.txt"
        echo "temp file $i" > "$TEST_WORKSPACE/tmp/temp_$i.tmp"
    done

    # Time basic cleanup
    local start_time=$(date +%s%N)
    "$IEC_SCRIPT" basic > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    log_info "Basic cleanup took ${duration_ms}ms with 100 test files"

    # Check performance requirement (<50ms for basic)
    if [[ $duration_ms -lt 50 ]]; then
        log_pass "Basic cleanup met performance requirement (${duration_ms}ms < 50ms)"
        return 0
    else
        log_fail "Basic cleanup exceeded performance requirement (${duration_ms}ms >= 50ms)"
        return 1
    fi
}

# Main test execution
run_all_tests() {
    log_info "Starting IEC Signal Handling Test Suite"
    log_info "Test workspace: $TEST_WORKSPACE"
    log_info "Test log: $TEST_LOG"

    # Setup
    cleanup_test_environment
    setup_test_environment

    # Run tests
    test_iec_cleanup_basic
    setup_test_environment  # Reset for next test
    test_iec_dry_run
    test_supervisor_validation
    test_supervisor_signal_handling
    setup_test_environment  # Reset for RunPod test
    test_runpod_sigterm_simulation
    setup_test_environment  # Reset for performance test
    test_cleanup_performance

    # Cleanup
    cleanup_test_environment

    # Results
    echo
    log_info "==============================================="
    log_info "IEC Signal Handling Test Suite Results"
    log_info "==============================================="
    log_info "Tests Run: $TESTS_RUN"
    log_pass "Tests Passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_fail "Tests Failed: $TESTS_FAILED"
    else
        log_info "Tests Failed: $TESTS_FAILED"
    fi
    log_info "Full log available at: $TEST_LOG"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_pass "All tests passed! IEC signal handling is working correctly."
        exit 0
    else
        log_fail "Some tests failed. Review the log for details."
        exit 1
    fi
}

# Execute tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi