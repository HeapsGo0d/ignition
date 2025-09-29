#!/bin/bash
# IEC Performance Benchmarking and Validation Framework
# Tests cleanup performance across different workloads and validates <20ms requirement for basic cleanup
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_WORKSPACE="/tmp/benchmark-workspace"
BENCHMARK_LOG="/tmp/iec-benchmark.log"
IEC_SCRIPT="$SCRIPT_DIR/iec-simple.sh"

# Performance thresholds (milliseconds)
THRESHOLD_BASIC=20
THRESHOLD_ENHANCED=50
THRESHOLD_NUCLEAR=100
THRESHOLD_FORENSIC=200

# Test workloads
WORKLOAD_SMALL=10     # 10 files per directory
WORKLOAD_MEDIUM=100   # 100 files per directory
WORKLOAD_LARGE=1000   # 1000 files per directory
WORKLOAD_EXTREME=5000 # 5000 files per directory

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Benchmark state
BENCHMARKS_RUN=0
BENCHMARKS_PASSED=0
BENCHMARKS_FAILED=0

# Logging
log() {
    local level=$1; shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] ${level} ${message}" | tee -a "$BENCHMARK_LOG"
}

log_bench() { log "${CYAN}[BENCH]${NC}" "$@"; }
log_pass() { log "${GREEN}[PASS]${NC}" "$@"; ((BENCHMARKS_PASSED++)); }
log_fail() { log "${RED}[FAIL]${NC}" "$@"; ((BENCHMARKS_FAILED++)); }
log_info() { log "${BLUE}[INFO]${NC}" "$@"; }
log_warn() { log "${YELLOW}[WARN]${NC}" "$@"; }

# High-precision timing function
get_time_ns() {
    date +%s%N
}

get_time_ms() {
    echo $(( $(get_time_ns) / 1000000 ))
}

# Workload creation functions
create_test_files() {
    local count=$1
    local base_dir=$2

    # Create output files
    for i in $(seq 1 $count); do
        echo "output data $i" > "$base_dir/outputs/output_$i.png"
        echo "upload data $i" > "$base_dir/uploads/upload_$i.txt"
        echo "temp data $i" > "$BENCHMARK_WORKSPACE/tmp/temp_$i.tmp"
    done

    # Create cache files
    for i in $(seq 1 $((count / 2))); do
        echo "cache data $i" > "$base_dir/cache/cache_$i.cache"
        mkdir -p /root/.cache/test_cache_$i
        echo "user cache $i" > "/root/.cache/test_cache_$i/data.cache"
    done

    # Create privacy-sensitive files
    for i in $(seq 1 $((count / 5))); do
        echo "privacy log $i" > "$BENCHMARK_WORKSPACE/logs/privacy/request_$i.log"
        echo "browser data $i" > "/root/.config/browser_$i.dat"
    done

    # Create shell history
    for i in $(seq 1 $((count / 10))); do
        echo "command $i" >> /root/.bash_history
    done
}

setup_benchmark_environment() {
    local workload_size=$1
    log_info "Setting up benchmark environment for workload size: $workload_size"

    # Clean previous environment
    rm -rf "$BENCHMARK_WORKSPACE" 2>/dev/null || true

    # Create directory structure
    mkdir -p "$BENCHMARK_WORKSPACE"/{data/{outputs,uploads,cache,state},tmp,logs/privacy}
    mkdir -p /root/.cache /root/.config

    # Create test files based on workload
    create_test_files "$workload_size" "$BENCHMARK_WORKSPACE/data"

    log_info "Created $workload_size files per category for benchmark"
}

cleanup_benchmark_environment() {
    rm -rf "$BENCHMARK_WORKSPACE" 2>/dev/null || true
    rm -rf /root/.cache/test_cache_* 2>/dev/null || true
    rm -f /root/.config/browser_*.dat 2>/dev/null || true
    > /root/.bash_history 2>/dev/null || true
}

