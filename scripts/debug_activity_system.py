#!/usr/bin/env python3
"""
Quick Debug Script for Activity-Aware Privacy System
For manual testing and troubleshooting
"""

import sys
import os
import time
import json
from typing import Dict, Any

# Add scripts directory to path
sys.path.append('/workspace/scripts')

def test_imports():
    """Test component imports"""
    print("🔍 Testing component imports...")

    try:
        from privacy_state_manager import PrivacyStateManager, PrivacyState
        print("✅ PrivacyStateManager imported successfully")
    except ImportError as e:
        print(f"❌ PrivacyStateManager import failed: {e}")
        return False

    try:
        from activity_detector import ActivityDetector, ActivityType, PolicyAction
        print("✅ ActivityDetector imported successfully")
    except ImportError as e:
        print(f"❌ ActivityDetector import failed: {e}")
        return False

    try:
        from process_monitor import ContainerProcessMonitor, ProcessInfo
        print("✅ ProcessMonitor imported successfully")
    except ImportError as e:
        print(f"❌ ProcessMonitor import failed: {e}")
        return False

    return True

def test_privacy_manager():
    """Test privacy state manager"""
    print("\n🛡️  Testing Privacy State Manager...")

    try:
        from privacy_state_manager import PrivacyStateManager

        manager = PrivacyStateManager()
        print("✅ PrivacyStateManager initialized")

        # Get status
        status = manager.get_status()
        print(f"   Current state: {status.get('state', 'unknown')}")
        print(f"   ComfyUI ready: {status.get('comfyui_ready', 'unknown')}")
        print(f"   Monitoring only: {status.get('monitoring_only', 'unknown')}")

        # Check activity integration
        if 'activities' in status:
            activities = status['activities']
            print(f"   Activity detection: {'✅' if activities.get('detection_available') else '❌'}")
            print(f"   Active activities: {activities.get('active_count', 0)}")
            print(f"   Health score: {activities.get('health_score', 'N/A')}")
        else:
            print("   No activity status (legacy mode)")

        return True

    except Exception as e:
        print(f"❌ Privacy manager test failed: {e}")
        return False

def test_activity_detector():
    """Test activity detection"""
    print("\n🎯 Testing Activity Detection...")

    try:
        from activity_detector import ActivityDetector, ActivityType
        from process_monitor import ProcessInfo

        detector = ActivityDetector()
        print("✅ ActivityDetector initialized")

        # Test with mock pip install process
        mock_process = ProcessInfo(
            pid=12345,
            ppid=1,
            command="pip",
            cmdline=["pip", "install", "torch"],
            cwd="/workspace/ComfyUI",
            start_time=time.time(),
            uid=1000,
            gid=1000
        )

        activity = detector.detect_activity(mock_process)
        if activity:
            print(f"   Detected activity: {activity.activity_type.value}")
            print(f"   Confidence: {activity.confidence:.3f}")
            print(f"   Policy action: {activity.policy_action.value}")
            print(f"   Allowed domains: {', '.join(activity.allowed_domains[:3])}...")
        else:
            print("   No activity detected")

        # Test policy thresholds
        print("\n   Policy threshold tests:")
        from activity_detector import ConfidenceThresholds
        test_confidences = [0.95, 0.75, 0.55, 0.25, 0.05]
        for conf in test_confidences:
            policy = ConfidenceThresholds.get_policy_action(conf)
            print(f"     Confidence {conf:.2f} -> {policy.value}")

        return True

    except Exception as e:
        print(f"❌ Activity detector test failed: {e}")
        return False

def test_process_monitor():
    """Test process monitoring"""
    print("\n📊 Testing Process Monitor...")

    try:
        from process_monitor import ContainerProcessMonitor

        monitor = ContainerProcessMonitor()
        print("✅ ProcessMonitor initialized")

        # Get current processes
        processes_dict = monitor._scan_processes()
        processes = list(processes_dict.values())
        print(f"   Found {len(processes)} active processes")

        # Show interesting processes
        interesting = [p for p in processes if p.command in ['python', 'python3', 'pip', 'git']]
        if interesting:
            print("   Interesting processes:")
            for proc in interesting[:5]:  # Show first 5
                print(f"     PID {proc.pid}: {proc.command} - {' '.join(proc.cmdline[:3])}...")

        return True

    except Exception as e:
        print(f"❌ Process monitor test failed: {e}")
        return False

def test_activity_policies():
    """Test activity policies configuration"""
    print("\n📋 Testing Activity Policies...")

    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        policies_file = os.path.join(script_dir, 'activity_policies.json')

        with open(policies_file, 'r') as f:
            policies = json.load(f)

        print("✅ Activity policies loaded successfully")

        # Check structure
        required_sections = ['activity_patterns', 'confidence_thresholds', 'policy_actions']
        for section in required_sections:
            if section in policies:
                print(f"   ✅ {section} section present")
            else:
                print(f"   ❌ {section} section missing")

        # Show activity patterns
        if 'activity_patterns' in policies:
            patterns = policies['activity_patterns']
            print(f"   Activity patterns: {len(patterns)}")
            for pattern_name in list(patterns.keys())[:5]:  # Show first 5
                pattern = patterns[pattern_name]
                print(f"     {pattern_name}: confidence {pattern.get('base_confidence', 'N/A')}")

        return True

    except Exception as e:
        print(f"❌ Activity policies test failed: {e}")
        return False

def test_integration():
    """Test full system integration"""
    print("\n🔗 Testing System Integration...")

    try:
        from privacy_state_manager import PrivacyStateManager

        manager = PrivacyStateManager()

        # Test state update
        print("   Testing state update...")
        initial_status = manager.get_status()
        manager.update_state()
        updated_status = manager.get_status()

        print(f"   State transition: {initial_status['state']} -> {updated_status['state']}")

        # Test activity integration if available
        if 'activities' in updated_status and updated_status['activities'].get('detection_available'):
            activities = updated_status['activities']
            print(f"   Activity system active: {activities['active_count']} activities")

            # Show active activities
            for i, activity in enumerate(activities.get('active_activities', [])[:3]):
                print(f"     Activity {i+1}: {activity['activity_type']} (confidence: {activity['confidence']:.2f})")
        else:
            print("   Activity system not active (fallback mode)")

        return True

    except Exception as e:
        print(f"❌ Integration test failed: {e}")
        return False

def main():
    """Run all debug tests"""
    print("🛠️  Activity-Aware Privacy System Debug Tool")
    print("=" * 50)

    tests = [
        ("Component Imports", test_imports),
        ("Privacy Manager", test_privacy_manager),
        ("Activity Detector", test_activity_detector),
        ("Process Monitor", test_process_monitor),
        ("Activity Policies", test_activity_policies),
        ("System Integration", test_integration),
    ]

    results = {}

    for test_name, test_func in tests:
        try:
            results[test_name] = test_func()
        except Exception as e:
            print(f"❌ {test_name} test crashed: {e}")
            results[test_name] = False

    # Summary
    print("\n" + "=" * 50)
    print("📊 DEBUG TEST SUMMARY")
    print("=" * 50)

    passed = sum(1 for result in results.values() if result)
    total = len(results)

    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} {test_name}")

    print(f"\nOverall: {passed}/{total} tests passed")

    if passed == total:
        print("🎉 All debug tests passed! System looks healthy.")
    elif passed >= total - 1:
        print("⚠️  Minor issues detected. System should mostly work.")
    else:
        print("❌ Multiple failures. System may have significant issues.")

    return 0 if passed == total else 1

if __name__ == "__main__":
    exit(main())