#!/usr/bin/env python3
"""
Simple HuggingFace downloader for Ignition.
Uses git-lfs for reliable large file downloads.
"""

import os
import sys
import subprocess
import argparse
import shutil
from pathlib import Path
from typing import List

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

def ensure_git_lfs():
    """Check if git-lfs is available."""
    try:
        subprocess.run(['git', 'lfs', 'version'], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        log('warning', 'git-lfs not available, trying regular git clone')
        return False

def clone_huggingface_repo(repo: str, output_dir: Path, token: str = "") -> bool:
    """Clone a HuggingFace repository."""
    
    # Parse repo name
    if '/' not in repo:
        log('error', f'Invalid repo format: {repo}. Use format: username/repo')
        return False
    
    repo_name = repo.split('/')[-1]
    repo_path = output_dir / repo_name
    
    # Remove existing directory
    if repo_path.exists():
        log('info', f'Removing existing {repo_name}')
        shutil.rmtree(repo_path)
    
    # Build clone URL
    if token:
        clone_url = f"https://{token}@huggingface.co/{repo}"
    else:
        clone_url = f"https://huggingface.co/{repo}"
    
    log('download', f'Cloning {repo}...')
    
    try:
        # Try with git-lfs first
        has_lfs = ensure_git_lfs()
        if has_lfs:
            subprocess.run(['git', 'lfs', 'install'], check=False, capture_output=True)
        
        cmd = ['git', 'clone', '--depth', '1', clone_url, str(repo_path)]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        
        # Check if we got any useful files
        model_files = list(repo_path.rglob('*.safetensors')) + \
                     list(repo_path.rglob('*.bin')) + \
                     list(repo_path.rglob('*.pt'))
        
        if model_files:
            total_size = sum(f.stat().st_size for f in model_files) // (1024 * 1024)
            log('success', f'Cloned {repo} with {len(model_files)} model files ({total_size}MB)')
            return True
        else:
            log('warning', f'Cloned {repo} but no model files found')
            return True  # Still consider success - might be config files
            
    except subprocess.CalledProcessError as e:
        log('error', f'Git clone failed for {repo}: {e.stderr}')
        if repo_path.exists():
            shutil.rmtree(repo_path)
        return False
    except Exception as e:
        log('error', f'Unexpected error cloning {repo}: {e}')
        return False

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Simple HuggingFace downloader for Ignition')
    parser.add_argument('--repos', required=True, help='Comma-separated list of repo names (user/repo)')
    parser.add_argument('--token', default='', help='HuggingFace API token')
    parser.add_argument('--output-dir', default='/workspace/ComfyUI/models/checkpoints', 
                        help='Output directory')
    
    args = parser.parse_args()
    
    # Get token from environment if not provided
    token = args.token or os.getenv('HF_TOKEN', '')
    
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    repos = [repo.strip() for repo in args.repos.split(',') if repo.strip()]
    
    if not repos:
        log('error', 'No repositories provided')
        return 1
    
    log('info', f'Starting download of {len(repos)} repositories to {output_dir}')
    
    success_count = 0
    for repo in repos:
        if clone_huggingface_repo(repo, output_dir, token):
            success_count += 1
        else:
            log('warning', f'Failed to clone repository {repo}')
    
    log('info', f'Downloaded {success_count}/{len(repos)} repositories successfully')
    return 0 if success_count > 0 else 1

if __name__ == "__main__":
    sys.exit(main())