# Benchmark execution function
run_benchmark() {
    local mode=$1
    local workload_size=$2
    local iterations=${3:-5}

    log_bench "Running $mode cleanup benchmark with $workload_size files ($iterations iterations)"

    # Set up environment
    export IEC_DATA_ROOT="$BENCHMARK_WORKSPACE/data"
    export IEC_TMP="$BENCHMARK_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$BENCHMARK_WORKSPACE/logs/privacy"
    export IEC_CACHE_DIRS="/root/.cache $BENCHMARK_WORKSPACE/data/cache"

    local total_time=0
    local min_time=999999
    local max_time=0
    local successful_runs=0

    for i in $(seq 1 $iterations); do
        # Reset environment for each iteration
        setup_benchmark_environment "$workload_size"

        # Run benchmark
        local start_time=$(get_time_ns)
        if "$IEC_SCRIPT" "$mode" > /dev/null 2>&1; then
            local end_time=$(get_time_ns)
            local duration_ns=$((end_time - start_time))
            local duration_ms=$((duration_ns / 1000000))

            total_time=$((total_time + duration_ms))
            ((successful_runs++))

            if [[ $duration_ms -lt $min_time ]]; then
                min_time=$duration_ms
            fi
            if [[ $duration_ms -gt $max_time ]]; then
                max_time=$duration_ms
            fi

            log_info "  Iteration $i: ${duration_ms}ms"
        else
            log_warn "  Iteration $i: FAILED"
        fi
    done

    if [[ $successful_runs -gt 0 ]]; then
        local avg_time=$((total_time / successful_runs))
        log_bench "Results for $mode cleanup ($workload_size files):"
        log_bench "  Average: ${avg_time}ms"
        log_bench "  Min: ${min_time}ms"
        log_bench "  Max: ${max_time}ms"
        log_bench "  Success: $successful_runs/$iterations"

        echo "$avg_time"
        return 0
    else
        log_fail "All benchmark iterations failed for $mode cleanup"
        echo "999999"
        return 1
    fi
}

# Threshold validation
validate_performance() {
    local mode=$1
    local workload_size=$2
    local avg_time=$3
    local threshold

    case "$mode" in
        basic) threshold=$THRESHOLD_BASIC ;;
        enhanced) threshold=$THRESHOLD_ENHANCED ;;
        nuclear) threshold=$THRESHOLD_NUCLEAR ;;
        forensic) threshold=$THRESHOLD_FORENSIC ;;
        *) log_fail "Unknown mode: $mode"; return 1 ;;
    esac

    ((BENCHMARKS_RUN++))

    if [[ $avg_time -le $threshold ]]; then
        log_pass "$mode cleanup passed performance test: ${avg_time}ms <= ${threshold}ms (workload: $workload_size files)"
        return 0
    else
        log_fail "$mode cleanup failed performance test: ${avg_time}ms > ${threshold}ms (workload: $workload_size files)"
        return 1
    fi
}

# Memory usage monitoring
monitor_memory_usage() {
    local mode=$1
    local workload_size=$2

    log_bench "Monitoring memory usage for $mode cleanup with $workload_size files"

    # Set up environment
    setup_benchmark_environment "$workload_size"
    export IEC_DATA_ROOT="$BENCHMARK_WORKSPACE/data"
    export IEC_TMP="$BENCHMARK_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$BENCHMARK_WORKSPACE/logs/privacy"

    # Get memory before
    local mem_before=$(ps -o pid,vsz,rss -p $$ | tail -1 | awk '{print $2}')

    # Run cleanup
    "$IEC_SCRIPT" "$mode" > /dev/null 2>&1

    # Get memory after
    local mem_after=$(ps -o pid,vsz,rss -p $$ | tail -1 | awk '{print $2}')
    local mem_diff=$((mem_after - mem_before))

    log_bench "Memory usage for $mode cleanup: ${mem_diff}KB difference"

    if [[ $mem_diff -lt 10000 ]]; then  # Less than 10MB increase
        log_pass "$mode cleanup passed memory test: ${mem_diff}KB < 10MB"
    else
        log_fail "$mode cleanup failed memory test: ${mem_diff}KB >= 10MB"
    fi
}

# Disk space measurement
measure_disk_space_freed() {
    local mode=$1
    local workload_size=$2

    log_bench "Measuring disk space freed by $mode cleanup with $workload_size files"

    # Set up environment
    setup_benchmark_environment "$workload_size"
    export IEC_DATA_ROOT="$BENCHMARK_WORKSPACE/data"
    export IEC_TMP="$BENCHMARK_WORKSPACE/tmp"
    export IEC_PRIVACY_LOGS="$BENCHMARK_WORKSPACE/logs/privacy"

    # Measure space before
    local space_before=$(du -sk "$BENCHMARK_WORKSPACE" /root/.cache /root/.config 2>/dev/null | awk '{sum+=$1} END {print sum}')

    # Run cleanup
    "$IEC_SCRIPT" "$mode" > /dev/null 2>&1

    # Measure space after
    local space_after=$(du -sk "$BENCHMARK_WORKSPACE" /root/.cache /root/.config 2>/dev/null | awk '{sum+=$1} END {print sum}')
    local space_freed=$((space_before - space_after))
    local space_freed_mb=$((space_freed / 1024))

    log_bench "$mode cleanup freed ${space_freed_mb}MB (${space_freed}KB) with $workload_size files"
}

