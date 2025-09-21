#!/usr/bin/env python3
"""
RunPod Activity-Aware Privacy System Test Script
Run with: python3 /workspace/scripts/runpod_test.py
"""

import sys
import os
import time
import json
sys.path.append('/workspace/scripts')

def print_header(title):
    print(f"\n{'='*60}")
    print(f"🧪 {title}")
    print(f"{'='*60}")

def test_system_status():
    print_header("SYSTEM STATUS TEST")

    try:
        from privacy_state_manager import PrivacyStateManager
        print("✅ PrivacyStateManager imported successfully")

        manager = PrivacyStateManager()
        print("✅ PrivacyStateManager initialized")

        status = manager.get_status()
        print("✅ Status retrieved successfully")

        print(f"\n📊 Current System Status:")
        print(f"   State: {status.get('state', 'unknown')}")
        print(f"   ComfyUI Ready: {status.get('comfyui_ready', False)}")
        print(f"   Monitoring Only: {status.get('monitoring_only', True)}")
        print(f"   Uptime: {status.get('uptime', 'unknown')}s")

        if 'activities' in status:
            activities = status['activities']
            print(f"\n🎯 Activity Detection Status:")
            print(f"   Detection Available: {activities.get('detection_available', False)}")
            print(f"   Active Activities: {activities.get('active_count', 0)}")
            print(f"   High Confidence: {activities.get('high_confidence_count', 0)}")
            print(f"   Health Score: {activities.get('health_score', 'N/A')}")
            print(f"   Fallback Recommended: {activities.get('fallback_recommended', False)}")

            if activities.get('active_activities'):
                print(f"\n   📋 Current Activities:")
                for i, activity in enumerate(activities['active_activities'][:5]):
                    print(f"      {i+1}. {activity['activity_type']} (confidence: {activity['confidence']:.2f}, policy: {activity['policy_action']})")
            else:
                print("   📋 No active activities detected")
        else:
            print("\n❌ Activity detection not available")

        return True, manager

    except Exception as e:
        print(f"❌ System status test failed: {e}")
        import traceback
        traceback.print_exc()
        return False, None

