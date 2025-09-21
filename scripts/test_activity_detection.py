#!/usr/bin/env python3
"""
Validation Test Suite for Activity Detection System
Tests accuracy, confidence scoring, and policy decisions
"""

import sys
import os
import time
import json
import subprocess
import tempfile
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
from pathlib import Path

# Add scripts directory to path
sys.path.append('/workspace/scripts')

try:
    from activity_detector import ActivityDetector, ActivityType, DetectedActivity, PolicyAction
    from process_monitor import ContainerProcessMonitor, ProcessInfo
    ACTIVITY_DETECTION_AVAILABLE = True
except ImportError:
    ACTIVITY_DETECTION_AVAILABLE = False
    print("⚠️  Activity detection components not available - running basic tests only")

@dataclass
class TestResult:
    """Result of a single test case"""
    test_name: str
    passed: bool
    expected_activity: Optional[str]
    detected_activity: Optional[str]
    expected_confidence: Optional[float]
    actual_confidence: Optional[float]
    expected_policy: Optional[str]
    actual_policy: Optional[str]
    error_message: Optional[str] = None
    execution_time: float = 0.0

@dataclass
class TestSummary:
    """Summary of all test results"""
    total_tests: int
    passed_tests: int
    failed_tests: int
    accuracy_rate: float
    avg_execution_time: float
    test_results: List[TestResult]

