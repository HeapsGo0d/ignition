#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from process_monitor import ProcessInfo
from activity_detector import ActivityDetector

print("🧪 Testing Fixed Pip Detection")
print("=" * 40)

detector = ActivityDetector()

# Test the exact process structure we found in RunPod
real_pip_process = ProcessInfo(
    pid=6747,
    ppid=1,
    command="/opt/conda/bin/python3.11",
    cmdline=["/opt/conda/bin/python3.11", "/opt/conda/bin/pip", "install", "--no-cache-dir", "tensorflow"],
    cwd="/workspace",
    start_time=time.time(),
    uid=0,
    gid=0
)

print("Testing process:")
print(f"  Command: {real_pip_process.command}")
print(f"  Cmdline: {real_pip_process.cmdline}")
print(f"  Working dir: {real_pip_process.cwd}")
print()

# Test activity detection
print("🔍 Running activity detection...")
activity = detector.detect_activity(real_pip_process)

if activity:
    print("✅ SUCCESS! Activity detected!")
    print(f"  Type: {activity.activity_type.value}")
    print(f"  Confidence: {activity.confidence:.3f}")
    print(f"  Policy: {activity.policy_action.value}")
    print(f"  Allowed domains: {', '.join(activity.allowed_domains[:5])}...")
    print()
    print("🎉 The activity-aware privacy system can now detect pip installs!")
else:
    print("❌ Still no activity detected")
    print()
    print("🔍 Additional debugging...")

    # Test pattern matching directly
    for pattern in detector.patterns:
        if hasattr(pattern, 'command_patterns') and 'pip' in str(pattern.command_patterns):
            print(f"Testing pattern: {pattern.command_patterns}")
            result = pattern.match(real_pip_process, [])
            print(f"  Result: {result}")

print("\n🎯 This shows if our fixes work for the real conda pip structure!")