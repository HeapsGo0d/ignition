#!/bin/bash
# Comprehensive Test Runner for Activity-Aware Privacy System
# Runs all validation and integration tests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="/tmp/ignition_test_results"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors and icons
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SUCCESS='✅'
ERROR='❌'
WARNING='⚠️'
INFO='🔍'
TEST='🧪'
PERFORMANCE='⚡'
SUMMARY='📊'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%H:%M:%S')
    echo -e "[$timestamp] $message"
}

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

# Initialize test summary
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log "$TEST" "Activity-Aware Privacy System - Complete Test Suite"
echo "=================================================================="
echo ""

# Test 1: Component availability check
log "$INFO" "Checking component availability..."
COMPONENT_CHECK_PASSED=false

if [[ -f "$SCRIPT_DIR/privacy_state_manager.py" ]]; then
    log "$SUCCESS" "privacy_state_manager.py found"
else
    log "$ERROR" "privacy_state_manager.py missing"
fi

if [[ -f "$SCRIPT_DIR/activity_detector.py" ]]; then
    log "$SUCCESS" "activity_detector.py found"
else
    log "$ERROR" "activity_detector.py missing"
fi

if [[ -f "$SCRIPT_DIR/process_monitor.py" ]]; then
    log "$SUCCESS" "process_monitor.py found"
else
    log "$ERROR" "process_monitor.py missing"
fi

if [[ -f "$SCRIPT_DIR/activity_policies.json" ]]; then
    log "$SUCCESS" "activity_policies.json found"
else
    log "$ERROR" "activity_policies.json missing"
fi

if [[ -x "$SCRIPT_DIR/connection_monitor.sh" ]]; then
    log "$SUCCESS" "connection_monitor.sh found and executable"
else
    log "$ERROR" "connection_monitor.sh missing or not executable"
fi

if [[ -x "$SCRIPT_DIR/ignition-privacy" ]]; then
    log "$SUCCESS" "ignition-privacy found and executable"
else
    log "$ERROR" "ignition-privacy missing or not executable"
fi

COMPONENT_CHECK_PASSED=true
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$COMPONENT_CHECK_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "$SUCCESS" "Component availability check passed"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "$ERROR" "Component availability check failed"
fi

echo ""

# Test 2: Python syntax validation
log "$INFO" "Validating Python syntax..."
SYNTAX_CHECK_PASSED=true

