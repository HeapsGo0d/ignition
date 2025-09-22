#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from process_monitor import ProcessInfo
from activity_detector import ActivityDetector

print("🔍 Deep Debug Activity Detection")
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

print("Process info:")
print(f"  Command: {real_pip_process.command}")
print(f"  Cmdline: {real_pip_process.cmdline}")
print(f"  Full cmdline: {getattr(real_pip_process, 'full_cmdline', 'N/A')}")

# Check if process has full_cmdline attribute
if not hasattr(real_pip_process, 'full_cmdline'):
    print("❌ ProcessInfo missing full_cmdline attribute!")
    # Add it manually
    real_pip_process.full_cmdline = ' '.join(real_pip_process.cmdline)
    print(f"  Added full_cmdline: {real_pip_process.full_cmdline}")

print("\n🔍 Testing each pattern individually:")

for i, pattern in enumerate(detector.patterns):
    print(f"\nPattern {i+1}:")
    print(f"  Activity type: {pattern.activity_type}")
    print(f"  Command patterns: {pattern.command_patterns}")
    print(f"  Arg patterns: {pattern.arg_patterns}")

    # Test the pattern match
    result = pattern.match(real_pip_process, [])
    print(f"  Match result: {result}")

    if result is not None and result > 0:
        print(f"  ✅ This pattern matches with confidence {result:.3f}")
    else:
        print(f"  ❌ This pattern doesn't match")

print(f"\n🎯 Main detect_activity result:")
activity = detector.detect_activity(real_pip_process)
if activity:
    print(f"✅ Activity: {activity.activity_type.value} (confidence: {activity.confidence:.3f})")
else:
    print("❌ No activity detected by main function")