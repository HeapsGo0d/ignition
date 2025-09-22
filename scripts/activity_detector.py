#!/usr/bin/env python3
"""
Activity Detector - Confidence-based activity classification for process monitoring
Part of Ignition Activity-Based Privacy Protection System

Analyzes processes to detect activities like pip installs, git operations, etc.
Uses confidence scoring to make nuanced policy decisions.
"""

import json
import time
import re
from typing import Dict, List, Optional, NamedTuple
from dataclasses import dataclass, asdict
from enum import Enum
from pathlib import Path

from process_monitor import ProcessInfo, ContainerProcessMonitor


class ActivityType(Enum):
    """Types of detected activities"""
    PIP_INSTALL = "pip_install"
    PIP_UPGRADE = "pip_upgrade"
    GIT_CLONE = "git_clone"
    GIT_PULL = "git_pull"
    EXTENSION_UPDATE = "extension_update"
    PACKAGE_INSTALL = "package_install"
    WEB_DOWNLOAD = "web_download"
    UNKNOWN = "unknown"
    SUSPICIOUS = "suspicious"


class PolicyAction(Enum):
    """Policy actions based on confidence"""
    ALLOW_UNRESTRICTED = "allow_unrestricted"
    ALLOW_WITH_MONITORING = "allow_with_monitoring"
    STRICT_ALLOWLIST = "strict_allowlist"
    EMERGENCY_REVIEW = "emergency_review"
    BLOCK_ALL = "block_all"


