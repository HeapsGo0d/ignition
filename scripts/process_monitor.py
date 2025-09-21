#!/usr/bin/env python3
"""
Process Monitor - Container-aware process tracking via /proc filesystem
Part of Ignition Activity-Based Privacy Protection System

Uses direct /proc parsing for maximum reliability in Docker containers.
Tracks process lifecycle, command lines, and parent-child relationships.
"""

import os
import time
import threading
from pathlib import Path
from typing import Dict, List, Optional, NamedTuple
from dataclasses import dataclass
from collections import defaultdict


@dataclass
class ProcessInfo:
    """Container for process information parsed from /proc"""
    pid: int
    ppid: int
    command: str
    cmdline: List[str]
    cwd: str
    start_time: float
    uid: int
    gid: int

    @property
    def full_cmdline(self) -> str:
        """Get full command line as string"""
        return ' '.join(self.cmdline)


class ProcessTree:
    """Maintains process tree relationships for container awareness"""

    def __init__(self):
        self.processes: Dict[int, ProcessInfo] = {}
        self.children: Dict[int, List[int]] = defaultdict(list)
        self.container_init_pid = self._detect_container_init()

    def _detect_container_init(self) -> int:
        """Detect container init process (usually PID 1 in containers)"""
        try:
            # In containers, PID 1 is typically the init process
            if os.path.exists('/proc/1/comm'):
                with open('/proc/1/comm', 'r') as f:
                    init_comm = f.read().strip()
                # Common container init processes
                if init_comm in ['systemd', 'init', 'sh', 'bash', 'python', 'python3']:
                    return 1
        except (FileNotFoundError, PermissionError):
            pass
        return 1  # Default to PID 1

    def add_process(self, proc_info: ProcessInfo):
        """Add process to tree and update relationships"""
        self.processes[proc_info.pid] = proc_info
        if proc_info.ppid != 0:
            self.children[proc_info.ppid].append(proc_info.pid)

    def remove_process(self, pid: int):
        """Remove process and update relationships"""
        if pid in self.processes:
            proc_info = self.processes[pid]
            # Remove from parent's children list
            if proc_info.ppid in self.children:
                self.children[proc_info.ppid] = [
                    p for p in self.children[proc_info.ppid] if p != pid
                ]
            # Remove the process
            del self.processes[pid]
            if pid in self.children:
                del self.children[pid]

    def get_lineage(self, pid: int) -> List[ProcessInfo]:
        """Get process lineage from container init to specified PID"""
        lineage = []
        current_pid = pid

        while current_pid != self.container_init_pid and current_pid in self.processes:
            proc_info = self.processes[current_pid]
            lineage.append(proc_info)
            current_pid = proc_info.ppid

            # Prevent infinite loops
            if len(lineage) > 50:
                break

        return lineage

    def get_children(self, pid: int, recursive: bool = False) -> List[int]:
        """Get child processes, optionally recursive"""
        if not recursive:
            return self.children.get(pid, [])

        all_children = []
        to_process = [pid]

        while to_process:
            current_pid = to_process.pop(0)
            children = self.children.get(current_pid, [])
            all_children.extend(children)
            to_process.extend(children)

        return all_children


