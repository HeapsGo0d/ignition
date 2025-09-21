#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from activity_detector import ActivityDetector
from process_monitor import ProcessInfo

detector = ActivityDetector()
mock_pip = ProcessInfo(
    pid=99999, ppid=1, command="pip",
    cmdline=["pip", "install", "torch"],
    cwd="/workspace", start_time=time.time(), uid=0, gid=0
)

activity = detector.detect_activity(mock_pip)
if activity:
    print(f"✅ Detected: {activity.activity_type.value}")
    print(f"Confidence: {activity.confidence:.3f}")
    print(f"Policy: {activity.policy_action.value}")
else:
    print("❌ No activity detected")