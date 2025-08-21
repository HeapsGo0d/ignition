#!/usr/bin/env python3
"""
File utilities for atomic downloads and organization.
Ensures robust download -> verify -> move -> cleanup operations.
"""

import os
import shutil
import tempfile
import hashlib
import logging
from pathlib import Path
from typing import Optional

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AtomicFileHandler:
    """Handles atomic file operations for model downloads."""
    
    def __init__(self, workspace_root: str = "/workspace"):
        self.workspace_root = Path(workspace_root)
        # Use environment variable for consistent path
        models_dir = Path(os.environ.get('COMFYUI_MODELS_DIR', '/workspace/ComfyUI/models'))
        self.temp_dir = Path(tempfile.gettempdir()) / "ignition_downloads"
        self.temp_dir.mkdir(exist_ok=True)
        
        # Model type to directory mapping - aligned with ComfyUI expectations
        self.model_dirs = {
            'checkpoint': models_dir / 'checkpoints',
            'model': models_dir / 'checkpoints',
            'lora': models_dir / 'loras',
            'vae': models_dir / 'vae',
            'embedding': models_dir / 'embeddings',
            'controlnet': models_dir / 'controlnet',
            'upscaler': models_dir / 'upscale_models',
        }
        
        # Ensure all directories exist
        for dir_path in self.model_dirs.values():
            dir_path.mkdir(parents=True, exist_ok=True)

    def get_temp_path(self, filename: str) -> Path:
        """Generate a unique temporary file path."""
        return self.temp_dir / f"{os.getpid()}_{filename}"

    def calculate_file_hash(self, file_path: Path, algorithm: str = 'sha256') -> str:
        """Calculate file hash for verification."""
        hash_obj = hashlib.new(algorithm)
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()

    def verify_file(self, file_path: Path, expected_size: Optional[int] = None, 
                   expected_hash: Optional[str] = None) -> bool:
        """Verify downloaded file integrity."""
        if not file_path.exists():
            logger.error(f"File does not exist: {file_path}")
            return False
        
        # Check file size
        if expected_size is not None:
            actual_size = file_path.stat().st_size
            if actual_size != expected_size:
                logger.error(f"Size mismatch: expected {expected_size}, got {actual_size}")
                return False
        
        # Check file hash if provided
        if expected_hash is not None:
            actual_hash = self.calculate_file_hash(file_path)
            # Normalize both hashes to lowercase for comparison
            if actual_hash.strip().lower() != expected_hash.strip().lower():
                logger.error(f"Hash mismatch: expected {expected_hash}, got {actual_hash}")
                return False
        
        # Basic file corruption check - ensure file is not empty
        if file_path.stat().st_size == 0:
            logger.error(f"File is empty: {file_path}")
            return False
            
        logger.info(f"File verification successful: {file_path}")
        return True

    def get_destination_path(self, filename: str, model_type: str) -> Path:
        """Get the final destination path for a model file."""
        model_type = model_type.lower()
        
        # Map model types to directories
        if model_type in self.model_dirs:
            return self.model_dirs[model_type] / filename
        
        # Default to checkpoints if type is unknown
        logger.warning(f"Unknown model type '{model_type}', defaulting to checkpoints")
        return self.model_dirs['checkpoint'] / filename

    def file_exists_and_valid(self, destination_path: Path, expected_size: Optional[int] = None) -> bool:
        """Check if file already exists and is valid (for persistent storage)."""
        if not destination_path.exists():
            return False
        
        # Basic validation - check if file is not empty
        if destination_path.stat().st_size == 0:
            logger.warning(f"Existing file is empty, will redownload: {destination_path}")
            return False
        
        # If expected size is provided, validate it
        if expected_size is not None:
            actual_size = destination_path.stat().st_size
            if actual_size != expected_size:
                logger.warning(f"Existing file size mismatch, will redownload: {destination_path}")
                return False
        
        logger.info(f"Valid existing file found: {destination_path}")
        return True

    def atomic_move(self, temp_path: Path, destination_path: Path) -> bool:
        """
        Atomically move file from temp location to final destination.
        This prevents partial files from appearing at the destination.
        """
        try:
            # Ensure destination directory exists
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            
            # If destination exists, create a backup first
            backup_path = None
            if destination_path.exists():
                backup_path = destination_path.with_suffix(destination_path.suffix + '.backup')
                shutil.move(str(destination_path), str(backup_path))
                logger.info(f"Created backup: {backup_path}")
            
            # Perform the atomic move
            shutil.move(str(temp_path), str(destination_path))
            logger.info(f"Successfully moved to: {destination_path}")
            
            # Remove backup if move was successful
            if backup_path and backup_path.exists():
                backup_path.unlink()
                logger.info(f"Removed backup: {backup_path}")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to move file: {e}")
            
            # Restore backup if it exists
            if backup_path and backup_path.exists():
                try:
                    shutil.move(str(backup_path), str(destination_path))
                    logger.info(f"Restored backup: {destination_path}")
                except Exception as restore_e:
                    logger.error(f"Failed to restore backup: {restore_e}")
            
            return False

    def cleanup_temp_file(self, temp_path: Path) -> None:
        """Clean up temporary file."""
        try:
            if temp_path.exists():
                temp_path.unlink()
                logger.info(f"Cleaned up temp file: {temp_path}")
        except Exception as e:
            logger.warning(f"Failed to cleanup temp file {temp_path}: {e}")

    def process_download(self, temp_path: Path, filename: str, model_type: str,
                        expected_size: Optional[int] = None, expected_hash: Optional[str] = None) -> bool:
        """
        Complete atomic file processing: verify -> move -> cleanup
        Returns True if successful, False otherwise.
        """
        try:
            # Step 1: Verify the downloaded file
            if not self.verify_file(temp_path, expected_size, expected_hash):
                self.cleanup_temp_file(temp_path)
                return False
            
            # Step 2: Determine destination
            destination_path = self.get_destination_path(filename, model_type)
            
            # Step 3: Atomic move to final location
            if not self.atomic_move(temp_path, destination_path):
                self.cleanup_temp_file(temp_path)
                return False
            
            # Step 4: Final verification at destination
            if not destination_path.exists():
                logger.error(f"File missing after move: {destination_path}")
                return False
            
            logger.info(f"Successfully processed: {destination_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error processing download: {e}")
            self.cleanup_temp_file(temp_path)
            return False

# Global instance for easy access
file_handler = AtomicFileHandler()