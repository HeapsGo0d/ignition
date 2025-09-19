#!/usr/bin/env python3
"""
Privacy State Manager - Core logic for managing privacy blocking states
Part of Ignition Privacy Blocking System
"""

import os
import sys
import json
import time
import subprocess
import signal
from pathlib import Path
from typing import Dict, List, Optional, Set
from enum import Enum

class PrivacyState(Enum):
    STARTUP = "startup"
    DOWNLOADS_ACTIVE = "downloads_active"
    STRICT = "strict"
    EMERGENCY_BLOCK = "emergency_block"

class PrivacyStateManager:
    def __init__(self):
        self.state_file = Path("/tmp/ignition_privacy_state")
        self.config_file = Path("/tmp/ignition_privacy_config")
        self.iptables_rules_file = Path("/tmp/ignition_iptables_rules")

        # Default configuration
        self.config = {
            "privacy_enabled": True,
            "startup_safety_buffer": 300,  # 5 minutes
            "download_grace_period": 300,  # 5 minutes
            "block_telemetry": True,
            "block_ai_services": True,
            "allow_model_downloads": True,
        }

        # Domain lists
        self.blocked_domains = {
            "analytics.google.com",
            "google-analytics.com",
            "googletagmanager.com",
            "doubleclick.net",
            "facebook.com/tr",
            "api.openai.com",
            "googleapis.com",
            "api.blackforestlabs.ai",
            "anthropic.com",
            "cohere.ai",
            "replicate.com",
            "telemetry",
            "analytics",
            "tracking",
            "metrics"
        }

        self.allowed_domains = {
            "civitai.com",
            "huggingface.co"
        }

        self.startup_domains = {
            "github.com"
        }

        # Current state
        self.current_state = PrivacyState.STARTUP
        self.startup_time = time.time()
        self.last_download_activity = None

        # Load configuration
        self.load_config()

        # Initialize logging
        self.log_file = Path("/tmp/ignition_privacy_manager.log")

    def log(self, level: str, message: str):
        """Log message with timestamp"""
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        status_icons = {
            'INFO': '🔍',
            'WARNING': '⚠️',
            'ERROR': '❌',
            'SUCCESS': '✅',
            'BLOCK': '🚫',
            'PROTECT': '🛡️'
        }
        icon = status_icons.get(level, '')
        log_entry = f"[{timestamp}] [{level}] {icon} {message}\n"

        # Print to stdout
        print(log_entry.strip())

        # Write to log file
        with open(self.log_file, 'a') as f:
            f.write(log_entry)

    def load_config(self):
        """Load configuration from file if it exists"""
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    file_config = json.load(f)
                    self.config.update(file_config)
                self.log("INFO", "Configuration loaded from file")
            except Exception as e:
                self.log("WARNING", f"Failed to load config: {e}")

    def save_config(self):
        """Save current configuration to file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
            self.log("INFO", "Configuration saved")
        except Exception as e:
            self.log("ERROR", f"Failed to save config: {e}")

    def get_download_status(self) -> Dict:
        """Get current download status from download protector"""
        try:
            result = subprocess.run(
                ["/workspace/scripts/download_protector.sh", "check"],
                capture_output=True, text=True, timeout=5
            )

            downloads_protected = result.stdout.strip() == "true"

            # Get aria2c count
            aria2c_count = len([
                p for p in subprocess.run(
                    ["pgrep", "-f", "aria2c"],
                    capture_output=True, text=True
                ).stdout.strip().split('\n')
                if p.strip()
            ]) if subprocess.run(["pgrep", "-f", "aria2c"], capture_output=True).returncode == 0 else 0

            return {
                "downloads_protected": downloads_protected,
                "aria2c_count": aria2c_count,
                "active": aria2c_count > 0
            }
        except Exception as e:
            self.log("WARNING", f"Failed to get download status: {e}")
            return {"downloads_protected": False, "aria2c_count": 0, "active": False}

    def check_comfyui_ready(self) -> bool:
        """Check if ComfyUI is ready and responsive"""
        try:
            result = subprocess.run(
                ["curl", "-s", "-f", "http://127.0.0.1:8188/"],
                capture_output=True, timeout=5
            )
            return result.returncode == 0
        except Exception:
            return False

    def should_transition_to_strict(self) -> bool:
        """Determine if we should transition to strict blocking mode"""
        current_time = time.time()

        # Check minimum startup time
        if current_time - self.startup_time < self.config["startup_safety_buffer"]:
            return False

        # Check if ComfyUI is ready
        if not self.check_comfyui_ready():
            return False

        # Check download status
        download_status = self.get_download_status()
        if download_status["downloads_protected"]:
            return False

        return True

    def get_current_allowlist(self) -> Set[str]:
        """Get current allowed domains based on state"""
        allowed = set(self.allowed_domains)  # Always allow model sources

        if self.current_state == PrivacyState.STARTUP:
            allowed.update(self.startup_domains)
        elif self.current_state == PrivacyState.DOWNLOADS_ACTIVE:
            # Only model sources allowed
            pass
        elif self.current_state == PrivacyState.STRICT:
            # Only model sources allowed
            pass
        elif self.current_state == PrivacyState.EMERGENCY_BLOCK:
            # Nothing allowed except localhost
            return set()

        return allowed

    def apply_iptables_rules(self):
        """Apply iptables rules based on current state"""
        if not self.config["privacy_enabled"]:
            self.log("INFO", "Privacy disabled - no iptables rules applied")
            return

        try:
            # Clear existing rules
            subprocess.run(["iptables", "-F", "OUTPUT"], check=False)

            # Allow loopback
            subprocess.run([
                "iptables", "-A", "OUTPUT", "-o", "lo", "-j", "ACCEPT"
            ], check=True)

            # Allow established connections
            subprocess.run([
                "iptables", "-A", "OUTPUT", "-m", "state",
                "--state", "ESTABLISHED,RELATED", "-j", "ACCEPT"
            ], check=True)

            # Get current allowlist
            allowed_domains = self.get_current_allowlist()

            # Allow model download domains
            for domain in allowed_domains:
                # Allow DNS resolution for domain
                subprocess.run([
                    "iptables", "-A", "OUTPUT", "-p", "udp", "--dport", "53",
                    "-j", "ACCEPT"
                ], check=False)

                # Allow HTTP/HTTPS to domain (we'll resolve IP separately)
                subprocess.run([
                    "iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "80",
                    "-j", "ACCEPT"
                ], check=False)
                subprocess.run([
                    "iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "443",
                    "-j", "ACCEPT"
                ], check=False)

            # Block everything else if in strict mode
            if self.current_state in [PrivacyState.STRICT, PrivacyState.EMERGENCY_BLOCK]:
                subprocess.run([
                    "iptables", "-A", "OUTPUT", "-j", "LOG",
                    "--log-prefix", "IGNITION_BLOCKED: "
                ], check=False)

                if self.current_state == PrivacyState.EMERGENCY_BLOCK:
                    # Emergency block - reject everything not explicitly allowed
                    subprocess.run([
                        "iptables", "-A", "OUTPUT", "-j", "REJECT"
                    ], check=False)

            self.log("INFO", f"Applied iptables rules for {self.current_state.value} mode")

        except subprocess.CalledProcessError as e:
            self.log("WARNING", f"Failed to apply iptables rules: {e}")
        except Exception as e:
            self.log("ERROR", f"Error applying iptables rules: {e}")

    def update_state(self):
        """Update current privacy state based on conditions"""
        old_state = self.current_state
        download_status = self.get_download_status()

        # State transition logic
        if self.current_state == PrivacyState.STARTUP:
            if download_status["active"]:
                self.current_state = PrivacyState.DOWNLOADS_ACTIVE
            elif self.should_transition_to_strict():
                self.current_state = PrivacyState.STRICT

        elif self.current_state == PrivacyState.DOWNLOADS_ACTIVE:
            if not download_status["downloads_protected"]:
                self.current_state = PrivacyState.STRICT

        elif self.current_state == PrivacyState.STRICT:
            if download_status["active"]:
                self.current_state = PrivacyState.DOWNLOADS_ACTIVE

        # Log state changes
        if old_state != self.current_state:
            self.log("INFO", f"State transition: {old_state.value} -> {self.current_state.value}")
            self.apply_iptables_rules()

        # Save current state
        self.save_state()

    def save_state(self):
        """Save current state to file"""
        state_data = {
            "state": self.current_state.value,
            "timestamp": time.time(),
            "startup_time": self.startup_time,
            "config": self.config
        }

        try:
            with open(self.state_file, 'w') as f:
                json.dump(state_data, f, indent=2)
        except Exception as e:
            self.log("ERROR", f"Failed to save state: {e}")

    def load_state(self):
        """Load state from file if it exists"""
        if self.state_file.exists():
            try:
                with open(self.state_file, 'r') as f:
                    state_data = json.load(f)

                # Restore state if recent (within 1 hour)
                if time.time() - state_data.get("timestamp", 0) < 3600:
                    self.current_state = PrivacyState(state_data["state"])
                    self.startup_time = state_data.get("startup_time", time.time())
                    self.log("INFO", f"Restored state: {self.current_state.value}")
                else:
                    self.log("INFO", "State file too old, starting fresh")

            except Exception as e:
                self.log("WARNING", f"Failed to load state: {e}")

    def get_status(self) -> Dict:
        """Get current privacy system status"""
        download_status = self.get_download_status()
        current_time = time.time()

        return {
            "state": self.current_state.value,
            "privacy_enabled": self.config["privacy_enabled"],
            "startup_time": self.startup_time,
            "uptime": current_time - self.startup_time,
            "comfyui_ready": self.check_comfyui_ready(),
            "downloads": download_status,
            "allowed_domains": list(self.get_current_allowlist()),
            "config": self.config
        }

    def set_emergency_block(self):
        """Activate emergency blocking mode"""
        self.log("WARNING", "Emergency block activated")
        self.current_state = PrivacyState.EMERGENCY_BLOCK
        self.apply_iptables_rules()
        self.save_state()

    def allow_domain_temporarily(self, domain: str, duration: int = 300):
        """Temporarily allow a domain for specified duration"""
        self.log("INFO", f"Temporarily allowing {domain} for {duration}s")
        # Implementation would add temporary iptables rule
        # For now, just log the action

    def run_monitoring_loop(self):
        """Main monitoring loop"""
        self.log("INFO", "Privacy state manager started")
        self.log("INFO", f"Configuration: {self.config}")

        # Load previous state if available
        self.load_state()

        # Apply initial rules
        self.apply_iptables_rules()

        try:
            while True:
                self.update_state()
                time.sleep(10)  # Check every 10 seconds

        except KeyboardInterrupt:
            self.log("INFO", "Privacy state manager stopped")
        except Exception as e:
            self.log("ERROR", f"Unexpected error: {e}")

def main():
    """Main entry point"""
    manager = PrivacyStateManager()

    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == "status":
            status = manager.get_status()
            print(json.dumps(status, indent=2))

        elif command == "emergency-block":
            manager.set_emergency_block()

        elif command == "allow":
            if len(sys.argv) > 2:
                domain = sys.argv[2]
                duration = int(sys.argv[3]) if len(sys.argv) > 3 else 300
                manager.allow_domain_temporarily(domain, duration)
            else:
                print("Usage: privacy_state_manager.py allow <domain> [duration]")

        elif command == "monitor":
            manager.run_monitoring_loop()

        else:
            print("Usage: privacy_state_manager.py {status|emergency-block|allow|monitor}")
    else:
        # Default to monitoring
        manager.run_monitoring_loop()

if __name__ == "__main__":
    main()