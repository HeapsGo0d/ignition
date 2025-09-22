#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from process_monitor import ProcessInfo
from activity_detector import ActivityDetector

print("🧪 Testing Real Pip Process Detection")
print("=" * 40)

detector = ActivityDetector()

# Create a ProcessInfo that matches exactly what we saw
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
activity = detector.detect_activity(real_pip_process)

if activity:
    print("✅ Activity detected!")
    print(f"  Type: {activity.activity_type.value}")
    print(f"  Confidence: {activity.confidence:.3f}")
    print(f"  Policy: {activity.policy_action.value}")
    print(f"  Domains: {', '.join(activity.allowed_domains[:5])}...")
else:
    print("❌ No activity detected")
    print()
    print("🔍 Let's debug why...")

    # Check if any patterns match
    print("Checking pattern matching...")

    # Test if cmdline contains 'pip'
    has_pip_in_cmdline = any('pip' in arg for arg in real_pip_process.cmdline)
    print(f"  Has 'pip' in cmdline: {has_pip_in_cmdline}")

    # Test if command contains 'pip'
    has_pip_in_command = 'pip' in real_pip_process.command
    print(f"  Has 'pip' in command: {has_pip_in_command}")

    # Test specific pip pattern
    pip_install_pattern = any(arg == 'install' for arg in real_pip_process.cmdline)
    print(f"  Has 'install' in cmdline: {pip_install_pattern}")

print("\n🎯 This tells us if the activity detector patterns are working!")