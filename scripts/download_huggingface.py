#!/usr/bin/env python3
"""
HuggingFace model downloader for Flux and other models.
Supports downloading from HuggingFace repositories.
"""

import sys
import asyncio
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from huggingface_hub import hf_hub_download, list_repo_files, repo_info
from huggingface_hub.utils import RepositoryNotFoundError, RevisionNotFoundError

from file_utils import file_handler

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class HuggingFaceDownloader:
    """Handles downloading models from HuggingFace."""
    
    def __init__(self, token: Optional[str] = None):
        self.token = token
        
        # File extensions to download for different model types
        self.model_extensions = {
            '.safetensors', '.bin', '.pt', '.pth', '.ckpt', 
            '.json', '.txt', '.yaml', '.yml'
        }
        
        # Files to skip (too large or unnecessary for ComfyUI)
        self.skip_files = {
            'README.md', '.gitattributes', '.gitignore',
            'model_index.json'  # Skip if it's just metadata
        }

    def determine_model_type(self, repo_id: str, filename: str) -> str:
        """Determine model type based on repository and filename."""
        repo_lower = repo_id.lower()
        filename_lower = filename.lower()
        
        # Check for specific model types based on repo name or filename
        if 'flux' in repo_lower or 'flux' in filename_lower:
            return 'checkpoint'
        elif 'lora' in repo_lower or 'lora' in filename_lower:
            return 'lora'
        elif 'vae' in repo_lower or 'vae' in filename_lower:
            return 'vae'
        elif 'controlnet' in repo_lower or 'controlnet' in filename_lower:
            return 'controlnet'
        elif 'embedding' in repo_lower or 'textual' in repo_lower:
            return 'embedding'
        else:
            # Default to checkpoint for safetensors/bin files, embedding for others
            if filename_lower.endswith(('.safetensors', '.bin', '.pt', '.pth', '.ckpt')):
                return 'checkpoint'
            else:
                return 'embedding'

    def should_download_file(self, filename: str, file_size: Optional[int] = None) -> bool:
        """Determine if a file should be downloaded."""
        # Skip files in the skip list
        if filename in self.skip_files:
            return False
        
        # Only download files with relevant extensions
        file_ext = Path(filename).suffix.lower()
        if file_ext not in self.model_extensions:
            return False
        
        # Skip very small files that are likely metadata
        if file_size is not None and file_size < 1024:  # Less than 1KB
            return False
        
        return True

    def download_single_file(self, repo_id: str, filename: str) -> bool:
        """Download a single file from HuggingFace repository."""
        try:
            logger.info(f"Processing file: {filename} from {repo_id}")
            
            # Determine model type and destination
            model_type = self.determine_model_type(repo_id, filename)
            destination_path = file_handler.get_destination_path(filename, model_type)
            
            # Check if file already exists and is valid (RunPod volume persistence)
            if destination_path.exists():
                logger.info(f"File already exists: {filename}")
                return True
            
            # Create temporary path
            temp_path = file_handler.get_temp_path(filename)
            
            # Download file using HuggingFace Hub
            try:
                downloaded_path = hf_hub_download(
                    repo_id=repo_id,
                    filename=filename,
                    token=self.token,
                    local_dir=str(temp_path.parent)
                )
                
                # The downloaded file might be in a subdirectory structure
                actual_temp_path = Path(downloaded_path)
                
                # If the file wasn't downloaded to our expected temp path, move it
                if actual_temp_path != temp_path:
                    actual_temp_path.rename(temp_path)
                
            except Exception as e:
                logger.error(f"HuggingFace download failed for {filename}: {e}")
                return False
            
            # Verify download
            if not temp_path.exists() or temp_path.stat().st_size == 0:
                logger.error(f"Downloaded file is missing or empty: {filename}")
                return False
            
            # Process the download atomically
            success = file_handler.process_download(temp_path, filename, model_type)
            
            if success:
                logger.info(f"Successfully processed: {filename}")
            else:
                logger.error(f"Failed to process: {filename}")
                
            return success
            
        except Exception as e:
            logger.error(f"Error downloading {filename} from {repo_id}: {e}")
            return False

    async def get_repo_files(self, repo_id: str) -> List[Dict]:
        """Get list of files in repository with their sizes."""
        try:
            logger.info(f"Fetching file list for repository: {repo_id}")
            info = repo_info(repo_id, token=self.token)
            files = list_repo_files(repo_id, token=self.token)

            file_info: List[Dict] = []
            for filename in files:
                file_data = {"filename": filename, "size": None}
                for sibling in info.siblings:
                    if sibling.rfilename == filename:
                        file_data["size"] = sibling.size
                        break
                file_info.append(file_data)

            files_to_download = []
            for file_data in file_info:
                if self.should_download_file(file_data["filename"], file_data["size"]):
                    files_to_download.append(file_data)

            logger.info(f"Found {len(files_to_download)} files to download from {repo_id}")
            return files_to_download
        except RepositoryNotFoundError:
            logger.error(f"Repository not found: {repo_id}")
            return []
        except RevisionNotFoundError:
            logger.error(f"Repository revision not found: {repo_id}")
            return []
        except Exception as e:
            logger.error(f"Error accessing repository {repo_id}: {e}")
            return []

    async def download_repository(self, repo_id: str) -> Tuple[int, int]:
        """Download all relevant files from a HuggingFace repository."""
        try:
            # Get list of files to download
            files_info = await self.get_repo_files(repo_id)

            if not files_info:
                logger.warning(f"No files found to download from {repo_id}")
                return 0, 1

            logger.info(f"Downloading {len(files_info)} files from {repo_id}")

            successful = 0
            failed = 0
            for file_info in files_info:
                if self.download_single_file(repo_id, file_info["filename"]):
                    successful += 1
                else:
                    failed += 1

            logger.info(f"Repository {repo_id} downloads complete: {successful} successful, {failed} failed")
            return successful, failed
        except Exception as e:
            logger.error(f"Error downloading repository {repo_id}: {e}")
            return 0, 1

    async def download_models(self, repo_ids: List[str]) -> Tuple[int, int]:
        """Download models from multiple HuggingFace repositories."""
        if not repo_ids:
            logger.info("No HuggingFace models to download")
            return 0, 0
        
        logger.info(f"Starting download from {len(repo_ids)} HuggingFace repositories")
        
        total_successful = 0
        total_failed = 0
        
        # Process repositories sequentially to avoid overwhelming HF servers
        for repo_id in repo_ids:
            repo_id = repo_id.strip()
            if not repo_id:
                continue
                
            successful, failed = await self.download_repository(repo_id)
            total_successful += successful
            total_failed += failed
        
        logger.info(f"HuggingFace downloads complete: {total_successful} successful, {total_failed} failed")
        return total_successful, total_failed


async def main():
    """Main function for standalone execution."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Download models from HuggingFace')
    parser.add_argument('--repos', required=True, help='Comma-separated list of repository IDs')
    parser.add_argument('--token', help='HuggingFace API token')
    args = parser.parse_args()
    
    repo_ids = [repo.strip() for repo in args.repos.split(',') if repo.strip()]
    
    if not repo_ids:
        logger.error("No repository IDs provided")
        return 1
    
    downloader = HuggingFaceDownloader(args.token)
    successful, failed = await downloader.download_models(repo_ids)
    
    if failed > 0:
        logger.error(f"Some downloads failed: {failed} files")
        return 1
    
    logger.info("All downloads completed successfully")
    return 0


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))