@dataclass
class DetectedActivity:
    """Container for detected activity information"""
    activity_type: ActivityType
    confidence: float  # 0.0 to 1.0
    policy_action: PolicyAction
    process_info: ProcessInfo
    context: Dict
    timestamp: float
    duration_estimate: int  # seconds
    allowed_domains: List[str]
    risk_factors: List[str]

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization"""
        result = asdict(self)
        result['activity_type'] = self.activity_type.value
        result['policy_action'] = self.policy_action.value
        # Convert ProcessInfo to dict manually since it's a dataclass
        result['process_info'] = asdict(self.process_info)
        return result


class ConfidenceThresholds:
    """Confidence thresholds for policy decisions"""
    HIGH_CONFIDENCE = 0.9      # Allow unrestricted
    MEDIUM_CONFIDENCE = 0.7    # Allow with monitoring
    LOW_CONFIDENCE = 0.5       # Strict allowlist
    SUSPICIOUS_THRESHOLD = 0.3 # Emergency review

    @classmethod
    def get_policy_action(cls, confidence: float) -> PolicyAction:
        """Get policy action based on confidence score"""
        if confidence >= cls.HIGH_CONFIDENCE:
            return PolicyAction.ALLOW_UNRESTRICTED
        elif confidence >= cls.MEDIUM_CONFIDENCE:
            return PolicyAction.ALLOW_WITH_MONITORING
        elif confidence >= cls.LOW_CONFIDENCE:
            return PolicyAction.STRICT_ALLOWLIST
        elif confidence >= cls.SUSPICIOUS_THRESHOLD:
            return PolicyAction.EMERGENCY_REVIEW
        else:
            return PolicyAction.BLOCK_ALL


class ActivityPattern:
    """Pattern for detecting specific activities"""

    def __init__(self, activity_type: ActivityType, patterns: Dict):
        self.activity_type = activity_type
        self.command_patterns = patterns.get('commands', [])
        self.arg_patterns = patterns.get('args', [])
        self.cwd_patterns = patterns.get('cwd', [])
        self.parent_patterns = patterns.get('parents', [])
        self.allowed_domains = patterns.get('allowed_domains', [])
        self.base_confidence = patterns.get('base_confidence', 0.5)
        self.confidence_modifiers = patterns.get('confidence_modifiers', {})
        self.duration_estimate = patterns.get('duration_estimate', 300)
        self.risk_factors = patterns.get('risk_factors', [])

    def match(self, proc_info: ProcessInfo, lineage: List[ProcessInfo]) -> Optional[float]:
        """
        Check if process matches this pattern and return confidence score.
        Returns None if no match, float 0.0-1.0 if match.
        """
        confidence = 0.0
        match_factors = []

        # Check command patterns
        command_match = False
        for pattern in self.command_patterns:
            if self._matches_pattern(pattern, proc_info.command):
                command_match = True
                confidence += 0.3
                match_factors.append(f"command:{pattern}")
                break

        # Special case for pip: if command is python but cmdline contains pip, allow it
        if not command_match and any('python' in cmd for cmd in self.command_patterns):
            if self._matches_pattern('python', proc_info.command) and any('pip' in arg for arg in proc_info.cmdline):
                command_match = True
                confidence += 0.3
                match_factors.append("command:python-pip")

        if not command_match:
            return None  # Must match at least one command pattern

        # Check argument patterns
        cmdline_str = proc_info.full_cmdline
        for pattern in self.arg_patterns:
            if self._matches_pattern(pattern, cmdline_str):
                confidence += 0.3
                match_factors.append(f"args:{pattern}")

        # Check working directory patterns
        for pattern in self.cwd_patterns:
            if self._matches_pattern(pattern, proc_info.cwd):
                confidence += 0.2
                match_factors.append(f"cwd:{pattern}")

        # Check parent process patterns
        for ancestor in lineage:
            for pattern in self.parent_patterns:
                if self._matches_pattern(pattern, ancestor.command):
                    confidence += 0.2
                    match_factors.append(f"parent:{pattern}")
                    break

        # Apply confidence modifiers
        for modifier_key, modifier_value in self.confidence_modifiers.items():
            if self._check_modifier(modifier_key, proc_info, cmdline_str):
                confidence += modifier_value
                match_factors.append(f"modifier:{modifier_key}")

        # Normalize confidence and apply base confidence
        confidence = min(1.0, max(0.0, confidence * self.base_confidence))

        return confidence

    def _matches_pattern(self, pattern: str, text: str) -> bool:
        """Check if pattern matches text (supports regex and command names)"""
        if pattern.startswith('regex:'):
            try:
                return bool(re.search(pattern[6:], text, re.IGNORECASE))
            except re.error:
                return False
        else:
            # Handle command name matching for full paths
            # e.g., "python3" should match "/opt/conda/bin/python3.11"
            pattern_lower = pattern.lower()
            text_lower = text.lower()

            # Direct substring match
            if pattern_lower in text_lower:
                return True

            # For command patterns, also check if the command basename matches
            # e.g., "python3" matches "/opt/conda/bin/python3.11"
            if '/' in text_lower:
                basename = text_lower.split('/')[-1]
                # Check if pattern matches the basename or basename starts with pattern
                if pattern_lower == basename or basename.startswith(pattern_lower):
                    return True

            return False

    def _check_modifier(self, modifier: str, proc_info: ProcessInfo, cmdline: str) -> bool:
        """Check confidence modifier conditions"""
        if modifier == "has_version_flag":
            return any(flag in cmdline for flag in ['--version', '-V', 'version'])
        elif modifier == "has_help_flag":
            return any(flag in cmdline for flag in ['--help', '-h', 'help'])
        elif modifier == "from_comfyui_directory":
            return '/ComfyUI' in proc_info.cwd
        elif modifier == "install_specific_package":
            # Higher confidence for installing specific packages vs generic commands
            return bool(re.search(r'install\s+[a-zA-Z0-9_-]+', cmdline))
        elif modifier == "suspicious_url":
            # Lower confidence if URLs look suspicious
            suspicious_tlds = ['.tk', '.ml', '.ga', '.cf']
            return any(tld in cmdline for tld in suspicious_tlds)
        elif modifier == "uses_sudo":
            return 'sudo' in cmdline
        return False


class SmartHealthCheck:
    """Time-window based health monitoring for activity detection"""

    def __init__(self, short_window: int = 300, medium_window: int = 900, long_window: int = 3600):
        self.short_window = short_window    # 5 minutes
        self.medium_window = medium_window  # 15 minutes
        self.long_window = long_window      # 1 hour

        self.detection_history = []  # List of (timestamp, success, confidence)
        self.error_history = []      # List of (timestamp, error_type)

    def record_detection(self, success: bool, confidence: float = 0.0, error_type: str = None):
        """Record a detection attempt"""
        timestamp = time.time()

        if success:
            self.detection_history.append((timestamp, True, confidence))
        else:
            self.detection_history.append((timestamp, False, 0.0))
            if error_type:
                self.error_history.append((timestamp, error_type))

        # Clean old entries
        self._cleanup_old_entries()

    def _cleanup_old_entries(self):
        """Remove entries older than long window"""
        cutoff = time.time() - self.long_window
        self.detection_history = [
            entry for entry in self.detection_history if entry[0] > cutoff
        ]
        self.error_history = [
            entry for entry in self.error_history if entry[0] > cutoff
        ]

    def get_health_score(self) -> float:
        """Get overall health score (0.0-1.0)"""
        now = time.time()

        # Analyze different time windows
        short_score = self._analyze_window(now - self.short_window)
        medium_score = self._analyze_window(now - self.medium_window)
        long_score = self._analyze_window(now - self.long_window)

        # Weight recent performance more heavily
        weighted_score = (short_score * 0.5 + medium_score * 0.3 + long_score * 0.2)

        return weighted_score

    def _analyze_window(self, since_timestamp: float) -> float:
        """Analyze detection performance in a time window"""
        recent_detections = [
            entry for entry in self.detection_history if entry[0] >= since_timestamp
        ]

        if not recent_detections:
            return 1.0  # No data = assume healthy

        total_detections = len(recent_detections)
        successful_detections = sum(1 for _, success, _ in recent_detections if success)
        avg_confidence = sum(conf for _, success, conf in recent_detections if success) / max(1, successful_detections)

        # Calculate success rate
        success_rate = successful_detections / total_detections

        # Factor in confidence levels
        confidence_factor = avg_confidence if successful_detections > 0 else 0.0

        return (success_rate * 0.7 + confidence_factor * 0.3)

    def should_fallback(self) -> bool:
        """Determine if system should fallback to stricter mode"""
        health_score = self.get_health_score()

        # Fallback if health score is poor
        if health_score < 0.3:
            return True

        # Check for error patterns
        recent_errors = [
            entry for entry in self.error_history
            if entry[0] > time.time() - self.short_window
        ]

        # Too many recent errors
        if len(recent_errors) > 5:
            return True

        return False

    def get_adaptive_threshold(self) -> float:
        """Get adaptive confidence threshold based on health"""
        health_score = self.get_health_score()

        # Lower thresholds when system is unhealthy
        if health_score < 0.5:
            return ConfidenceThresholds.HIGH_CONFIDENCE  # Require higher confidence
        elif health_score < 0.7:
            return ConfidenceThresholds.MEDIUM_CONFIDENCE
        else:
            return ConfidenceThresholds.LOW_CONFIDENCE


class ActivityDetector:
    """
    Main activity detection engine with confidence-based policy decisions.
    Analyzes processes to detect activities and make blocking decisions.
    """

    def __init__(self, config_path: Optional[str] = None):
        self.config_path = config_path or "/workspace/scripts/activity_policies.json"
        self.patterns: List[ActivityPattern] = []
        self.health_check = SmartHealthCheck()
        self.active_activities: Dict[int, DetectedActivity] = {}  # pid -> activity
        self.process_monitor: Optional[ContainerProcessMonitor] = None

        # Load activity patterns
        self._load_patterns()

    def _load_patterns(self):
        """Load activity patterns from configuration file"""
        try:
            with open(self.config_path, 'r') as f:
                config = json.load(f)

            for activity_name, pattern_config in config.get('activity_patterns', {}).items():
                try:
                    activity_type = ActivityType(activity_name)
                    pattern = ActivityPattern(activity_type, pattern_config)
                    self.patterns.append(pattern)
                except ValueError:
                    print(f"Unknown activity type: {activity_name}")

        except FileNotFoundError:
            print(f"Config file not found: {self.config_path}, using defaults")
            self._create_default_patterns()
        except json.JSONDecodeError as e:
            print(f"Error parsing config file: {e}, using defaults")
            self._create_default_patterns()

    def _create_default_patterns(self):
        """Create default activity patterns if no config file"""
        default_patterns = {
            ActivityType.PIP_INSTALL: {
                'commands': ['pip', 'pip3', 'python -m pip'],
                'args': ['install'],
                'allowed_domains': ['pypi.org', 'pypi.python.org', 'files.pythonhosted.org'],
                'base_confidence': 0.9,
                'duration_estimate': 180,
                'confidence_modifiers': {
                    'install_specific_package': 0.1,
                    'from_comfyui_directory': 0.05
                }
            },
            ActivityType.GIT_CLONE: {
                'commands': ['git'],
                'args': ['clone'],
                'allowed_domains': ['github.com', 'gitlab.com', 'bitbucket.org'],
                'base_confidence': 0.8,
                'duration_estimate': 120,
                'confidence_modifiers': {
                    'from_comfyui_directory': 0.1
                }
            },
            ActivityType.EXTENSION_UPDATE: {
                'commands': ['python', 'python3'],
                'cwd': ['/ComfyUI/custom_nodes'],
                'allowed_domains': ['github.com', 'pypi.org'],
                'base_confidence': 0.85,
                'duration_estimate': 240
            }
        }

        for activity_type, config in default_patterns.items():
            pattern = ActivityPattern(activity_type, config)
            self.patterns.append(pattern)

    def start_monitoring(self, poll_interval: float = 1.0):
        """Start process monitoring and activity detection"""
        if self.process_monitor:
            return

        self.process_monitor = ContainerProcessMonitor(poll_interval)
        self.process_monitor.register_callback('command_detected', self._on_process_detected)
        self.process_monitor.register_callback('process_ended', self._on_process_ended)
        self.process_monitor.start_monitoring()

    def stop_monitoring(self):
        """Stop process monitoring"""
        if self.process_monitor:
            self.process_monitor.stop_monitoring()
            self.process_monitor = None

    def _on_process_detected(self, proc_info: ProcessInfo):
        """Handle new interesting process detection"""
        try:
            activity = self.detect_activity(proc_info)
            if activity:
                self.active_activities[proc_info.pid] = activity
                print(f"🔍 Activity detected: {activity.activity_type.value} "
                      f"(confidence: {activity.confidence:.2f}, "
                      f"policy: {activity.policy_action.value})")

            self.health_check.record_detection(True, activity.confidence if activity else 0.0)

        except Exception as e:
            print(f"Error detecting activity: {e}")
            self.health_check.record_detection(False, error_type=str(type(e).__name__))

    def _on_process_ended(self, proc_info: ProcessInfo):
        """Handle process termination"""
        if proc_info.pid in self.active_activities:
            activity = self.active_activities[proc_info.pid]
            print(f"✅ Activity completed: {activity.activity_type.value} (PID: {proc_info.pid})")
            del self.active_activities[proc_info.pid]

    def detect_activity(self, proc_info: ProcessInfo) -> Optional[DetectedActivity]:
        """Detect activity type and confidence for a process"""
        if not self.process_monitor:
            return None

        # Get process lineage for context
        lineage = self.process_monitor.get_process_lineage(proc_info.pid)

        best_match = None
        best_confidence = 0.0
        best_pattern = None

        # Try each pattern
        for pattern in self.patterns:
            confidence = pattern.match(proc_info, lineage)
            if confidence is not None and confidence > best_confidence:
                best_confidence = confidence
                best_pattern = pattern
                best_match = pattern.activity_type

        if not best_match or best_confidence < 0.1:
            return None

        # Apply adaptive thresholds based on system health
        adaptive_threshold = self.health_check.get_adaptive_threshold()
        adjusted_confidence = best_confidence

        if self.health_check.should_fallback():
            # System unhealthy, be more conservative
            adjusted_confidence *= 0.8

        # Get policy action based on confidence
        policy_action = ConfidenceThresholds.get_policy_action(adjusted_confidence)

        # Build context information
        context = {
            'lineage_length': len(lineage),
            'parent_command': lineage[0].command if lineage else None,
            'working_directory': proc_info.cwd,
            'health_score': self.health_check.get_health_score(),
            'adaptive_threshold_used': adaptive_threshold
        }

        # Identify risk factors
        risk_factors = []
        if best_pattern:
            risk_factors.extend(best_pattern.risk_factors)

        if 'sudo' in proc_info.full_cmdline:
            risk_factors.append('elevated_privileges')

        if proc_info.uid == 0:
            risk_factors.append('running_as_root')

        return DetectedActivity(
            activity_type=best_match,
            confidence=adjusted_confidence,
            policy_action=policy_action,
            process_info=proc_info,
            context=context,
            timestamp=time.time(),
            duration_estimate=best_pattern.duration_estimate if best_pattern else 300,
            allowed_domains=best_pattern.allowed_domains if best_pattern else [],
            risk_factors=risk_factors
        )

    def should_allow_connection(self, domain: str, port: int) -> tuple[bool, Optional[str]]:
        """
        Check if a connection should be allowed based on active activities.
        Returns (allow, reason)
        """
        # Check each active activity
        for activity in self.active_activities.values():
            if domain in activity.allowed_domains:
                confidence_desc = f"confidence {activity.confidence:.2f}"
                return True, f"{activity.activity_type.value} ({confidence_desc})"

            # Check policy-based allowances
            if activity.policy_action == PolicyAction.ALLOW_UNRESTRICTED:
                return True, f"{activity.activity_type.value} (unrestricted)"
            elif activity.policy_action == PolicyAction.ALLOW_WITH_MONITORING:
                # Allow but flag for extra monitoring
                return True, f"{activity.activity_type.value} (monitored)"

        return False, "no_active_activity"

    def get_active_activities(self) -> List[DetectedActivity]:
        """Get list of currently active activities"""
        return list(self.active_activities.values())

    def get_health_status(self) -> Dict:
        """Get health monitoring status"""
        return {
            'health_score': self.health_check.get_health_score(),
            'should_fallback': self.health_check.should_fallback(),
            'adaptive_threshold': self.health_check.get_adaptive_threshold(),
            'active_activities_count': len(self.active_activities),
            'detection_history_length': len(self.health_check.detection_history)
        }


def main():
    """Test/demo the activity detector"""
    detector = ActivityDetector()

    print("🚀 Starting activity detector...")
    print("Monitoring for pip, git, and extension activities...")
    print("Press Ctrl+C to stop")

    try:
        detector.start_monitoring(poll_interval=1.0)

        # Keep running and show periodic status
        while True:
            time.sleep(10)

            # Show active activities
            activities = detector.get_active_activities()
            if activities:
                print(f"\n📊 Active activities: {len(activities)}")
                for activity in activities:
                    print(f"  • {activity.activity_type.value} "
                          f"(PID: {activity.process_info.pid}, "
                          f"confidence: {activity.confidence:.2f})")

            # Show health status
            health = detector.get_health_status()
            print(f"🏥 Health score: {health['health_score']:.2f}, "
                  f"fallback: {health['should_fallback']}")

    except KeyboardInterrupt:
        print("\n🛑 Stopping activity detector...")
        detector.stop_monitoring()


if __name__ == "__main__":
    main()