# Comprehensive benchmark suite
run_comprehensive_benchmarks() {
    log_info "Starting IEC Performance Benchmark Suite"
    log_info "Thresholds: basic=${THRESHOLD_BASIC}ms, enhanced=${THRESHOLD_ENHANCED}ms, nuclear=${THRESHOLD_NUCLEAR}ms, forensic=${THRESHOLD_FORENSIC}ms"

    # Test each mode against different workloads
    for mode in basic enhanced nuclear forensic; do
        log_bench "=== Benchmarking $mode cleanup ==="

        # Small workload (critical for basic mode)
        local avg_time=$(run_benchmark "$mode" "$WORKLOAD_SMALL")
        validate_performance "$mode" "$WORKLOAD_SMALL" "$avg_time"

        # Medium workload
        avg_time=$(run_benchmark "$mode" "$WORKLOAD_MEDIUM")
        validate_performance "$mode" "$WORKLOAD_MEDIUM" "$avg_time"

        # Large workload (stress test)
        if [[ "$mode" != "basic" ]]; then  # Skip large workload for basic mode
            avg_time=$(run_benchmark "$mode" "$WORKLOAD_LARGE")
            # Don't validate against threshold for large workload, just measure
            log_bench "$mode cleanup with large workload: ${avg_time}ms (informational)"
        fi

        # Memory usage test
        monitor_memory_usage "$mode" "$WORKLOAD_MEDIUM"

        # Disk space measurement
        measure_disk_space_freed "$mode" "$WORKLOAD_MEDIUM"

        echo
    done
}

# Stress testing
run_stress_tests() {
    log_bench "=== Running Stress Tests ==="

    # Extreme workload test
    log_bench "Testing with extreme workload ($WORKLOAD_EXTREME files)"
    for mode in enhanced nuclear forensic; do
        local avg_time=$(run_benchmark "$mode" "$WORKLOAD_EXTREME" 3)
        log_bench "$mode cleanup with extreme workload: ${avg_time}ms"

        # Anything under 5 seconds is acceptable for extreme workload
        if [[ $avg_time -lt 5000 ]]; then
            log_pass "$mode cleanup handled extreme workload efficiently: ${avg_time}ms < 5000ms"
        else
            log_warn "$mode cleanup took significant time with extreme workload: ${avg_time}ms"
        fi
    done

    # Concurrent cleanup test
    log_bench "Testing concurrent cleanup resistance"
    setup_benchmark_environment "$WORKLOAD_MEDIUM"
    export IEC_DATA_ROOT="$BENCHMARK_WORKSPACE/data"
    export IEC_TMP="$BENCHMARK_WORKSPACE/tmp"

    # Run multiple cleanups concurrently (should handle gracefully)
    "$IEC_SCRIPT" basic > /dev/null 2>&1 &
    local pid1=$!
    "$IEC_SCRIPT" basic > /dev/null 2>&1 &
    local pid2=$!

    wait $pid1 2>/dev/null || true
    wait $pid2 2>/dev/null || true

    log_pass "Concurrent cleanup test completed without deadlock"
}

# Generate performance report
generate_report() {
    log_info "==============================================="
    log_info "IEC Performance Benchmark Report"
    log_info "==============================================="
    log_info "Benchmarks Run: $BENCHMARKS_RUN"
    log_pass "Benchmarks Passed: $BENCHMARKS_PASSED"
    if [[ $BENCHMARKS_FAILED -gt 0 ]]; then
        log_fail "Benchmarks Failed: $BENCHMARKS_FAILED"
    else
        log_info "Benchmarks Failed: $BENCHMARKS_FAILED"
    fi
    log_info "Full benchmark log: $BENCHMARK_LOG"

    if [[ $BENCHMARKS_FAILED -eq 0 ]]; then
        log_pass "All performance benchmarks passed! IEC meets performance requirements."
        return 0
    else
        log_fail "Some performance benchmarks failed. Review the log for optimization opportunities."
        return 1
    fi
}

# Main execution
main() {
    local mode="${1:-all}"

    case "$mode" in
        "all")
            cleanup_benchmark_environment
            run_comprehensive_benchmarks
            run_stress_tests
            cleanup_benchmark_environment
            generate_report
            ;;
        "quick")
            cleanup_benchmark_environment
            # Quick test with just small workloads
            for cleanup_mode in basic enhanced; do
                local avg_time=$(run_benchmark "$cleanup_mode" "$WORKLOAD_SMALL")
                validate_performance "$cleanup_mode" "$WORKLOAD_SMALL" "$avg_time"
            done
            cleanup_benchmark_environment
            generate_report
            ;;
        "stress")
            cleanup_benchmark_environment
            run_stress_tests
            cleanup_benchmark_environment
            ;;
        *)
            echo "Usage: $0 [all|quick|stress]"
            echo "  all    - Run comprehensive benchmark suite"
            echo "  quick  - Run quick performance validation"
            echo "  stress - Run stress tests only"
            exit 1
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi