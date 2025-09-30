#!/usr/bin/env python3
"""
Simple CivitAI downloader for Ignition based on Hearmeman's approach.
Uses aria2c for reliable downloads with fallback strategies.
"""

import os
import sys
import argparse
import requests
import re
from pathlib import Path
from typing import Optional, List, Dict, Union
from urllib.parse import urlencode

# Import shared utilities
from download_utils import log, download_with_aria2, validate_civitai_model_id, validate_models_list

# Constants
CIVITAI_API_BASE = "https://civitai.com/api"

def clean_filename(name: str, max_length: int = 50) -> str:
    """Clean and truncate filename for filesystem safety."""
    # Remove or replace invalid characters
    clean_name = re.sub(r'[<>:"/\\|?*]', '', name)
    clean_name = re.sub(r'[\s\-_]+', '_', clean_name.strip())
    
    # Truncate if too long
    if len(clean_name) > max_length:
        clean_name = clean_name[:max_length].rstrip('_')
    
    return clean_name

def get_model_info(model_id: str, token: str = "") -> Dict[str, any]:
    """Fetch model info from CivitAI API."""
    try:
        headers: Dict[str, str] = {}
        if token:
            headers['Authorization'] = f'Bearer {token}'
        
        response = requests.get(f"{CIVITAI_API_BASE}/v1/model-versions/{model_id}", 
                              headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 401:
            log('warning', f'Model {model_id}: Authentication failed. Check CIVITAI_TOKEN')
        elif e.response.status_code == 404:
            log('warning', f'Model {model_id}: Not found. Verify model version ID')
        else:
            log('warning', f'Model {model_id}: HTTP {e.response.status_code} error')
        return {}
    except requests.exceptions.RequestException as e:
        log('warning', f'Model {model_id}: Network error - {e}')
        return {}
    except Exception as e:
        log('warning', f'Model {model_id}: Unexpected error - {e}')
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


def download_civitai_model(model_id: str, output_dir: Path, token: str = "", filename: str = "", force: bool = False) -> bool:
    """Download a CivitAI model with fallback strategies."""

    # Try SafeTensor format first
    params: Dict[str, str] = {'type': 'Model', 'format': 'SafeTensor'}
    if token:
        params['token'] = token

    safetensor_url = f"{CIVITAI_API_BASE}/download/models/{model_id}?{urlencode(params)}"

    # Generate filename if not provided
    if not filename:
        filename = generate_filename(model_id, token)
    elif not filename.endswith('.safetensors'):
        filename += '.safetensors'

    log('info', f'Attempting SafeTensor download for model {model_id}')
    if download_with_aria2(safetensor_url, output_dir, filename, token="", force=force):
        return True

    # Fallback to any available format
    log('warning', 'SafeTensor failed, trying default format...')
    params = {'type': 'Model'}
    if token:
        params['token'] = token

    fallback_url = f"{CIVITAI_API_BASE}/download/models/{model_id}?{urlencode(params)}"
    fallback_filename = f"model_{model_id}.ckpt" if not filename.endswith(('.safetensors', '.ckpt', '.pt')) else filename

    if download_with_aria2(fallback_url, output_dir, fallback_filename, token="", force=force):
        return True

    log('error', f'All download attempts failed for model {model_id}')
    return False

def main() -> int:
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

    # Check for force sync flag
    force_sync = os.getenv('FORCE_MODEL_SYNC', 'false').lower() == 'true'
    if force_sync:
        log('info', '🔄 FORCE_MODEL_SYNC=true - will re-download existing files')

    base_output_dir = Path(args.output_dir)
    
    # Parse and validate model IDs
    model_ids = validate_models_list(args.models, validate_civitai_model_id, 'checkpoint')
    lora_ids = validate_models_list(args.loras, validate_civitai_model_id, 'LoRA')
    vae_ids = validate_models_list(args.vaes, validate_civitai_model_id, 'VAE')
    flux_ids = validate_models_list(args.flux, validate_civitai_model_id, 'FLUX')

    if not model_ids and not lora_ids and not vae_ids and not flux_ids:
        log('error', 'No valid model IDs provided after validation')
        log('info', 'CivitAI model IDs must be numeric (e.g., 123456)')
        return 1
    
    total_downloads = len(model_ids) + len(lora_ids) + len(vae_ids) + len(flux_ids)
    log('info', f'Starting download of {total_downloads} items ({len(model_ids)} models, {len(lora_ids)} LoRAs, {len(vae_ids)} VAEs, {len(flux_ids)} FLUX)')
    
    success_count = 0
    
    # Download regular models to checkpoints/
    if model_ids:
        checkpoints_dir = base_output_dir / 'checkpoints'
        log('info', f'Downloading {len(model_ids)} models to {checkpoints_dir}')
        for model_id in model_ids:
            if download_civitai_model(model_id, checkpoints_dir, token, force=force_sync):
                success_count += 1
            else:
                log('warning', f'Failed to download model {model_id}')

    # Download LoRAs to loras/
    if lora_ids:
        loras_dir = base_output_dir / 'loras'
        log('info', f'Downloading {len(lora_ids)} LoRAs to {loras_dir}')
        for lora_id in lora_ids:
            if download_civitai_model(lora_id, loras_dir, token, force=force_sync):
                success_count += 1
            else:
                log('warning', f'Failed to download LoRA {lora_id}')

    # Download VAEs to vae/
    if vae_ids:
        vaes_dir = base_output_dir / 'vae'
        log('info', f'Downloading {len(vae_ids)} VAEs to {vaes_dir}')
        for vae_id in vae_ids:
            if download_civitai_model(vae_id, vaes_dir, token, force=force_sync):
                success_count += 1
            else:
                log('warning', f'Failed to download VAE {vae_id}')

    # Download FLUX models to diffusion_models/
    if flux_ids:
        flux_dir = base_output_dir / 'diffusion_models'
        log('info', f'Downloading {len(flux_ids)} FLUX models to {flux_dir}')
        for flux_id in flux_ids:
            if download_civitai_model(flux_id, flux_dir, token, force=force_sync):
                success_count += 1
            else:
                log('warning', f'Failed to download FLUX model {flux_id}')
    
    log('info', f'Downloaded {success_count}/{total_downloads} items successfully')
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())