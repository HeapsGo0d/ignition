#!/usr/bin/env python3
"""
CivitAI model downloader with parallel processing.
Supports models, LoRAs, and VAEs specified by version IDs.
"""

import sys
import asyncio
import aiohttp
import aiofiles
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple

from file_utils import file_handler

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class CivitAIDownloader:
    """Handles downloading models from CivitAI with parallel processing."""
    
    def __init__(self, api_token: Optional[str] = None):
        self.api_token = api_token
        self.base_url = "https://civitai.com/api/v1"
        self.session = None
        self.concurrent_downloads = 3  # Limit concurrent downloads to be respectful
        
    async def __aenter__(self):
        """Async context manager entry."""
        headers = {}
        if self.api_token:
            headers['Authorization'] = f'Bearer {self.api_token}'
        
        connector = aiohttp.TCPConnector(limit=10, limit_per_host=5)
        self.session = aiohttp.ClientSession(
            connector=connector,
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=3600)  # 1 hour timeout for large files
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def get_model_info(self, version_id: str) -> Optional[Dict]:
        """Get model information from CivitAI API."""
        try:
            url = f"{self.base_url}/model-versions/{version_id}"
            logger.info(f"Fetching model info for version ID: {version_id}")
            
            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info(f"Successfully fetched info for: {data.get('model', {}).get('name', 'Unknown')}")
                    return data
                elif response.status == 404:
                    logger.error(f"Model version not found: {version_id}")
                    return None
                else:
                    logger.error(f"API error {response.status} for version {version_id}")
                    return None
                    
        except Exception as e:
            logger.error(f"Error fetching model info for {version_id}: {e}")
            return None

    def determine_model_type(self, model_info: Dict) -> str:
        """Determine the model type from CivitAI model information."""
        model_data = model_info.get('model', {})
        model_type = model_data.get('type', '').lower()
        
        # Map CivitAI types to our internal types
        type_mapping = {
            'checkpoint': 'checkpoint',
            'textualinversion': 'embedding',
            'hypernetwork': 'embedding',
            'lora': 'lora',
            'locon': 'lora',
            'vae': 'vae',
            'controlnet': 'controlnet',
            'upscaler': 'upscaler',
        }
        
        mapped_type = type_mapping.get(model_type, 'checkpoint')
        logger.info(f"Model type '{model_type}' mapped to '{mapped_type}'")
        return mapped_type

    def get_download_file(self, model_info: Dict) -> Optional[Dict]:
        """Get the primary download file from model info."""
        files = model_info.get('files', [])
        
        # Look for the primary file (usually the first one)
        for file_info in files:
            if file_info.get('primary', False) or len(files) == 1:
                return file_info
        
        # If no primary file found, use the first one
        if files:
            return files[0]
        
        return None

    async def download_file(self, url: str, temp_path: Path, filename: str, 
                          expected_size: Optional[int] = None) -> bool:
        """Download a file with progress tracking."""
        try:
            logger.info(f"Starting download: {filename}")
            
            async with self.session.get(url) as response:
                if response.status != 200:
                    logger.error(f"Download failed with status {response.status}: {filename}")
                    return False
                
                total_size = expected_size or int(response.headers.get('content-length', 0))
                downloaded_size = 0
                last_logged = 0
                log_interval = 100 * 1024 * 1024  # 100MB

                async with aiofiles.open(temp_path, 'wb') as file:
                    async for chunk in response.content.iter_chunked(8192):
                        await file.write(chunk)
                        downloaded_size += len(chunk)

                        # Log progress roughly every 100MB downloaded
                        if downloaded_size - last_logged >= log_interval:
                            if total_size > 0:
                                progress = (downloaded_size / total_size) * 100
                                logger.info(
                                    f"Progress {filename}: {progress:.1f}% ({downloaded_size / 1024 / 1024:.1f}MB)"
                                )
                            else:
                                logger.info(
                                    f"Downloaded {filename}: {downloaded_size / 1024 / 1024:.1f}MB"
                                )
                            last_logged = downloaded_size
                
                logger.info(f"Download complete: {filename} ({downloaded_size / 1024 / 1024:.1f}MB)")
                return True
                
        except Exception as e:
            logger.error(f"Error downloading {filename}: {e}")
            return False

    async def process_model(self, version_id: str, max_retries: int = 2) -> bool:
        """Process a single model download with retry logic."""
        try:
            # Get model information
            model_info = await self.get_model_info(version_id)
            if not model_info:
                return False
            
            # Get download file info
            file_info = self.get_download_file(model_info)
            if not file_info:
                logger.error(f"No download file found for version {version_id}")
                return False
            
            filename = file_info.get('name')
            download_url = file_info.get('downloadUrl')
            file_size = file_info.get('sizeKB', 0) * 1024  # Convert KB to bytes
            file_hash = file_info.get('hashes', {}).get('SHA256')
            
            if not filename or not download_url:
                logger.error(f"Missing filename or download URL for version {version_id}")
                return False
            
            # Determine model type and destination
            model_type = self.determine_model_type(model_info)
            destination_path = file_handler.get_destination_path(filename, model_type)
            
            # Check if file already exists and is valid (RunPod volume persistence)
            if destination_path.exists() and file_handler.file_exists_and_valid(destination_path, file_size):
                logger.info(f"File already exists and is valid: {filename}")
                return True
            
            # Retry logic for download and processing
            for attempt in range(max_retries + 1):
                try:
                    if attempt > 0:
                        logger.info(f"Retry attempt {attempt} for {filename}")
                        await asyncio.sleep(2 ** attempt)  # Exponential backoff
                    
                    # Download to temporary location
                    temp_path = file_handler.get_temp_path(filename)
                    
                    if not await self.download_file(download_url, temp_path, filename, file_size):
                        if attempt == max_retries:
                            return False
                        continue
                    
                    # Process the download atomically
                    success = file_handler.process_download(
                        temp_path, filename, model_type, file_size, file_hash
                    )
                    
                    if success:
                        logger.info(f"Successfully processed model: {filename}")
                        return True
                    elif attempt == max_retries:
                        logger.error(f"Failed to process model after {max_retries + 1} attempts: {filename}")
                        return False
                    else:
                        logger.warning(f"Processing failed for {filename}, retrying...")
                        
                except Exception as e:
                    if attempt == max_retries:
                        logger.error(f"Final attempt failed for {filename}: {e}")
                        return False
                    else:
                        logger.warning(f"Attempt {attempt + 1} failed for {filename}: {e}")
            
            return False
            
        except Exception as e:
            logger.error(f"Error processing model {version_id}: {e}")
            return False

    async def download_models(self, model_ids: List[str]) -> Tuple[int, int]:
        """Download multiple models with controlled concurrency."""
        if not model_ids:
            logger.info("No CivitAI models to download")
            return 0, 0
        
        logger.info(f"Starting download of {len(model_ids)} CivitAI models")
        
        # Create semaphore to limit concurrent downloads
        semaphore = asyncio.Semaphore(self.concurrent_downloads)
        
        async def download_with_semaphore(version_id: str) -> bool:
            async with semaphore:
                return await self.process_model(version_id)
        
        # Execute downloads with limited concurrency
        results = await asyncio.gather(
            *[download_with_semaphore(model_id.strip()) for model_id in model_ids],
            return_exceptions=True
        )
        
        # Count successes and failures
        successful = sum(1 for result in results if result is True)
        failed = len(results) - successful
        
        logger.info(f"CivitAI downloads complete: {successful} successful, {failed} failed")
        return successful, failed


async def main():
    """Main function for standalone execution."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Download models from CivitAI')
    parser.add_argument('--models', required=True, help='Comma-separated list of model version IDs')
    parser.add_argument('--token', help='CivitAI API token')
    args = parser.parse_args()
    
    model_ids = [mid.strip() for mid in args.models.split(',') if mid.strip()]
    
    if not model_ids:
        logger.error("No model IDs provided")
        return 1
    
    async with CivitAIDownloader(args.token) as downloader:
        successful, failed = await downloader.download_models(model_ids)
        
        if failed > 0:
            logger.error(f"Some downloads failed: {failed} out of {len(model_ids)}")
            return 1
        
        logger.info("All downloads completed successfully")
        return 0


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))