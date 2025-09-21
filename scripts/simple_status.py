#!/usr/bin/env python3
import sys
sys.path.append('/workspace/scripts')
from privacy_state_manager import PrivacyStateManager
m = PrivacyStateManager()
status = m.get_status()
print(f"State: {status.get('state')}")
print(f"Activities: {status.get('activities', {}).get('active_count', 0)}")
print(f"Health: {status.get('activities', {}).get('health_score', 'N/A')}")