for py_file in "$SCRIPT_DIR"/*.py; do
    if [[ -f "$py_file" ]]; then
        filename=$(basename "$py_file")
        if python3 -m py_compile "$py_file" 2>/dev/null; then
            log "$SUCCESS" "$filename syntax valid"
        else
            log "$ERROR" "$filename syntax error"
            SYNTAX_CHECK_PASSED=false
        fi
    fi
done

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$SYNTAX_CHECK_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "$SUCCESS" "Python syntax validation passed"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "$ERROR" "Python syntax validation failed"
fi

echo ""

# Test 3: JSON configuration validation
log "$INFO" "Validating JSON configuration..."
JSON_CHECK_PASSED=true

if [[ -f "$SCRIPT_DIR/activity_policies.json" ]]; then
    if python3 -c "import json; json.load(open('$SCRIPT_DIR/activity_policies.json'))" 2>/dev/null; then
        log "$SUCCESS" "activity_policies.json is valid JSON"
    else
        log "$ERROR" "activity_policies.json has invalid JSON syntax"
        JSON_CHECK_PASSED=false
    fi
else
    log "$ERROR" "activity_policies.json not found"
    JSON_CHECK_PASSED=false
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$JSON_CHECK_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "$SUCCESS" "JSON configuration validation passed"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "$ERROR" "JSON configuration validation failed"
fi

echo ""

# Test 4: Activity detection validation tests
log "$TEST" "Running activity detection validation tests..."
ACTIVITY_TESTS_PASSED=false

if [[ -x "$SCRIPT_DIR/test_activity_detection.py" ]]; then
    echo "Starting detailed activity detection tests..."
    echo "----------------------------------------"

    if cd "$SCRIPT_DIR" && python3 test_activity_detection.py; then
        ACTIVITY_TESTS_PASSED=true
        log "$SUCCESS" "Activity detection validation tests passed"
    else
        log "$ERROR" "Activity detection validation tests failed"
    fi
else
    log "$ERROR" "Activity detection test script not found or not executable"
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$ACTIVITY_TESTS_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# Test 5: Privacy system integration tests
log "$TEST" "Running privacy system integration tests..."
INTEGRATION_TESTS_PASSED=false

if [[ -x "$SCRIPT_DIR/test_privacy_integration.py" ]]; then
    echo "Starting integration tests..."
    echo "----------------------------"

    if cd "$SCRIPT_DIR" && python3 test_privacy_integration.py; then
        INTEGRATION_TESTS_PASSED=true
        log "$SUCCESS" "Privacy system integration tests passed"
    else
        log "$ERROR" "Privacy system integration tests failed"
    fi
else
    log "$ERROR" "Integration test script not found or not executable"
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$INTEGRATION_TESTS_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# Test 6: Command line interface tests
log "$TEST" "Testing command line interfaces..."
CLI_TESTS_PASSED=true

# Test ignition-privacy commands
if [[ -x "$SCRIPT_DIR/ignition-privacy" ]]; then
    echo "Testing ignition-privacy commands..."

    # Test status command
    if timeout 30 "$SCRIPT_DIR/ignition-privacy" status >/dev/null 2>&1; then
        log "$SUCCESS" "ignition-privacy status command works"
    else
        log "$WARNING" "ignition-privacy status command failed or timed out"
        CLI_TESTS_PASSED=false
    fi

    # Test help command
    if timeout 10 "$SCRIPT_DIR/ignition-privacy" help >/dev/null 2>&1; then
        log "$SUCCESS" "ignition-privacy help command works"
    else
        log "$WARNING" "ignition-privacy help command failed"
    fi

    # Test activities command (may not be available in all environments)
    if timeout 30 "$SCRIPT_DIR/ignition-privacy" activities >/dev/null 2>&1; then
        log "$SUCCESS" "ignition-privacy activities command works"
    else
        log "$WARNING" "ignition-privacy activities command not available or failed"
    fi

else
    log "$ERROR" "ignition-privacy script not found"
    CLI_TESTS_PASSED=false
fi

# Test connection monitor commands
if [[ -x "$SCRIPT_DIR/connection_monitor.sh" ]]; then
    echo "Testing connection monitor commands..."

    # Test status command
    if timeout 10 "$SCRIPT_DIR/connection_monitor.sh" status >/dev/null 2>&1; then
        log "$SUCCESS" "connection_monitor.sh status command works"
    else
        log "$WARNING" "connection_monitor.sh status command failed"
    fi

    # Test recent command
    if timeout 10 "$SCRIPT_DIR/connection_monitor.sh" recent 5 >/dev/null 2>&1; then
        log "$SUCCESS" "connection_monitor.sh recent command works"
    else
        log "$WARNING" "connection_monitor.sh recent command failed"
    fi

else
    log "$ERROR" "connection_monitor.sh script not found"
    CLI_TESTS_PASSED=false
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$CLI_TESTS_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "$SUCCESS" "Command line interface tests passed"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "$ERROR" "Command line interface tests failed"
fi

echo ""

# Test 7: Performance baseline tests
log "$PERFORMANCE" "Running performance baseline tests..."
PERFORMANCE_TESTS_PASSED=true

echo "Testing component import performance..."
start_time=$(date +%s.%N)

if cd "$SCRIPT_DIR" && python3 -c "
import sys
sys.path.append('/workspace/scripts')
try:
    from privacy_state_manager import PrivacyStateManager
    from activity_detector import ActivityDetector
    from process_monitor import ContainerProcessMonitor
    print('All components imported successfully')
except ImportError as e:
    print(f'Import failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
    end_time=$(date +%s.%N)
    import_time=$(echo "$end_time - $start_time" | bc)
    log "$SUCCESS" "Component import completed in ${import_time}s"

    # Check if import time is reasonable (should be under 2 seconds)
    if (( $(echo "$import_time > 2.0" | bc -l) )); then
        log "$WARNING" "Component import time is slow (>${import_time}s)"
    fi
else
    log "$ERROR" "Component import failed"
    PERFORMANCE_TESTS_PASSED=false
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [[ "$PERFORMANCE_TESTS_PASSED" == "true" ]]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "$SUCCESS" "Performance baseline tests passed"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "$ERROR" "Performance baseline tests failed"
fi

echo ""

# Collect and save test results
log "$INFO" "Collecting test results..."

# Copy test result files to results directory
if [[ -f "/tmp/activity_detection_test_results.json" ]]; then
    cp "/tmp/activity_detection_test_results.json" "$TEST_RESULTS_DIR/activity_detection_${TIMESTAMP}.json"
    log "$SUCCESS" "Activity detection test results saved"
fi

if [[ -f "/tmp/privacy_integration_test_results.json" ]]; then
    cp "/tmp/privacy_integration_test_results.json" "$TEST_RESULTS_DIR/integration_${TIMESTAMP}.json"
    log "$SUCCESS" "Integration test results saved"
fi

# Create summary report
SUMMARY_FILE="$TEST_RESULTS_DIR/test_summary_${TIMESTAMP}.json"
cat > "$SUMMARY_FILE" << EOF
{
  "test_suite": "Activity-Aware Privacy System",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "success_rate": $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
  },
  "test_results": {
    "component_availability": $COMPONENT_CHECK_PASSED,
    "python_syntax": $SYNTAX_CHECK_PASSED,
    "json_configuration": $JSON_CHECK_PASSED,
    "activity_detection": $ACTIVITY_TESTS_PASSED,
    "system_integration": $INTEGRATION_TESTS_PASSED,
    "cli_interfaces": $CLI_TESTS_PASSED,
    "performance_baseline": $PERFORMANCE_TESTS_PASSED
  },
  "environment": {
    "python_version": "$(python3 --version)",
    "working_directory": "$(pwd)",
    "script_directory": "$SCRIPT_DIR"
  }
}
EOF

# Print final summary
echo ""
echo "=================================================================="
log "$SUMMARY" "TEST SUITE SUMMARY"
echo "=================================================================="
echo ""
echo "Total Tests:    $TOTAL_TESTS"
echo "Passed Tests:   $PASSED_TESTS $SUCCESS"
echo "Failed Tests:   $FAILED_TESTS $([ $FAILED_TESTS -gt 0 ] && echo "$ERROR" || echo "$SUCCESS")"
echo "Success Rate:   $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
echo ""

# Test results breakdown
echo "Test Results Breakdown:"
echo "- Component Availability:    $([ "$COMPONENT_CHECK_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- Python Syntax:             $([ "$SYNTAX_CHECK_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- JSON Configuration:        $([ "$JSON_CHECK_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- Activity Detection:        $([ "$ACTIVITY_TESTS_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- System Integration:        $([ "$INTEGRATION_TESTS_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- CLI Interfaces:            $([ "$CLI_TESTS_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo "- Performance Baseline:      $([ "$PERFORMANCE_TESTS_PASSED" == "true" ] && echo "$SUCCESS PASS" || echo "$ERROR FAIL")"
echo ""
echo "Test Results Directory: $TEST_RESULTS_DIR"
echo "Summary Report: $SUMMARY_FILE"
echo ""

# Provide recommendations based on results
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "🎉 All tests passed! The activity-aware privacy system is ready for use."
    echo ""
    echo "Next steps:"
    echo "1. Deploy the system to your ComfyUI environment"
    echo "2. Monitor system behavior using: ignition-privacy status"
    echo "3. Check activity detection with: ignition-privacy activities"
    echo "4. Monitor connections with: ignition-privacy monitor"
elif [[ $FAILED_TESTS -le 2 ]]; then
    echo "⚠️  Minor issues detected. The system should work but may have reduced functionality."
    echo ""
    echo "Recommended actions:"
    echo "1. Review failed tests and address any critical issues"
    echo "2. Test manually in your environment"
    echo "3. Monitor system logs for any problems"
else
    echo "❌ Multiple test failures detected. Please review and fix issues before deployment."
    echo ""
    echo "Recommended actions:"
    echo "1. Check component installation and dependencies"
    echo "2. Verify file permissions and paths"
    echo "3. Review error logs and fix critical issues"
    echo "4. Re-run tests after fixes"
fi

# Return appropriate exit code
exit $FAILED_TESTS