class ContainerProcessMonitor:
    """
    Container-aware process monitor using direct /proc filesystem access.
    Optimized for Docker containers with PID namespace awareness.
    """

    def __init__(self, poll_interval: float = 1.0):
        self.poll_interval = poll_interval
        self.process_tree = ProcessTree()
        self.monitoring = False
        self.monitor_thread: Optional[threading.Thread] = None
        self.callbacks = {
            'process_started': [],
            'process_ended': [],
            'command_detected': []
        }

        # Cache for performance
        self._proc_cache = {}
        self._last_scan = 0

    def register_callback(self, event: str, callback):
        """Register callback for process events"""
        if event in self.callbacks:
            self.callbacks[event].append(callback)

    def _parse_proc_stat(self, pid: int) -> Optional[tuple]:
        """Parse /proc/[pid]/stat for basic process info"""
        try:
            with open(f'/proc/{pid}/stat', 'r') as f:
                fields = f.read().strip().split()
                if len(fields) >= 4:
                    return (
                        int(fields[0]),  # pid
                        fields[1],       # comm (command name in parentheses)
                        fields[2],       # state
                        int(fields[3])   # ppid
                    )
        except (FileNotFoundError, PermissionError, ValueError):
            pass
        return None

    def _parse_proc_cmdline(self, pid: int) -> List[str]:
        """Parse /proc/[pid]/cmdline for full command line"""
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline_bytes = f.read()
                if cmdline_bytes:
                    # Command line arguments are null-separated
                    return cmdline_bytes.decode('utf-8', errors='replace').split('\x00')[:-1]
        except (FileNotFoundError, PermissionError, UnicodeDecodeError):
            pass
        return []

    def _get_proc_cwd(self, pid: int) -> str:
        """Get process current working directory"""
        try:
            return os.readlink(f'/proc/{pid}/cwd')
        except (FileNotFoundError, PermissionError, OSError):
            return ""

    def _get_proc_uid_gid(self, pid: int) -> tuple:
        """Get process UID and GID from /proc/[pid]/status"""
        try:
            with open(f'/proc/{pid}/status', 'r') as f:
                uid = gid = 0
                for line in f:
                    if line.startswith('Uid:'):
                        uid = int(line.split()[1])  # Real UID
                    elif line.startswith('Gid:'):
                        gid = int(line.split()[1])  # Real GID
                return uid, gid
        except (FileNotFoundError, PermissionError, ValueError):
            pass
        return 0, 0

    def _get_process_info(self, pid: int) -> Optional[ProcessInfo]:
        """Get complete process information from /proc filesystem"""
        stat_info = self._parse_proc_stat(pid)
        if not stat_info:
            return None

        pid_val, comm, state, ppid = stat_info

        # Skip zombie processes
        if state == 'Z':
            return None

        cmdline = self._parse_proc_cmdline(pid)
        cwd = self._get_proc_cwd(pid)
        uid, gid = self._get_proc_uid_gid(pid)

        # Use command from cmdline if available, fallback to comm
        command = cmdline[0] if cmdline else comm.strip('()')

        return ProcessInfo(
            pid=pid_val,
            ppid=ppid,
            command=command,
            cmdline=cmdline,
            cwd=cwd,
            start_time=time.time(),  # Approximation for new processes
            uid=uid,
            gid=gid
        )

    def _scan_processes(self) -> Dict[int, ProcessInfo]:
        """Scan /proc for all current processes"""
        current_processes = {}

        try:
            for pid_str in os.listdir('/proc'):
                if pid_str.isdigit():
                    pid = int(pid_str)
                    proc_info = self._get_process_info(pid)
                    if proc_info:
                        current_processes[pid] = proc_info
        except OSError:
            pass

        return current_processes

    def _detect_process_changes(self, current_processes: Dict[int, ProcessInfo]):
        """Detect new and ended processes"""
        current_pids = set(current_processes.keys())
        previous_pids = set(self.process_tree.processes.keys())

        # New processes
        new_pids = current_pids - previous_pids
        for pid in new_pids:
            proc_info = current_processes[pid]
            self.process_tree.add_process(proc_info)

            # Trigger callbacks
            for callback in self.callbacks['process_started']:
                try:
                    callback(proc_info)
                except Exception as e:
                    print(f"Error in process_started callback: {e}")

            # Check for interesting commands
            if self._is_interesting_command(proc_info):
                for callback in self.callbacks['command_detected']:
                    try:
                        callback(proc_info)
                    except Exception as e:
                        print(f"Error in command_detected callback: {e}")

        # Ended processes
        ended_pids = previous_pids - current_pids
        for pid in ended_pids:
            if pid in self.process_tree.processes:
                proc_info = self.process_tree.processes[pid]
                self.process_tree.remove_process(pid)

                # Trigger callbacks
                for callback in self.callbacks['process_ended']:
                    try:
                        callback(proc_info)
                    except Exception as e:
                        print(f"Error in process_ended callback: {e}")

    def _is_interesting_command(self, proc_info: ProcessInfo) -> bool:
        """Check if command is interesting for activity detection"""
        interesting_commands = [
            'pip', 'pip3', 'python -m pip',
            'git', 'wget', 'curl', 'aria2c',
            'apt', 'apt-get', 'yum', 'dnf',
            'npm', 'yarn', 'node'
        ]

        command_lower = proc_info.command.lower()
        cmdline_str = proc_info.full_cmdline.lower()

        return any(cmd in command_lower or cmd in cmdline_str
                  for cmd in interesting_commands)

    def start_monitoring(self):
        """Start process monitoring in background thread"""
        if self.monitoring:
            return

        self.monitoring = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.monitor_thread.start()

    def stop_monitoring(self):
        """Stop process monitoring"""
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=5)

    def _monitor_loop(self):
        """Main monitoring loop"""
        # Initial scan to populate process tree
        initial_processes = self._scan_processes()
        for proc_info in initial_processes.values():
            self.process_tree.add_process(proc_info)

        while self.monitoring:
            try:
                current_processes = self._scan_processes()
                self._detect_process_changes(current_processes)
                time.sleep(self.poll_interval)
            except Exception as e:
                print(f"Error in process monitoring loop: {e}")
                time.sleep(self.poll_interval)

    def get_process(self, pid: int) -> Optional[ProcessInfo]:
        """Get process information by PID"""
        return self.process_tree.processes.get(pid)

    def get_processes_by_command(self, command: str) -> List[ProcessInfo]:
        """Get all processes matching a command pattern"""
        matching = []
        for proc_info in self.process_tree.processes.values():
            if command.lower() in proc_info.command.lower():
                matching.append(proc_info)
        return matching

    def get_process_lineage(self, pid: int) -> List[ProcessInfo]:
        """Get process lineage from container init"""
        return self.process_tree.get_lineage(pid)

    def is_child_of(self, child_pid: int, parent_pid: int) -> bool:
        """Check if one process is a child of another"""
        lineage = self.get_process_lineage(child_pid)
        return any(proc.pid == parent_pid for proc in lineage)


