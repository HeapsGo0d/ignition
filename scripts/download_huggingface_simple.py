#!/usr/bin/env python3
"""
Simple HuggingFace downloader for Ignition based on Hearmeman's approach.
Uses aria2c for reliable downloads with direct model URLs.
"""

import os
import sys
import argparse
from pathlib import Path
from typing import Dict, List

# Import shared utilities
from download_utils import log, download_with_aria2, validate_huggingface_repo, validate_models_list

# ComfyUI workflow FLUX model URLs with proper directory structure
FLUX_MODELS = {
    'flux1-dev': {
        'url': 'https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev.safetensors',
        'filename': 'flux1-dev.safetensors',
        'subdir': 'diffusion_models'
    },
    'clip_l': {
        'url': 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors', 
        'filename': 'clip_l.safetensors',
        'subdir': 'text_encoders'
    },
    't5xxl_fp16': {
        'url': 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors',
        'filename': 't5xxl_fp16.safetensors',
        'subdir': 'text_encoders'
    },
    't5xxl_fp8': {
        'url': 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn_scaled.safetensors',
        'filename': 't5xxl_fp8_e4m3fn_scaled.safetensors',
        'subdir': 'text_encoders'
    },
    'ae': {
        'url': 'https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors',
        'filename': 'ae.safetensors',
        'subdir': 'vae'
    },
    'flux1-krea-dev': {
        'url': 'https://huggingface.co/black-forest-labs/FLUX.1-Krea-dev/resolve/main/flux1-krea-dev.safetensors',
        'filename': 'flux1-krea-dev.safetensors',
        'subdir': 'diffusion_models'
    }
}


def normalize_flux_key(model_input: str) -> str:
    """Convert HF repo names to internal FLUX keys."""
    # Map common HF repo formats to our internal keys
    repo_mappings = {
        'black-forest-labs/FLUX.1-dev': 'flux1-dev',
        'black-forest-labs/FLUX.1-schnell': 'ae',
        'Comfy-Org/flux1-dev': 'flux1-dev',
        'comfyanonymous/flux_text_encoders': 'clip_l,t5xxl_fp16'  # Default to fp16 variant
    }
    
    # Check if it's a direct repo mapping
    if model_input in repo_mappings:
        return repo_mappings[model_input]
    
    # If it's already a key, return as-is
    if model_input in FLUX_MODELS:
        return model_input
        
    # Default fallback
    return model_input

def parse_generic_repo(model_input: str) -> dict:
    """Parse generic HuggingFace repo format: repo:filename:subdir[:branch]"""
    parts = model_input.split(':')
    if len(parts) < 3:
        return None
        
    repo = parts[0]
    filename = parts[1] 
    subdir = parts[2]
    branch = parts[3] if len(parts) > 3 else 'main'
    
    url = f"https://huggingface.co/{repo}/resolve/{branch}/{filename}"
    
    return {
        'url': url,
        'filename': filename,
        'subdir': subdir
    }

def download_flux_model(model_key: str, base_output_dir: Path, token: str = "") -> bool:
    """Download a FLUX model - supports both predefined models and generic HF repos."""
    
    model_info = None
    
    # Check if it's a predefined model
    if model_key in FLUX_MODELS:
        model_info = FLUX_MODELS[model_key]
        log('info', f'Downloading predefined FLUX model: {model_key}')
    
    # Check if it's a generic repo format (contains colons)
    elif ':' in model_key:
        model_info = parse_generic_repo(model_key)
        if model_info:
            log('info', f'Downloading generic HuggingFace model: {model_key}')
        else:
            log('error', f'Invalid generic repo format: {model_key}. Use: repo:filename:subdir[:branch]')
            return False
    
    # Unknown model
    else:
        log('error', f'Unknown FLUX model: {model_key}. Available predefined: {", ".join(FLUX_MODELS.keys())}')
        log('info', f'Or use generic format: repo:filename:subdir[:branch]')
        return False
    
    url = model_info['url']
    filename = model_info['filename']
    subdir = model_info['subdir']
    
    # Create the proper subdirectory
    target_dir = base_output_dir / subdir
    
    log('info', f'Target directory: {subdir}/')
    return download_with_aria2(url, target_dir, filename, token)

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Simple HuggingFace downloader for Ignition using Hearmeman\'s approach')
    parser.add_argument('--repos', required=True, help='Comma-separated list of FLUX model keys. Predefined: flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev. Generic format: repo:filename:subdir[:branch]')
    parser.add_argument('--token', default='', help='HuggingFace API token')
    parser.add_argument('--output-dir', default='/workspace/ComfyUI/models', 
                        help='Base ComfyUI models directory')
    
    args = parser.parse_args()
    
    # Get token from environment if not provided
    token = args.token or os.getenv('HF_TOKEN', '')
    
    if not token:
        log('warning', 'No HuggingFace token provided - downloads may fail for gated models')
    
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Validate HuggingFace repository inputs
    valid_model_inputs = validate_models_list(args.repos, validate_huggingface_repo, 'HuggingFace')

    if not valid_model_inputs:
        log('error', 'No valid HuggingFace models provided after validation')
        log('info', 'Use format: username/repository or predefined models like flux1-dev')
        return 1
    
    # Normalize all inputs and expand multi-model repos
    all_model_keys = []
    for model_input in valid_model_inputs:
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