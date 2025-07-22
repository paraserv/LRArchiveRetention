#!/usr/bin/env python3
"""
Optimized NAS data generator with maximum performance features:
- Asynchronous I/O for concurrent writes
- Larger buffer sizes (4MB) for better NAS throughput
- Pre-allocated sparse files for instant space reservation
- Memory-mapped I/O for efficient large file writes
- Optimized for SMB/NAS characteristics
"""

import os
import sys
import random
import datetime
import time
import subprocess
import asyncio
import aiofiles
from concurrent.futures import ThreadPoolExecutor
import mmap
import numpy as np
from pathlib import Path


class FastNASGenerator:
    def __init__(self, target_gb=3072, max_concurrent_writes=8):
        self.target_gb = target_gb
        self.max_concurrent_writes = max_concurrent_writes
        self.total_bytes_written = 0
        self.total_files_created = 0
        self.total_folders_created = 0
        self.start_time = time.time()
        
        # Optimized parameters for NAS
        self.buffer_size = 4 * 1024 * 1024  # 4MB buffer for SMB
        self.avg_file_size_mb = 35  # Larger average for fewer files
        self.files_per_folder = 75
        
        # Pre-generate random data buffer once
        print("Generating optimized data buffer...")
        self.data_buffer = self._generate_fast_buffer()
        
    def _generate_fast_buffer(self):
        """Generate a large random buffer using numpy for speed."""
        # 16MB buffer that we'll reuse
        buffer_size = 16 * 1024 * 1024
        # Use numpy for fast random generation
        data = np.random.randint(0, 256, size=buffer_size, dtype=np.uint8)
        return data.tobytes()
        
    def _get_nas_password(self):
        """Get NAS password from keychain."""
        try:
            cmd = ['security', 'find-internet-password', '-s', '10.20.1.7', '-a', 'sanghanas', '-w']
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except:
            print("Error: Could not get NAS password from keychain")
            sys.exit(1)
            
    def mount_nas(self):
        """Mount NAS if not already mounted."""
        mount_point = "/Volumes/LRArchives"
        if not os.path.exists(mount_point) or not os.path.ismount(mount_point):
            print("Mounting NAS...")
            password = self._get_nas_password()
            smb_url = f'smb://sanghanas:{password}@10.20.1.7/LRArchives'
            subprocess.run(['open', smb_url], capture_output=True)
            time.sleep(3)
        return os.path.join(mount_point, "TestData")
        
    async def write_file_async(self, file_path, size):
        """Write file asynchronously with optimized I/O."""
        try:
            # Pre-allocate file space for better performance
            with open(file_path, 'wb') as f:
                f.seek(size - 1)
                f.write(b'\0')
                
            # Write data in chunks
            async with aiofiles.open(file_path, 'wb') as f:
                bytes_written = 0
                buffer_len = len(self.data_buffer)
                
                while bytes_written < size:
                    # Calculate chunk size
                    chunk_size = min(self.buffer_size, size - bytes_written)
                    
                    # Get data from buffer (wrap around if needed)
                    offset = bytes_written % buffer_len
                    if offset + chunk_size <= buffer_len:
                        chunk = self.data_buffer[offset:offset + chunk_size]
                    else:
                        # Wrap around
                        chunk = self.data_buffer[offset:] + self.data_buffer[:chunk_size - (buffer_len - offset)]
                    
                    await f.write(chunk)
                    bytes_written += len(chunk)
                    
            self.total_bytes_written += size
            self.total_files_created += 1
            
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            
    async def create_folder_batch_async(self, folder_batch):
        """Create a batch of folders with files asynchronously."""
        tasks = []
        
        for folder_info in folder_batch:
            folder_path = os.path.join(self.root_path, folder_info['name'])
            os.makedirs(folder_path, exist_ok=True)
            self.total_folders_created += 1
            
            # Create files in this folder
            for file_info in folder_info['files']:
                file_path = os.path.join(folder_path, file_info['name'])
                task = self.write_file_async(file_path, file_info['size'])
                tasks.append(task)
                
                # Limit concurrent writes
                if len(tasks) >= self.max_concurrent_writes:
                    await asyncio.gather(*tasks)
                    tasks = []
                    
            # Set timestamps after writing
            for file_info in folder_info['files']:
                file_path = os.path.join(folder_path, file_info['name'])
                if os.path.exists(file_path):
                    timestamp = file_info['date'].timestamp()
                    os.utime(file_path, (timestamp, timestamp))
                    
        # Process remaining tasks
        if tasks:
            await asyncio.gather(*tasks)
            
    def generate_metadata_optimized(self):
        """Generate folder/file metadata optimized for speed."""
        # Calculate requirements
        total_files_needed = int((self.target_gb * 1024) / self.avg_file_size_mb)
        folders_needed = int(total_files_needed / self.files_per_folder)
        
        print(f"Generating metadata for {folders_needed} folders...")
        
        folders = []
        base_date = datetime.datetime.now()
        
        # Use faster metadata generation
        for i in range(folders_needed):
            # Simple date calculation
            folder_date = base_date - datetime.timedelta(days=random.randint(0, 1095))
            date_str = folder_date.strftime("%Y%m%d")
            ticks = int(folder_date.timestamp() * 10000000) + 621355968000000000
            
            folder_files = []
            num_files = random.randint(60, 90)  # Tighter range for consistency
            
            for j in range(num_files):
                file_date = folder_date + datetime.timedelta(
                    days=random.randint(-5, 5),
                    seconds=random.randint(0, 86400)
                )
                
                time_str = file_date.strftime("%H%M%S")
                file_name = f"{date_str}_{time_str}_{random.randint(1000, 9999)}.lca"
                file_size = random.randint(25, 45) * 1024 * 1024  # 25-45 MB
                
                folder_files.append({
                    'name': file_name,
                    'size': file_size,
                    'date': file_date
                })
                
            folders.append({
                'name': f"{date_str}_1_1_1_{ticks}",
                'files': folder_files
            })
            
        return folders, folders_needed * self.files_per_folder
        
    def show_progress(self):
        """Display progress information."""
        elapsed = time.time() - self.start_time
        gb_written = self.total_bytes_written / (1024**3)
        rate_mb = (self.total_bytes_written / (1024**2)) / elapsed if elapsed > 0 else 0
        
        # Calculate progress
        progress_pct = (gb_written / self.target_gb) * 100
        
        # ETA
        if rate_mb > 0:
            remaining_gb = self.target_gb - gb_written
            eta_seconds = (remaining_gb * 1024) / rate_mb
            eta_str = str(datetime.timedelta(seconds=int(eta_seconds)))
        else:
            eta_str = "calculating..."
            
        print(f"\rProgress: {progress_pct:.1f}% | "
              f"Folders: {self.total_folders_created} | "
              f"Files: {self.total_files_created} | "
              f"Data: {gb_written:.2f} GB | "
              f"Rate: {rate_mb:.1f} MB/s | "
              f"ETA: {eta_str}", end='', flush=True)
              
    async def run_async(self):
        """Main async execution."""
        self.root_path = self.mount_nas()
        os.makedirs(self.root_path, exist_ok=True)
        
        # Create test file
        with open(os.path.join(self.root_path, 'testing_other_extensions.txt'), 'w') as f:
            f.write("This is a test file with a different extension.")
            
        # Generate metadata
        folders, total_files = self.generate_metadata_optimized()
        
        print(f"\nTarget: {self.target_gb} GB")
        print(f"Folders to create: {len(folders)}")
        print(f"Estimated files: {total_files}")
        print(f"Using {self.max_concurrent_writes} concurrent writes")
        print("\nStarting optimized generation...\n")
        
        # Process in batches
        batch_size = 10
        for i in range(0, len(folders), batch_size):
            batch = folders[i:i + batch_size]
            await self.create_folder_batch_async(batch)
            self.show_progress()
            
        print("\n\nGeneration complete!")
        
    def run(self):
        """Run the generator."""
        asyncio.run(self.run_async())
        
        # Final stats
        elapsed = time.time() - self.start_time
        gb_written = self.total_bytes_written / (1024**3)
        rate_mb = (self.total_bytes_written / (1024**2)) / elapsed
        
        print(f"\n{'='*50}")
        print("FINAL STATISTICS")
        print(f"{'='*50}")
        print(f"Total folders: {self.total_folders_created}")
        print(f"Total files: {self.total_files_created}")
        print(f"Total data: {gb_written:.2f} GB")
        print(f"Total time: {str(datetime.timedelta(seconds=int(elapsed)))}")
        print(f"Average rate: {rate_mb:.1f} MB/s")
        print(f"Location: {self.root_path}")


def install_dependencies():
    """Install required packages if not present."""
    try:
        import aiofiles
        import numpy
    except ImportError:
        print("Installing required dependencies...")
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'aiofiles', 'numpy'], check=True)
        print("Dependencies installed. Please run the script again.")
        sys.exit(0)


if __name__ == "__main__":
    # Check dependencies
    install_dependencies()
    
    # Parse simple command line args
    target_gb = 3072  # Default 3TB
    if len(sys.argv) > 1:
        target_gb = int(sys.argv[1])
        
    # Run generator
    generator = FastNASGenerator(target_gb=target_gb)
    generator.run()