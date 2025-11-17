#!/usr/bin/env python3
"""
Shared utilities for Ignition downloaders.
Common functions for aria2c downloads, logging, and file operations.
"""

import subprocess
import re
from pathlib import Path
from typing import Callable, List

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

def download_with_aria2(url: str, output_dir: Path, filename: str, token: str = "", force: bool = False) -> bool:
    """Download file using aria2c with standardized settings."""
    if not ensure_aria2():
        return False

    output_dir.mkdir(parents=True, exist_ok=True)
    file_path = output_dir / filename

    # Check if file already exists (caching)
    if file_path.exists() and not force:
        file_size_mb = file_path.stat().st_size // (1024 * 1024)
        if file_size_mb > 0:  # Valid cached file
            log('info', f'✓ Cached: {filename} ({file_size_mb}MB)')
            return True

    # Remove existing file only when force=True or file is invalid
    if file_path.exists():
        log('info', f'Removing existing file: {filename} (force={force})')
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

def validate_civitai_model_id(model_id: str) -> bool:
    """Validate CivitAI model ID format and range."""
    if not model_id or not model_id.strip():
        log('error', f'Empty model ID provided')
        return False

    model_id = model_id.strip()

    # Must be numeric
    if not model_id.isdigit():
        log('error', f'Invalid CivitAI model ID: "{model_id}" - must be numeric')
        return False

    # Reasonable range check
    model_num = int(model_id)
    if model_num <= 0:
        log('error', f'Invalid CivitAI model ID: "{model_id}" - must be positive')
        return False

    if model_num > 10000000:  # 10 million seems reasonable upper bound
        log('error', f'Invalid CivitAI model ID: "{model_id}" - too large (>10M)')
        return False

    return True

def validate_huggingface_repo(repo: str) -> bool:
    """Validate HuggingFace repository format."""
    if not repo or not repo.strip():
        log('error', f'Empty repository name provided')
        return False

    repo = repo.strip()

    # Check for predefined models (single words or underscored keys)
    predefined_models = [
        'flux1-dev', 'clip_l', 't5xxl_fp16', 't5xxl_fp8', 'ae', 'flux1-krea-dev',
        'qwen_image_fp8', 'qwen_text_encoder_fp8', 'qwen_vae',
        'qwen_lightning_4step', 'qwen_lightning_8step'
    ]
    if repo in predefined_models:
        return True

    # Check generic repo format: repo:filename:subdir[:branch] or user/repo format
    if ':' in repo:
        parts = repo.split(':')
        if len(parts) < 3:
            log('error', f'Invalid HF repo format: "{repo}" - use repo:filename:subdir[:branch]')
            return False
        return True

    # Check standard HF repo format: username/repository
    if '/' not in repo:
        log('error', f'Invalid HF repo format: "{repo}" - use username/repository or predefined model')
        return False

    # Basic username/repo validation
    parts = repo.split('/')
    if len(parts) != 2 or not all(part.strip() for part in parts):
        log('error', f'Invalid HF repo format: "{repo}" - use username/repository')
        return False

    # Check for valid characters (basic validation)
    username, reponame = parts
    if not re.match(r'^[a-zA-Z0-9._-]+$', username) or not re.match(r'^[a-zA-Z0-9._-]+$', reponame):
        log('error', f'Invalid HF repo format: "{repo}" - contains invalid characters')
        return False

    return True

def validate_models_list(models_str: str, validator_func: Callable[[str], bool], model_type: str) -> List[str]:
    """Validate and parse comma-separated model list."""
    if not models_str or not models_str.strip():
        return []

    valid_models: List[str] = []
    invalid_count: int = 0

    models: List[str] = [m.strip() for m in models_str.split(',') if m.strip()]

    for model in models:
        if validator_func(model):
            valid_models.append(model)
        else:
            invalid_count += 1

    if invalid_count > 0:
        log('warning', f'{invalid_count} invalid {model_type} model IDs skipped')

    if valid_models:
        log('info', f'Validated {len(valid_models)} {model_type} models: {", ".join(valid_models[:3])}{"..." if len(valid_models) > 3 else ""}')

    return valid_models