#!/usr/bin/env python3
import sys
sys.path.append('/workspace/scripts')
from process_monitor import ContainerProcessMonitor

print("🔍 Simple Process Debug")
print("=" * 30)

monitor = ContainerProcessMonitor()
processes_dict = monitor._scan_processes()
processes = list(processes_dict.values())

print(f"Total processes found: {len(processes)}")
print()

# Look for any pip processes
pip_procs = [p for p in processes if 'pip' in p.command or any('pip' in arg for arg in p.cmdline)]
if pip_procs:
    print("🐍 Pip processes found:")
    for proc in pip_procs:
        print(f"  PID {proc.pid}: {proc.command}")
        print(f"  Cmdline: {proc.cmdline}")
        print(f"  Working dir: {proc.cwd}")
        print()
else:
    print("❌ No pip processes found")

# Show python processes
python_procs = [p for p in processes if 'python' in p.command]
print(f"\n🐍 Python processes: {len(python_procs)}")
for proc in python_procs[:5]:
    cmdline_short = ' '.join(proc.cmdline[:3]) + ('...' if len(proc.cmdline) > 3 else '')
    print(f"  PID {proc.pid}: {proc.command} - {cmdline_short}")

print(f"\nFirst 10 processes:")
for proc in processes[:10]:
    print(f"  PID {proc.pid}: {proc.command}")