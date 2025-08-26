#!/usr/bin/env python3
"""
Simple HuggingFace downloader for Ignition based on Hearmeman's approach.
Uses aria2c for reliable downloads with direct model URLs.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path
from typing import Dict, List

# Constants
ARIA2_CONNECTIONS = 16  # Hearmeman's settings
ARIA2_SPLITS = 16
PROGRESS_INTERVAL = 5

# Status indicators
STATUS = {
    'success': '✅',
    'error': '❌', 
    'warning': '⚠️',
    'info': '🔍',
    'download': '📥'
}

# Hearmeman's proven FLUX model URLs
FLUX_MODELS = {
    'flux1-dev': {
        'url': 'https://huggingface.co/lllyasviel/flux1_dev/resolve/main/flux1-dev-fp8.safetensors',
        'filename': 'flux1-dev-fp8.safetensors'
    },
    'clip_l': {
        'url': 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors', 
        'filename': 'clip_l.safetensors'
    },
    't5xxl_fp8': {
        'url': 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors',
        'filename': 't5xxl_fp8_e4m3fn.safetensors'
    },
    'ae': {
        'url': 'https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors',
        'filename': 'ae.safetensors'
    }
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
    """Download file using aria2c with Hearmeman's settings."""
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

def normalize_flux_key(model_input: str) -> str:
    """Convert HF repo names to internal FLUX keys."""
    # Map common HF repo formats to our internal keys
    repo_mappings = {
        'black-forest-labs/FLUX.1-dev': 'flux1-dev',
        'black-forest-labs/FLUX.1-schnell': 'ae',  # ae.safetensors is from schnell
        'lllyasviel/flux1_dev': 'flux1-dev',
        'comfyanonymous/flux_text_encoders': 'clip_l,t5xxl_fp8'  # This repo has multiple files
    }
    
    # Check if it's a direct repo mapping
    if model_input in repo_mappings:
        return repo_mappings[model_input]
    
    # If it's already a key, return as-is
    if model_input in FLUX_MODELS:
        return model_input
        
    # Default fallback
    return model_input

def download_flux_model(model_key: str, output_dir: Path, token: str = "") -> bool:
    """Download a specific FLUX model using Hearmeman's proven URLs."""
    
    if model_key not in FLUX_MODELS:
        log('error', f'Unknown FLUX model: {model_key}. Available: {", ".join(FLUX_MODELS.keys())}')
        return False
    
    model_info = FLUX_MODELS[model_key]
    url = model_info['url']
    filename = model_info['filename']
    
    log('info', f'Downloading FLUX model: {model_key}')
    return download_with_aria2(url, output_dir, filename, token)

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Simple HuggingFace downloader for Ignition using Hearmeman\'s approach')
    parser.add_argument('--repos', required=True, help='Comma-separated list of FLUX model keys: flux1-dev,clip_l,t5xxl_fp8,ae')
    parser.add_argument('--token', default='', help='HuggingFace API token')
    parser.add_argument('--output-dir', default='/workspace/ComfyUI/models/checkpoints', 
                        help='Output directory')
    
    args = parser.parse_args()
    
    # Get token from environment if not provided
    token = args.token or os.getenv('HF_TOKEN', '')
    
    if not token:
        log('warning', 'No HuggingFace token provided - downloads may fail for gated models')
    
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    model_inputs = [key.strip() for key in args.repos.split(',') if key.strip()]
    
    if not model_inputs:
        log('error', 'No model inputs provided')
        return 1
    
    # Normalize all inputs and expand multi-model repos
    all_model_keys = []
    for model_input in model_inputs:
        normalized = normalize_flux_key(model_input)
        if ',' in normalized:  # Multi-model repo like comfyanonymous/flux_text_encoders
            all_model_keys.extend([k.strip() for k in normalized.split(',')])
        else:
            all_model_keys.append(normalized)
    
    log('info', f'Starting download of {len(all_model_keys)} FLUX models to {output_dir}')
    log('info', f'Normalized model keys: {", ".join(all_model_keys)}')
    log('info', f'Available models: {", ".join(FLUX_MODELS.keys())}')
    
    success_count = 0
    for model_key in all_model_keys:
        if download_flux_model(model_key, output_dir, token):
            success_count += 1
        else:
            log('warning', f'Failed to download model {model_key}')
    
    log('info', f'Downloaded {success_count}/{len(all_model_keys)} models successfully')
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())