def main():
    """Test/demo the process monitor"""
    monitor = ContainerProcessMonitor(poll_interval=2.0)

    def on_process_started(proc_info: ProcessInfo):
        print(f"📦 New process: {proc_info.pid} - {proc_info.command}")
        if proc_info.cmdline:
            print(f"    Command: {proc_info.full_cmdline}")
        print(f"    CWD: {proc_info.cwd}")
        print(f"    Parent: {proc_info.ppid}")

    def on_interesting_command(proc_info: ProcessInfo):
        print(f"🔍 Interesting command detected: {proc_info.full_cmdline}")
        lineage = monitor.get_process_lineage(proc_info.pid)
        if lineage:
            print("    Process lineage:")
            for i, ancestor in enumerate(lineage):
                indent = "    " + "  " * i
                print(f"{indent}└─ {ancestor.pid}: {ancestor.command}")

    monitor.register_callback('process_started', on_process_started)
    monitor.register_callback('command_detected', on_interesting_command)

    print("🚀 Starting container process monitor...")
    print(f"📊 Container init PID: {monitor.process_tree.container_init_pid}")
    print("Press Ctrl+C to stop")

    try:
        monitor.start_monitoring()

        # Keep running until interrupted
        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\n🛑 Stopping process monitor...")
        monitor.stop_monitoring()


if __name__ == "__main__":
    main()