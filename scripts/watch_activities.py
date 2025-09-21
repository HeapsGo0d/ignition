#!/usr/bin/env python3
import sys
import time
sys.path.append('/workspace/scripts')
from privacy_state_manager import PrivacyStateManager

print("🔍 Watching for activities...")
manager = PrivacyStateManager()

for i in range(10):
    status = manager.get_status()
    activities = status.get('activities', {})
    count = activities.get('active_count', 0)

    if count > 0:
        print(f"[{time.strftime('%H:%M:%S')}] Found {count} activities!")
        for activity in activities.get('active_activities', []):
            print(f"  - {activity['activity_type']} (confidence: {activity['confidence']:.2f})")
    else:
        print(f"[{time.strftime('%H:%M:%S')}] No activities detected")

    time.sleep(2)

print("Done watching.")