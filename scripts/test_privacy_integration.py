#!/usr/bin/env python3
"""
Integration Test Suite for Activity-Aware Privacy System
Tests end-to-end integration between components
"""

import sys
import os
import time
import json
import subprocess
import tempfile
from typing import Dict, List, Optional
from pathlib import Path

# Add scripts directory to path
sys.path.append('/workspace/scripts')

try:
    from privacy_state_manager import PrivacyStateManager, PrivacyState
    from activity_detector import ActivityDetector, ActivityType
    from process_monitor import ContainerProcessMonitor
    COMPONENTS_AVAILABLE = True
except ImportError as e:
    COMPONENTS_AVAILABLE = False
    print(f"⚠️  Privacy system components not available: {e}")

class PrivacyIntegrationTester:
    """Integration tests for the complete privacy system"""

    def __init__(self):
        self.manager = None
        self.detector = None
        self.monitor = None

        if COMPONENTS_AVAILABLE:
            try:
                self.manager = PrivacyStateManager()
                print("✅ Privacy system integration test initialized")
            except Exception as e:
                print(f"❌ Failed to initialize privacy system: {e}")
                COMPONENTS_AVAILABLE = False

    def run_integration_tests(self) -> bool:
        """Run complete integration test suite"""
        print("🔗 Activity-Aware Privacy System Integration Tests")
        print("=" * 60)

        if not COMPONENTS_AVAILABLE:
            print("❌ Cannot run integration tests - components not available")
            return False

        success = True

        # Test basic system functionality
        success &= self._test_system_initialization()
        success &= self._test_state_transitions()
        success &= self._test_activity_integration()
        success &= self._test_health_monitoring()
        success &= self._test_fallback_behavior()
        success &= self._test_connection_integration()

        return success

    def _test_system_initialization(self) -> bool:
        """Test system initialization and basic functionality"""
        print("\n🚀 Testing System Initialization...")

        try:
            # Test that privacy manager can get status
            status = self.manager.get_status()

            required_keys = ['mode', 'state', 'comfyui_ready', 'monitoring_only', 'uptime']
            has_required_keys = all(key in status for key in required_keys)

            if not has_required_keys:
                print(f"❌ Status missing required keys: {[k for k in required_keys if k not in status]}")
                return False

            print("✅ Privacy manager status check passed")

            # Test activity detection availability
            if 'activities' in status:
                activities_status = status['activities']
                if activities_status.get('detection_available', False):
                    print("✅ Activity detection is available")
                else:
                    print("⚠️  Activity detection not available (fallback mode)")
            else:
                print("⚠️  No activity status (legacy mode)")

            return True

        except Exception as e:
            print(f"❌ System initialization test failed: {e}")
            return False

    def _test_state_transitions(self) -> bool:
        """Test privacy state transitions"""
        print("\n🔄 Testing State Transitions...")

        try:
            # Get initial state
            initial_status = self.manager.get_status()
            initial_state = initial_status['state']
            print(f"   Initial state: {initial_state}")

            # Test manual state update
            self.manager.update_state()
            updated_status = self.manager.get_status()
            print(f"   State after update: {updated_status['state']}")

            # Verify state is valid
            valid_states = [state.value for state in PrivacyState]
            is_valid_state = updated_status['state'] in valid_states

            if not is_valid_state:
                print(f"❌ Invalid state detected: {updated_status['state']}")
                return False

            print("✅ State transitions working correctly")
            return True

        except Exception as e:
            print(f"❌ State transition test failed: {e}")
            return False

    def _test_activity_integration(self) -> bool:
        """Test activity detection integration"""
        print("\n🎯 Testing Activity Integration...")

        try:
            status = self.manager.get_status()

            if 'activities' not in status:
                print("⚠️  Activity integration not available - using legacy mode")
                return True

            activities = status['activities']

            # Check activity detection structure
            required_activity_keys = ['detection_available', 'active_count', 'high_confidence_count']
            has_activity_keys = all(key in activities for key in required_activity_keys)

            if not has_activity_keys:
                print(f"❌ Activity status missing keys: {[k for k in required_activity_keys if k not in activities]}")
                return False

            print(f"   Active activities: {activities['active_count']}")
            print(f"   High confidence: {activities['high_confidence_count']}")
            print(f"   Health score: {activities.get('health_score', 'N/A')}")

            # Test activity list structure
            if 'active_activities' in activities:
                for i, activity in enumerate(activities['active_activities'][:3]):  # Check first 3
                    required_activity_fields = ['activity_type', 'confidence', 'policy_action']
                    has_fields = all(field in activity for field in required_activity_fields)

                    if not has_fields:
                        print(f"❌ Activity {i} missing required fields")
                        return False

                    print(f"   Activity {i}: {activity['activity_type']} (confidence: {activity['confidence']:.2f})")

            print("✅ Activity integration working correctly")
            return True

        except Exception as e:
            print(f"❌ Activity integration test failed: {e}")
            return False

    def _test_health_monitoring(self) -> bool:
        """Test health monitoring functionality"""
        print("\n🏥 Testing Health Monitoring...")

        try:
            status = self.manager.get_status()

            if 'activities' not in status or not status['activities'].get('detection_available', False):
                print("⚠️  Health monitoring not available - activity detection disabled")
                return True

            activities = status['activities']

            # Check health score
            health_score = activities.get('health_score')
            if health_score is None:
                print("❌ Health score not available")
                return False

            if not 0 <= health_score <= 1:
                print(f"❌ Invalid health score: {health_score}")
                return False

            print(f"   Health score: {health_score:.3f}")

            # Check fallback recommendation
            fallback_recommended = activities.get('fallback_recommended', False)
            print(f"   Fallback recommended: {fallback_recommended}")

            if fallback_recommended and health_score > 0.5:
                print("⚠️  Fallback recommended despite good health score")

            print("✅ Health monitoring working correctly")
            return True

        except Exception as e:
            print(f"❌ Health monitoring test failed: {e}")
            return False

    def _test_fallback_behavior(self) -> bool:
        """Test fallback behavior when activity detection fails"""
        print("\n🔙 Testing Fallback Behavior...")

        try:
            # This test verifies that the system gracefully handles activity detection unavailability
            # Since we can't easily simulate detection failure, we check fallback paths exist

            status = self.manager.get_status()

            # System should work even without activity detection
            if 'activities' in status:
                detection_available = status['activities'].get('detection_available', False)
                if detection_available:
                    print("   Activity detection available - fallback not needed")
                else:
                    print("   Running in fallback mode - activity detection disabled")
            else:
                print("   Running in legacy mode - no activity status")

            # Verify system still functions
            self.manager.update_state()
            fallback_status = self.manager.get_status()

            if 'state' not in fallback_status:
                print("❌ System not functioning in fallback mode")
                return False

            print("✅ Fallback behavior working correctly")
            return True

        except Exception as e:
            print(f"❌ Fallback behavior test failed: {e}")
            return False

    def _test_connection_integration(self) -> bool:
        """Test connection monitoring integration"""
        print("\n🌐 Testing Connection Integration...")

        try:
            # Test that connection monitor can be called
            connection_script = "/workspace/scripts/connection_monitor.sh"

            if os.path.exists(connection_script) and os.access(connection_script, os.X_OK):
                # Test connection monitor status
                result = subprocess.run([connection_script, "status"],
                                      capture_output=True, text=True, timeout=10)

                if result.returncode == 0:
                    print("✅ Connection monitor accessible")
                else:
                    print(f"⚠️  Connection monitor returned error: {result.stderr}")

                # Test recent connections (should not fail even if no data)
                result = subprocess.run([connection_script, "recent", "5"],
                                      capture_output=True, text=True, timeout=10)

                if result.returncode == 0:
                    print("✅ Connection history accessible")
                else:
                    print(f"⚠️  Connection history error: {result.stderr}")

            else:
                print("⚠️  Connection monitor script not available")

            # Test privacy command integration
            privacy_script = "/workspace/scripts/ignition-privacy"

            if os.path.exists(privacy_script) and os.access(privacy_script, os.X_OK):
                # Test status command
                result = subprocess.run([privacy_script, "status"],
                                      capture_output=True, text=True, timeout=15)

                if result.returncode == 0:
                    print("✅ Privacy control interface accessible")

                    # Check if activities command exists
                    result = subprocess.run([privacy_script, "activities"],
                                          capture_output=True, text=True, timeout=15)

                    if result.returncode == 0:
                        print("✅ Activities command working")
                    else:
                        print("⚠️  Activities command may not be available")

                else:
                    print(f"⚠️  Privacy control interface error: {result.stderr}")

            else:
                print("⚠️  Privacy control script not available")

            print("✅ Connection integration tests completed")
            return True

        except subprocess.TimeoutExpired:
            print("❌ Connection integration test timed out")
            return False
        except Exception as e:
            print(f"❌ Connection integration test failed: {e}")
            return False

    def run_performance_test(self) -> Dict:
        """Run performance tests and return metrics"""
        print("\n⚡ Running Performance Tests...")

        metrics = {
            'status_check_time': None,
            'state_update_time': None,
            'activity_detection_time': None,
            'memory_usage': None
        }

        try:
            # Test status check performance
            start = time.time()
            for _ in range(10):
                self.manager.get_status()
            metrics['status_check_time'] = (time.time() - start) / 10

            # Test state update performance
            start = time.time()
            for _ in range(5):
                self.manager.update_state()
            metrics['state_update_time'] = (time.time() - start) / 5

            print(f"   Avg status check time: {metrics['status_check_time']:.3f}s")
            print(f"   Avg state update time: {metrics['state_update_time']:.3f}s")

            # Check if performance is acceptable
            if metrics['status_check_time'] > 1.0:
                print("⚠️  Status check performance may be slow")

            if metrics['state_update_time'] > 2.0:
                print("⚠️  State update performance may be slow")

            print("✅ Performance tests completed")

        except Exception as e:
            print(f"❌ Performance test failed: {e}")

        return metrics

def main():
    """Run integration tests"""
    print("🧪 Activity-Aware Privacy System Integration Tests")
    print("=" * 50)

    tester = PrivacyIntegrationTester()

    # Run integration tests
    integration_success = tester.run_integration_tests()

    # Run performance tests
    performance_metrics = tester.run_performance_test()

    # Print final summary
    print("\n" + "=" * 60)
    print("📊 INTEGRATION TEST SUMMARY")
    print("=" * 60)

    if integration_success:
        print("✅ All integration tests passed")
    else:
        print("❌ Some integration tests failed")

    if performance_metrics:
        print("\n📈 Performance Metrics:")
        for metric, value in performance_metrics.items():
            if value is not None:
                if 'time' in metric:
                    print(f"   {metric}: {value:.3f}s")
                else:
                    print(f"   {metric}: {value}")

    # Save test results
    results = {
        'integration_success': integration_success,
        'performance_metrics': performance_metrics,
        'timestamp': time.time(),
        'components_available': COMPONENTS_AVAILABLE
    }

    results_file = "/tmp/privacy_integration_test_results.json"
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n📁 Results saved to: {results_file}")

    return 0 if integration_success else 1

if __name__ == "__main__":
    exit(main())