class ActivityDetectionValidator:
    """Comprehensive validation suite for activity detection"""

    def __init__(self):
        self.results: List[TestResult] = []
        self.detector = None
        self.monitor = None

        if ACTIVITY_DETECTION_AVAILABLE:
            try:
                self.detector = ActivityDetector()
                self.monitor = ContainerProcessMonitor()
                print("✅ Activity detection components initialized")
            except Exception as e:
                print(f"❌ Failed to initialize activity detection: {e}")
                ACTIVITY_DETECTION_AVAILABLE = False

    def run_all_tests(self) -> TestSummary:
        """Run complete validation test suite"""
        print("🧪 Starting Activity Detection Validation Tests")
        print("=" * 60)

        # Basic component tests
        self._test_component_initialization()
        self._test_policy_thresholds()
        self._test_confidence_calculations()

        if ACTIVITY_DETECTION_AVAILABLE:
            # Activity pattern tests
            self._test_pip_install_detection()
            self._test_git_operations_detection()
            self._test_download_activity_detection()
            self._test_unknown_activity_classification()

            # Integration tests
            self._test_process_monitoring_integration()
            self._test_confidence_modifiers()
            self._test_health_check_behavior()

            # Policy decision tests
            self._test_policy_action_mapping()
            self._test_domain_allowlist_logic()

        # Generate summary
        return self._generate_summary()

    def _test_component_initialization(self):
        """Test basic component initialization"""
        start_time = time.time()

        try:
            # Test that components can be imported and initialized
            if ACTIVITY_DETECTION_AVAILABLE:
                assert self.detector is not None, "ActivityDetector initialization failed"
                assert self.monitor is not None, "ProcessMonitor initialization failed"

                result = TestResult(
                    test_name="Component Initialization",
                    passed=True,
                    expected_activity=None,
                    detected_activity=None,
                    expected_confidence=None,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    execution_time=time.time() - start_time
                )
            else:
                result = TestResult(
                    test_name="Component Initialization",
                    passed=False,
                    expected_activity=None,
                    detected_activity=None,
                    expected_confidence=None,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    error_message="Activity detection components not available",
                    execution_time=time.time() - start_time
                )

        except Exception as e:
            result = TestResult(
                test_name="Component Initialization",
                passed=False,
                expected_activity=None,
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_policy_thresholds(self):
        """Test policy action threshold mappings"""
        start_time = time.time()

        test_cases = [
            (0.95, PolicyAction.ALLOW_UNRESTRICTED),
            (0.85, PolicyAction.ALLOW_WITH_MONITORING),
            (0.65, PolicyAction.STRICT_ALLOWLIST),
            (0.25, PolicyAction.EMERGENCY_REVIEW),
            (0.05, PolicyAction.BLOCK_ALL)
        ]

        try:
            if ACTIVITY_DETECTION_AVAILABLE:
                for confidence, expected_policy in test_cases:
                    actual_policy = self.detector.get_policy_action(confidence)

                    passed = actual_policy == expected_policy
                    result = TestResult(
                        test_name=f"Policy Threshold {confidence}",
                        passed=passed,
                        expected_activity=None,
                        detected_activity=None,
                        expected_confidence=confidence,
                        actual_confidence=confidence,
                        expected_policy=expected_policy.value,
                        actual_policy=actual_policy.value,
                        execution_time=(time.time() - start_time) / len(test_cases)
                    )

                    self.results.append(result)
                    self._log_test_result(result)
            else:
                result = TestResult(
                    test_name="Policy Thresholds",
                    passed=False,
                    expected_activity=None,
                    detected_activity=None,
                    expected_confidence=None,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    error_message="Activity detection not available",
                    execution_time=time.time() - start_time
                )
                self.results.append(result)
                self._log_test_result(result)

        except Exception as e:
            result = TestResult(
                test_name="Policy Thresholds",
                passed=False,
                expected_activity=None,
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )
            self.results.append(result)
            self._log_test_result(result)

    def _test_confidence_calculations(self):
        """Test confidence calculation logic"""
        start_time = time.time()

        if not ACTIVITY_DETECTION_AVAILABLE:
            result = TestResult(
                test_name="Confidence Calculations",
                passed=False,
                expected_activity=None,
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message="Activity detection not available",
                execution_time=time.time() - start_time
            )
            self.results.append(result)
            self._log_test_result(result)
            return

        try:
            # Test pip install confidence
            mock_process = ProcessInfo(
                pid=12345,
                name="pip",
                cmdline=["pip", "install", "torch"],
                cwd="/workspace/ComfyUI",
                ppid=1,
                create_time=time.time()
            )

            activity = self.detector._classify_activity(mock_process)

            expected_activity = ActivityType.PIP_INSTALL
            expected_confidence_min = 0.8  # Should be high confidence

            passed = (activity and
                     activity.activity_type == expected_activity and
                     activity.confidence >= expected_confidence_min)

            result = TestResult(
                test_name="Pip Install Confidence",
                passed=passed,
                expected_activity=expected_activity.value if expected_activity else None,
                detected_activity=activity.activity_type.value if activity else None,
                expected_confidence=expected_confidence_min,
                actual_confidence=activity.confidence if activity else None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Confidence Calculations",
                passed=False,
                expected_activity=None,
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_pip_install_detection(self):
        """Test pip install activity detection"""
        start_time = time.time()

        test_cases = [
            (["pip", "install", "torch"], "/workspace", ActivityType.PIP_INSTALL, 0.9),
            (["pip3", "install", "transformers"], "/ComfyUI", ActivityType.PIP_INSTALL, 0.95),
            (["python", "-m", "pip", "install", "numpy"], "/workspace", ActivityType.PIP_INSTALL, 0.9),
            (["pip", "upgrade", "torch"], "/workspace", ActivityType.PIP_UPGRADE, 0.85),
        ]

        for cmdline, cwd, expected_type, min_confidence in test_cases:
            try:
                mock_process = ProcessInfo(
                    pid=12345,
                    name=cmdline[0],
                    cmdline=cmdline,
                    cwd=cwd,
                    ppid=1,
                    create_time=time.time()
                )

                activity = self.detector._classify_activity(mock_process)

                passed = (activity and
                         activity.activity_type == expected_type and
                         activity.confidence >= min_confidence)

                result = TestResult(
                    test_name=f"Pip Detection: {' '.join(cmdline)}",
                    passed=passed,
                    expected_activity=expected_type.value,
                    detected_activity=activity.activity_type.value if activity else None,
                    expected_confidence=min_confidence,
                    actual_confidence=activity.confidence if activity else None,
                    expected_policy=None,
                    actual_policy=None,
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            except Exception as e:
                result = TestResult(
                    test_name=f"Pip Detection: {' '.join(cmdline)}",
                    passed=False,
                    expected_activity=expected_type.value,
                    detected_activity=None,
                    expected_confidence=min_confidence,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    error_message=str(e),
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            self.results.append(result)
            self._log_test_result(result)

    def _test_git_operations_detection(self):
        """Test git operation detection"""
        start_time = time.time()

        test_cases = [
            (["git", "clone", "https://github.com/user/repo.git"], ActivityType.GIT_CLONE, 0.8),
            (["git", "pull", "origin", "main"], ActivityType.GIT_PULL, 0.85),
            (["git", "fetch", "--all"], ActivityType.GIT_PULL, 0.85),
        ]

        for cmdline, expected_type, min_confidence in test_cases:
            try:
                mock_process = ProcessInfo(
                    pid=12346,
                    name="git",
                    cmdline=cmdline,
                    cwd="/workspace/ComfyUI/custom_nodes",
                    ppid=1,
                    create_time=time.time()
                )

                activity = self.detector._classify_activity(mock_process)

                passed = (activity and
                         activity.activity_type == expected_type and
                         activity.confidence >= min_confidence)

                result = TestResult(
                    test_name=f"Git Detection: {' '.join(cmdline)}",
                    passed=passed,
                    expected_activity=expected_type.value,
                    detected_activity=activity.activity_type.value if activity else None,
                    expected_confidence=min_confidence,
                    actual_confidence=activity.confidence if activity else None,
                    expected_policy=None,
                    actual_policy=None,
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            except Exception as e:
                result = TestResult(
                    test_name=f"Git Detection: {' '.join(cmdline)}",
                    passed=False,
                    expected_activity=expected_type.value,
                    detected_activity=None,
                    expected_confidence=min_confidence,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    error_message=str(e),
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            self.results.append(result)
            self._log_test_result(result)

    def _test_download_activity_detection(self):
        """Test download activity detection"""
        start_time = time.time()

        test_cases = [
            (["wget", "https://example.com/file.zip"], ActivityType.WEB_DOWNLOAD, 0.4),
            (["curl", "-O", "https://example.com/model.safetensors"], ActivityType.WEB_DOWNLOAD, 0.4),
            (["aria2c", "https://civitai.com/model.ckpt"], ActivityType.WEB_DOWNLOAD, 0.6),  # Higher confidence from ComfyUI dir
        ]

        for cmdline, expected_type, min_confidence in test_cases:
            try:
                mock_process = ProcessInfo(
                    pid=12347,
                    name=cmdline[0],
                    cmdline=cmdline,
                    cwd="/workspace/ComfyUI" if "aria2c" in cmdline[0] else "/tmp",
                    ppid=1,
                    create_time=time.time()
                )

                activity = self.detector._classify_activity(mock_process)

                passed = (activity and
                         activity.activity_type == expected_type and
                         activity.confidence >= min_confidence)

                result = TestResult(
                    test_name=f"Download Detection: {' '.join(cmdline)}",
                    passed=passed,
                    expected_activity=expected_type.value,
                    detected_activity=activity.activity_type.value if activity else None,
                    expected_confidence=min_confidence,
                    actual_confidence=activity.confidence if activity else None,
                    expected_policy=None,
                    actual_policy=None,
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            except Exception as e:
                result = TestResult(
                    test_name=f"Download Detection: {' '.join(cmdline)}",
                    passed=False,
                    expected_activity=expected_type.value,
                    detected_activity=None,
                    expected_confidence=min_confidence,
                    actual_confidence=None,
                    expected_policy=None,
                    actual_policy=None,
                    error_message=str(e),
                    execution_time=(time.time() - start_time) / len(test_cases)
                )

            self.results.append(result)
            self._log_test_result(result)

    def _test_unknown_activity_classification(self):
        """Test unknown activity classification"""
        start_time = time.time()

        try:
            mock_process = ProcessInfo(
                pid=12348,
                name="unknown_binary",
                cmdline=["unknown_binary", "--weird-flag"],
                cwd="/tmp",
                ppid=1,
                create_time=time.time()
            )

            activity = self.detector._classify_activity(mock_process)

            expected_type = ActivityType.UNKNOWN
            max_confidence = 0.2  # Should be low confidence

            passed = (activity and
                     activity.activity_type == expected_type and
                     activity.confidence <= max_confidence)

            result = TestResult(
                test_name="Unknown Activity Classification",
                passed=passed,
                expected_activity=expected_type.value,
                detected_activity=activity.activity_type.value if activity else None,
                expected_confidence=max_confidence,
                actual_confidence=activity.confidence if activity else None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Unknown Activity Classification",
                passed=False,
                expected_activity=ActivityType.UNKNOWN.value,
                detected_activity=None,
                expected_confidence=0.2,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_process_monitoring_integration(self):
        """Test integration with process monitoring"""
        start_time = time.time()

        try:
            # Test that process monitor can find current processes
            processes = self.monitor.get_active_processes()

            # Should find at least the current Python process
            found_python = any(proc.name in ['python', 'python3'] for proc in processes)

            result = TestResult(
                test_name="Process Monitor Integration",
                passed=found_python,
                expected_activity="python process detected",
                detected_activity=f"{len(processes)} processes found",
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Process Monitor Integration",
                passed=False,
                expected_activity="python process detected",
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_confidence_modifiers(self):
        """Test confidence modifier application"""
        start_time = time.time()

        try:
            # Test ComfyUI directory modifier
            base_process = ProcessInfo(
                pid=12349,
                name="pip",
                cmdline=["pip", "install", "torch"],
                cwd="/tmp",  # Non-ComfyUI directory
                ppid=1,
                create_time=time.time()
            )

            comfyui_process = ProcessInfo(
                pid=12350,
                name="pip",
                cmdline=["pip", "install", "torch"],
                cwd="/workspace/ComfyUI",  # ComfyUI directory
                ppid=1,
                create_time=time.time()
            )

            base_activity = self.detector._classify_activity(base_process)
            comfyui_activity = self.detector._classify_activity(comfyui_process)

            # ComfyUI directory should have higher confidence
            passed = (base_activity and comfyui_activity and
                     comfyui_activity.confidence > base_activity.confidence)

            result = TestResult(
                test_name="Confidence Modifiers (ComfyUI Directory)",
                passed=passed,
                expected_activity="higher confidence in ComfyUI dir",
                detected_activity=f"base: {base_activity.confidence:.2f}, comfyui: {comfyui_activity.confidence:.2f}" if base_activity and comfyui_activity else "detection failed",
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Confidence Modifiers",
                passed=False,
                expected_activity="higher confidence in ComfyUI dir",
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_health_check_behavior(self):
        """Test health check behavior"""
        start_time = time.time()

        try:
            # Get health status
            health = self.detector.health_check.get_health_status()

            # Should have basic health data structure
            expected_keys = ['health_score', 'short_window_health', 'medium_window_health', 'long_window_health']
            has_expected_keys = all(key in health for key in expected_keys)

            # Health score should be between 0 and 1
            valid_health_score = 0 <= health.get('health_score', -1) <= 1

            passed = has_expected_keys and valid_health_score

            result = TestResult(
                test_name="Health Check Behavior",
                passed=passed,
                expected_activity="valid health structure",
                detected_activity=f"health_score: {health.get('health_score', 'missing')}",
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Health Check Behavior",
                passed=False,
                expected_activity="valid health structure",
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_policy_action_mapping(self):
        """Test policy action to domain mapping"""
        start_time = time.time()

        try:
            # Test pip install activity - should map to specific domains
            mock_process = ProcessInfo(
                pid=12351,
                name="pip",
                cmdline=["pip", "install", "torch"],
                cwd="/workspace/ComfyUI",
                ppid=1,
                create_time=time.time()
            )

            activity = self.detector._classify_activity(mock_process)

            # Should have allowed domains for pip
            expected_domains = ["pypi.org", "files.pythonhosted.org"]
            has_expected_domains = activity and any(domain in activity.allowed_domains for domain in expected_domains)

            result = TestResult(
                test_name="Policy Action Domain Mapping",
                passed=has_expected_domains,
                expected_activity="pip with pypi domains",
                detected_activity=f"domains: {activity.allowed_domains if activity else 'none'}",
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Policy Action Domain Mapping",
                passed=False,
                expected_activity="pip with pypi domains",
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _test_domain_allowlist_logic(self):
        """Test domain allowlist logic"""
        start_time = time.time()

        try:
            # Create activity and check domain permissions
            mock_process = ProcessInfo(
                pid=12352,
                name="git",
                cmdline=["git", "clone", "https://github.com/user/repo.git"],
                cwd="/workspace/ComfyUI/custom_nodes",
                ppid=1,
                create_time=time.time()
            )

            activity = self.detector._classify_activity(mock_process)

            # Git activity should allow github.com
            allows_github = activity and "github.com" in activity.allowed_domains
            # But should not allow random domains
            allows_random = activity and "random-site.com" in activity.allowed_domains

            passed = allows_github and not allows_random

            result = TestResult(
                test_name="Domain Allowlist Logic",
                passed=passed,
                expected_activity="github allowed, random blocked",
                detected_activity=f"domains: {activity.allowed_domains if activity else 'none'}",
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                execution_time=time.time() - start_time
            )

        except Exception as e:
            result = TestResult(
                test_name="Domain Allowlist Logic",
                passed=False,
                expected_activity="github allowed, random blocked",
                detected_activity=None,
                expected_confidence=None,
                actual_confidence=None,
                expected_policy=None,
                actual_policy=None,
                error_message=str(e),
                execution_time=time.time() - start_time
            )

        self.results.append(result)
        self._log_test_result(result)

    def _log_test_result(self, result: TestResult):
        """Log individual test result"""
        status = "✅ PASS" if result.passed else "❌ FAIL"
        print(f"{status} {result.test_name}")

        if result.error_message:
            print(f"     Error: {result.error_message}")

        if result.expected_activity and result.detected_activity:
            print(f"     Expected: {result.expected_activity}")
            print(f"     Detected: {result.detected_activity}")

        if result.expected_confidence is not None and result.actual_confidence is not None:
            print(f"     Confidence: {result.actual_confidence:.3f} (expected: {result.expected_confidence:.3f})")

        if result.execution_time > 0:
            print(f"     Time: {result.execution_time:.3f}s")

        print()

    def _generate_summary(self) -> TestSummary:
        """Generate test summary"""
        total_tests = len(self.results)
        passed_tests = sum(1 for r in self.results if r.passed)
        failed_tests = total_tests - passed_tests
        accuracy_rate = (passed_tests / total_tests) * 100 if total_tests > 0 else 0
        avg_execution_time = sum(r.execution_time for r in self.results) / total_tests if total_tests > 0 else 0

        return TestSummary(
            total_tests=total_tests,
            passed_tests=passed_tests,
            failed_tests=failed_tests,
            accuracy_rate=accuracy_rate,
            avg_execution_time=avg_execution_time,
            test_results=self.results
        )

    def save_results(self, filepath: str):
        """Save test results to JSON file"""
        summary = self._generate_summary()

        # Convert to serializable format
        data = {
            'summary': asdict(summary),
            'results': [asdict(result) for result in self.results],
            'timestamp': time.time(),
            'activity_detection_available': ACTIVITY_DETECTION_AVAILABLE
        }

        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2, default=str)

        print(f"📁 Test results saved to: {filepath}")

def main():
    """Run validation tests"""
    print("🔍 Activity Detection System Validation")
    print("=" * 50)

    validator = ActivityDetectionValidator()
    summary = validator.run_all_tests()

    # Print summary
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    print(f"Total Tests: {summary.total_tests}")
    print(f"Passed: {summary.passed_tests} ✅")
    print(f"Failed: {summary.failed_tests} ❌")
    print(f"Accuracy Rate: {summary.accuracy_rate:.1f}%")
    print(f"Average Execution Time: {summary.avg_execution_time:.3f}s")

    # Save results
    results_file = "/tmp/activity_detection_test_results.json"
    validator.save_results(results_file)

    # Return appropriate exit code
    return 0 if summary.failed_tests == 0 else 1

if __name__ == "__main__":
    exit(main())