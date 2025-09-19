#!/usr/bin/env python3
"""
Shared utilities for Ignition downloaders.
Common functions for aria2c downloads, logging, and file operations.
"""

import subprocess
from pathlib import Path

# Constants - standardized across all downloaders
ARIA2_CONNECTIONS = 8  # Balanced performance for container environments
ARIA2_SPLITS = 8
PROGRESS_INTERVAL = 5

# Status indicators
STATUS = {
    'success': '✅',
    'error': '❌',
    'warning': '⚠️',
    'info': '🔍',
    'download': '📥'
}

def log(level: str, message: str):
    """Simple logging function matching startup.sh style."""
    print(f"{STATUS.get(level, '')} {message}")

def ensure_aria2():
    """Check if aria2c is available."""
    try:
        subprocess.run(['aria2c', '--version'], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        log('error', 'aria2c not found. Please install aria2.')
        return False

def download_with_aria2(url: str, output_dir: Path, filename: str, token: str = "") -> bool:
    """Download file using aria2c with standardized settings."""
    if not ensure_aria2():
        return False

    output_dir.mkdir(parents=True, exist_ok=True)
    file_path = output_dir / filename

    # Remove existing file to avoid conflicts
    if file_path.exists():
        file_path.unlink()

    cmd = [
        'aria2c',
        f'-x{ARIA2_CONNECTIONS}',
        f'-s{ARIA2_SPLITS}',
        '-k1M',
        '--continue=true',
        '--auto-file-renaming=false',
        '--allow-overwrite=true',
        f'--summary-interval={PROGRESS_INTERVAL}',
        '--console-log-level=warn',
        f'--dir={output_dir}',
        f'--out={filename}',
    ]

    # Add authorization header if token provided
    if token:
        cmd.append(f'--header=Authorization: Bearer {token}')

    cmd.append(url)

    log('download', f'Downloading {filename}...')

    try:
        result = subprocess.run(cmd, check=False, capture_output=False)

        # Check if file was downloaded
        if file_path.exists() and file_path.stat().st_size > 1024 * 1024:  # At least 1MB
            log('success', f'Downloaded {filename} ({file_path.stat().st_size // (1024*1024)}MB)')
            return True
        else:
            log('error', f'Download failed or file too small: {filename}')
            return False

    except Exception as e:
        log('error', f'Download error: {e}')
        return False