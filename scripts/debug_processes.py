#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from process_monitor import ContainerProcessMonitor
from activity_detector import ActivityDetector

print("🔍 Debug Process Monitor and Activity Detection")
print("=" * 50)

# Initialize components
monitor = ContainerProcessMonitor()
detector = ActivityDetector()

print("✅ Components initialized")
print()

# Scan current processes
print("📊 Scanning current processes...")
processes_dict = monitor._scan_processes()
processes = list(processes_dict.values())

print(f"Found {len(processes)} total processes")
print()

# Look for interesting processes
interesting_commands = ['python', 'python3', 'pip', 'pip3', 'git', 'wget', 'curl', 'aria2c']
interesting_processes = [p for p in processes if p.command in interesting_commands]

if interesting_processes:
    print("🎯 Interesting processes found:")
    for proc in interesting_processes:
        print(f"  PID {proc.pid}: {proc.command}")
        print(f"    Command line: {' '.join(proc.cmdline[:5])}{'...' if len(proc.cmdline) > 5 else ''}")
        print(f"    Working dir: {proc.cwd}")

        # Test activity detection on this process
        activity = detector.detect_activity(proc)
        if activity:
            print(f"    ✅ Activity detected: {activity.activity_type.value} (confidence: {activity.confidence:.3f})")
        else:
            print(f"    ❌ No activity detected")
        print()
else:
    print("📋 No interesting processes found")
    print("Showing first 10 processes:")
    for proc in processes[:10]:
        print(f"  PID {proc.pid}: {proc.command} - {' '.join(proc.cmdline[:3])}")

print()
print("💡 Try running this script while pip install is running in another terminal!")
print("   Example: pip install requests &")