#!/usr/bin/env python3
"""
Simple CivitAI downloader for Ignition based on Hearmeman's approach.
Uses aria2c for reliable downloads with fallback strategies.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path
from typing import Optional, List
from urllib.parse import urlencode

# Constants
CIVITAI_API_BASE = "https://civitai.com/api"
ARIA2_CONNECTIONS = 4  # Conservative for container environments
ARIA2_SPLITS = 4
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

def download_with_aria2(url: str, output_dir: Path, filename: str) -> bool:
    """Download file using aria2c."""
    if not ensure_aria2():
        return False
    
    output_dir.mkdir(parents=True, exist_ok=True)
    file_path = output_dir / filename
    
    # Remove existing file to avoid conflicts
    if file_path.exists():
        file_path.unlink()
    
    cmd = [
        'aria2c',
        f'--max-connection-per-server={ARIA2_CONNECTIONS}',
        f'--split={ARIA2_SPLITS}',
        '--continue=true',
        '--auto-file-renaming=false',
        '--allow-overwrite=true',
        f'--summary-interval={PROGRESS_INTERVAL}',
        '--console-log-level=warn',
        f'--dir={output_dir}',
        f'--out={filename}',
        url
    ]
    
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

def download_civitai_model(model_id: str, output_dir: Path, token: str = "", filename: str = "") -> bool:
    """Download a CivitAI model with fallback strategies."""
    
    # Try SafeTensor format first
    params = {'type': 'Model', 'format': 'SafeTensor'}
    if token:
        params['token'] = token
    
    safetensor_url = f"{CIVITAI_API_BASE}/download/models/{model_id}?{urlencode(params)}"
    
    # Generate filename if not provided
    if not filename:
        filename = f"model_{model_id}.safetensors"
    elif not filename.endswith('.safetensors'):
        filename += '.safetensors'
    
    log('info', f'Attempting SafeTensor download for model {model_id}')
    if download_with_aria2(safetensor_url, output_dir, filename):
        return True
    
    # Fallback to any available format
    log('warning', 'SafeTensor failed, trying default format...')
    params = {'type': 'Model'}
    if token:
        params['token'] = token
    
    fallback_url = f"{CIVITAI_API_BASE}/download/models/{model_id}?{urlencode(params)}"
    fallback_filename = f"model_{model_id}.ckpt" if not filename.endswith(('.safetensors', '.ckpt', '.pt')) else filename
    
    if download_with_aria2(fallback_url, output_dir, fallback_filename):
        return True
    
    log('error', f'All download attempts failed for model {model_id}')
    return False

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Simple CivitAI downloader for Ignition')
    parser.add_argument('--models', required=True, help='Comma-separated list of model IDs')
    parser.add_argument('--token', default='', help='CivitAI API token')
    parser.add_argument('--output-dir', default='/workspace/ComfyUI/models/checkpoints', 
                        help='Output directory')
    
    args = parser.parse_args()
    
    # Get token from environment if not provided
    token = args.token or os.getenv('CIVITAI_TOKEN', '')
    
    output_dir = Path(args.output_dir)
    model_ids = [mid.strip() for mid in args.models.split(',') if mid.strip()]
    
    if not model_ids:
        log('error', 'No model IDs provided')
        return 1
    
    log('info', f'Starting download of {len(model_ids)} models to {output_dir}')
    
    success_count = 0
    for model_id in model_ids:
        if download_civitai_model(model_id, output_dir, token):
            success_count += 1
        else:
            log('warning', f'Failed to download model {model_id}')
    
    log('info', f'Downloaded {success_count}/{len(model_ids)} models successfully')
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())