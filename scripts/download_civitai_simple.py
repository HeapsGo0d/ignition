#!/usr/bin/env python3
"""
Simple CivitAI downloader for Ignition based on Hearmeman's approach.
Uses aria2c for reliable downloads with fallback strategies.
"""

import os
import sys
import subprocess
import argparse
import requests
import re
from pathlib import Path
from typing import Optional, List, Dict
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

def clean_filename(name: str, max_length: int = 50) -> str:
    """Clean and truncate filename for filesystem safety."""
    # Remove or replace invalid characters
    clean_name = re.sub(r'[<>:"/\\|?*]', '', name)
    clean_name = re.sub(r'[\s\-_]+', '_', clean_name.strip())
    
    # Truncate if too long
    if len(clean_name) > max_length:
        clean_name = clean_name[:max_length].rstrip('_')
    
    return clean_name

def get_model_info(model_id: str, token: str = "") -> Dict:
    """Fetch model info from CivitAI API."""
    try:
        headers = {}
        if token:
            headers['Authorization'] = f'Bearer {token}'
        
        response = requests.get(f"{CIVITAI_API_BASE}/v1/model-versions/{model_id}", 
                              headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        log('warning', f'Failed to fetch model info for {model_id}: {e}')
        return {}

def generate_filename(model_id: str, token: str = "") -> str:
    """Generate hybrid filename with model name and ID."""
    model_info = get_model_info(model_id, token)
    
    if model_info and 'name' in model_info.get('model', {}):
        model_name = model_info['model']['name']
        clean_name = clean_filename(model_name, max_length=30)
        return f"{clean_name}_{model_id}.safetensors"
    else:
        # Fallback to ID-only naming
        return f"model_{model_id}.safetensors"

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
        filename = generate_filename(model_id, token)
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
    parser.add_argument('--models', default='', help='Comma-separated list of model IDs (checkpoints)')
    parser.add_argument('--loras', default='', help='Comma-separated list of LoRA model IDs')
    parser.add_argument('--vaes', default='', help='Comma-separated list of VAE model IDs')
    parser.add_argument('--flux', default='', help='Comma-separated list of FLUX model IDs')
    parser.add_argument('--token', default='', help='CivitAI API token')
    parser.add_argument('--output-dir', default='/workspace/ComfyUI/models', 
                        help='Base ComfyUI models directory')
    
    args = parser.parse_args()
    
    # Get token from environment if not provided
    token = args.token or os.getenv('CIVITAI_TOKEN', '')
    
    if not token:
        log('warning', 'No CIVITAI_TOKEN provided - downloads may fail for gated models')
    else:
        log('info', f'Using CivitAI token: {token[:8]}...')
    
    base_output_dir = Path(args.output_dir)
    
    # Parse model IDs
    model_ids = [mid.strip() for mid in args.models.split(',') if mid.strip()]
    lora_ids = [lid.strip() for lid in args.loras.split(',') if lid.strip()]
    vae_ids = [vid.strip() for vid in args.vaes.split(',') if vid.strip()]
    flux_ids = [fid.strip() for fid in args.flux.split(',') if fid.strip()]
    
    if not model_ids and not lora_ids and not vae_ids and not flux_ids:
        log('error', 'No model, LoRA, VAE, or FLUX IDs provided')
        return 1
    
    total_downloads = len(model_ids) + len(lora_ids) + len(vae_ids) + len(flux_ids)
    log('info', f'Starting download of {total_downloads} items ({len(model_ids)} models, {len(lora_ids)} LoRAs, {len(vae_ids)} VAEs, {len(flux_ids)} FLUX)')
    
    success_count = 0
    
    # Download regular models to checkpoints/
    if model_ids:
        checkpoints_dir = base_output_dir / 'checkpoints'
        log('info', f'Downloading {len(model_ids)} models to {checkpoints_dir}')
        for model_id in model_ids:
            if download_civitai_model(model_id, checkpoints_dir, token):
                success_count += 1
            else:
                log('warning', f'Failed to download model {model_id}')
    
    # Download LoRAs to loras/
    if lora_ids:
        loras_dir = base_output_dir / 'loras'
        log('info', f'Downloading {len(lora_ids)} LoRAs to {loras_dir}')
        for lora_id in lora_ids:
            if download_civitai_model(lora_id, loras_dir, token):
                success_count += 1
            else:
                log('warning', f'Failed to download LoRA {lora_id}')
    
    # Download VAEs to vae/
    if vae_ids:
        vaes_dir = base_output_dir / 'vae'
        log('info', f'Downloading {len(vae_ids)} VAEs to {vaes_dir}')
        for vae_id in vae_ids:
            if download_civitai_model(vae_id, vaes_dir, token):
                success_count += 1
            else:
                log('warning', f'Failed to download VAE {vae_id}')
    
    # Download FLUX models to diffusion_models/
    if flux_ids:
        flux_dir = base_output_dir / 'diffusion_models'
        log('info', f'Downloading {len(flux_ids)} FLUX models to {flux_dir}')
        for flux_id in flux_ids:
            if download_civitai_model(flux_id, flux_dir, token):
                success_count += 1
            else:
                log('warning', f'Failed to download FLUX model {flux_id}')
    
    log('info', f'Downloaded {success_count}/{total_downloads} items successfully')
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())