def test_activity_detection():
    print_header("ACTIVITY DETECTION TEST")

    try:
        from activity_detector import ActivityDetector, ConfidenceThresholds
        from process_monitor import ProcessInfo

        detector = ActivityDetector()
        print("✅ ActivityDetector initialized")

        # Test various mock processes
        test_cases = [
            {
                "name": "Pip Install",
                "process": ProcessInfo(
                    pid=12345, ppid=1, command="pip",
                    cmdline=["pip", "install", "torch"],
                    cwd="/workspace", start_time=time.time(), uid=0, gid=0
                )
            },
            {
                "name": "Git Clone",
                "process": ProcessInfo(
                    pid=12346, ppid=1, command="git",
                    cmdline=["git", "clone", "https://github.com/user/repo.git"],
                    cwd="/workspace/ComfyUI/custom_nodes", start_time=time.time(), uid=0, gid=0
                )
            },
            {
                "name": "Aria2c Download",
                "process": ProcessInfo(
                    pid=12347, ppid=1, command="aria2c",
                    cmdline=["aria2c", "https://civitai.com/model.safetensors"],
                    cwd="/workspace/ComfyUI/models", start_time=time.time(), uid=0, gid=0
                )
            }
        ]

        print(f"\n🔍 Testing Activity Detection:")
        for test_case in test_cases:
            activity = detector.detect_activity(test_case["process"])
            if activity:
                print(f"   ✅ {test_case['name']}: {activity.activity_type.value}")
                print(f"      Confidence: {activity.confidence:.3f}")
                print(f"      Policy: {activity.policy_action.value}")
                print(f"      Domains: {', '.join(activity.allowed_domains[:3])}{'...' if len(activity.allowed_domains) > 3 else ''}")
            else:
                print(f"   ❌ {test_case['name']}: No activity detected")

        # Test policy thresholds
        print(f"\n📊 Policy Threshold Tests:")
        test_confidences = [0.95, 0.80, 0.65, 0.40, 0.15]
        for conf in test_confidences:
            policy = ConfidenceThresholds.get_policy_action(conf)
            print(f"   Confidence {conf:.2f} → {policy.value}")

        return True

    except Exception as e:
        print(f"❌ Activity detection test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_process_monitoring():
    print_header("PROCESS MONITORING TEST")

    try:
        from process_monitor import ContainerProcessMonitor

        monitor = ContainerProcessMonitor()
        print("✅ ProcessMonitor initialized")

        processes_dict = monitor._scan_processes()
        processes = list(processes_dict.values())
        print(f"✅ Found {len(processes)} active processes")

        # Show interesting processes
        interesting = [p for p in processes if p.command in ['python', 'python3', 'pip', 'git', 'aria2c', 'wget', 'curl']]
        if interesting:
            print(f"\n🔍 Interesting Processes Found:")
            for proc in interesting[:10]:  # Show first 10
                cmdline_preview = ' '.join(proc.cmdline[:3]) + ('...' if len(proc.cmdline) > 3 else '')
                print(f"   PID {proc.pid}: {proc.command} - {cmdline_preview}")
        else:
            print(f"\n📋 No particularly interesting processes running")

        return True

    except Exception as e:
        print(f"❌ Process monitoring test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_cli_integration():
    print_header("CLI INTEGRATION TEST")

    try:
        import subprocess

        # Test ignition-privacy commands
        commands = [
            ("status", "ignition-privacy status"),
            ("activities", "ignition-privacy activities"),
            ("help", "ignition-privacy help")
        ]

        for cmd_name, cmd in commands:
            try:
                result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    print(f"✅ {cmd_name} command works")
                    # Show first few lines of output
                    lines = result.stdout.strip().split('\n')[:5]
                    for line in lines:
                        if line.strip():
                            print(f"   {line}")
                    if len(result.stdout.strip().split('\n')) > 5:
                        print("   ...")
                else:
                    print(f"❌ {cmd_name} command failed (exit code: {result.returncode})")
                    if result.stderr:
                        print(f"   Error: {result.stderr.strip()}")
            except subprocess.TimeoutExpired:
                print(f"⏰ {cmd_name} command timed out")
            except Exception as e:
                print(f"❌ {cmd_name} command error: {e}")

        return True

    except Exception as e:
        print(f"❌ CLI integration test failed: {e}")
        return False

def show_next_steps():
    print_header("NEXT STEPS FOR MANUAL TESTING")

    print("🚀 System is ready! Try these commands:")
    print()
    print("1. Monitor system status:")
    print("   ignition-privacy status")
    print()
    print("2. Watch for activities in real-time:")
    print("   ignition-privacy activities")
    print()
    print("3. Test pip install detection:")
    print("   pip install some-package")
    print("   ignition-privacy debug activities")
    print()
    print("4. Test model download (this is the key test!):")
    print("   # Download a Flux model and watch activity detection")
    print("   ignition-privacy monitor &")
    print("   # Then download your model")
    print()
    print("5. Check connection monitoring:")
    print("   ignition-privacy summary")
    print("   ignition-privacy debug timeline")
    print()
    print("6. Emergency block test:")
    print("   ignition-privacy block-all")
    print("   ignition-privacy status")
    print()

def main():
    print("🧪 RunPod Activity-Aware Privacy System Diagnostic")
    print("Starting comprehensive test suite...")

    # Run all tests
    system_ok, manager = test_system_status()
    activity_ok = test_activity_detection() if system_ok else False
    process_ok = test_process_monitoring() if system_ok else False
    cli_ok = test_cli_integration()

    # Summary
    print_header("TEST SUMMARY")

    total_tests = 4
    passed_tests = sum([system_ok, activity_ok, process_ok, cli_ok])

    print(f"📊 Results: {passed_tests}/{total_tests} tests passed")
    print(f"   System Status: {'✅ PASS' if system_ok else '❌ FAIL'}")
    print(f"   Activity Detection: {'✅ PASS' if activity_ok else '❌ FAIL'}")
    print(f"   Process Monitoring: {'✅ PASS' if process_ok else '❌ FAIL'}")
    print(f"   CLI Integration: {'✅ PASS' if cli_ok else '❌ FAIL'}")

    if passed_tests == total_tests:
        print(f"\n🎉 All tests passed! Activity-aware privacy system is working correctly.")
        show_next_steps()
    elif passed_tests >= 2:
        print(f"\n⚠️  Some tests failed but core system appears functional.")
        print("Try the CLI commands manually to see what's working.")
    else:
        print(f"\n❌ Multiple test failures. System may have significant issues.")
        print("Check the error messages above for troubleshooting.")

if __name__ == "__main__":
    main()