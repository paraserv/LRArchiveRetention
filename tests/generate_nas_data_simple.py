#!/usr/bin/env python3
"""
Simpler sequential version of NAS data generator with better progress reporting.
"""

import os
import sys
import random
import datetime
import time
import subprocess
from pathlib import Path


def get_nas_password():
    """Get NAS password from keychain."""
    try:
        cmd = ['security', 'find-internet-password', '-s', '10.20.1.7', '-a', 'sanghanas', '-w']
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except:
        print("Error: Could not get NAS password from keychain")
        sys.exit(1)


def main():
    # Parameters
    target_gb = 3072  # 3TB
    avg_file_size_mb = 25  # Average of 50MB max
    files_per_folder = 75  # Average of 50-100
    
    # Calculate how many folders we need
    total_files_needed = int((target_gb * 1024) / avg_file_size_mb)
    folders_needed = int(total_files_needed / files_per_folder)
    
    print(f"Target: {target_gb} GB")
    print(f"Estimated folders: {folders_needed}")
    print(f"Estimated files: {total_files_needed}")
    print()
    
    # Mount check
    root_path = "/Volumes/LRArchives/TestData"
    if not os.path.exists("/Volumes/LRArchives"):
        print("Mounting NAS...")
        password = get_nas_password()
        smb_url = f'smb://sanghanas:{password}@10.20.1.7/LRArchives'
        subprocess.run(['open', smb_url], capture_output=True)
        time.sleep(3)
    
    # Create root
    os.makedirs(root_path, exist_ok=True)
    
    # Generate buffer for file content
    print("Generating data buffer...")
    buffer = bytearray(1024 * 1024)  # 1MB buffer
    for i in range(len(buffer)):
        buffer[i] = i % 256
    
    # Start generation
    start_time = time.time()
    total_bytes = 0
    total_files = 0
    
    print("\nStarting generation...")
    print("Progress will be shown every 10 folders\n")
    
    for folder_num in range(folders_needed):
        # Generate folder date
        days_back = random.randint(0, 1095)
        folder_date = datetime.datetime.now() - datetime.timedelta(days=days_back)
        date_str = folder_date.strftime("%Y%m%d")
        ticks = int(folder_date.timestamp() * 10000000) + 621355968000000000
        folder_name = f"{date_str}_1_1_1_{ticks}"
        folder_path = os.path.join(root_path, folder_name)
        
        # Create folder
        os.makedirs(folder_path, exist_ok=True)
        
        # Create files
        num_files = random.randint(50, 100)
        for file_num in range(num_files):
            # Generate file metadata
            file_date = folder_date + datetime.timedelta(
                days=random.randint(-5, 5),
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59)
            )
            time_str = file_date.strftime("%H%M%S")
            random_num = random.randint(1000, 9999)
            file_name = f"{date_str}_{time_str}_{random_num}.lca"
            file_path = os.path.join(folder_path, file_name)
            
            # Write file
            file_size = random.randint(20, 50) * 1024 * 1024  # 20-50 MB
            with open(file_path, 'wb') as f:
                bytes_written = 0
                while bytes_written < file_size:
                    chunk_size = min(len(buffer), file_size - bytes_written)
                    f.write(buffer[:chunk_size])
                    bytes_written += chunk_size
            
            # Set timestamp
            timestamp = file_date.timestamp()
            os.utime(file_path, (timestamp, timestamp))
            
            total_bytes += file_size
            total_files += 1
        
        # Progress report every 10 folders
        if (folder_num + 1) % 10 == 0 or folder_num == 0:
            elapsed = time.time() - start_time
            gb_written = total_bytes / (1024**3)
            rate_mb = (total_bytes / (1024**2)) / elapsed if elapsed > 0 else 0
            percent = (folder_num + 1) / folders_needed * 100
            
            # ETA calculation
            if folder_num > 0 and elapsed > 0:
                folders_per_sec = (folder_num + 1) / elapsed
                remaining_folders = folders_needed - (folder_num + 1)
                eta_seconds = remaining_folders / folders_per_sec
                eta_str = str(datetime.timedelta(seconds=int(eta_seconds)))
            else:
                eta_str = "calculating..."
            
            print(f"Progress: {percent:.1f}% | "
                  f"Folders: {folder_num + 1}/{folders_needed} | "
                  f"Files: {total_files} | "
                  f"Data: {gb_written:.2f} GB | "
                  f"Rate: {rate_mb:.1f} MB/s | "
                  f"ETA: {eta_str}")
    
    # Final report
    elapsed = time.time() - start_time
    gb_written = total_bytes / (1024**3)
    rate_mb = (total_bytes / (1024**2)) / elapsed
    
    print("\n" + "="*50)
    print("GENERATION COMPLETE")
    print(f"Total folders: {folders_needed}")
    print(f"Total files: {total_files}")
    print(f"Total data: {gb_written:.2f} GB")
    print(f"Total time: {str(datetime.timedelta(seconds=int(elapsed)))}")
    print(f"Average rate: {rate_mb:.1f} MB/s")
    print(f"Location: {root_path}")


if __name__ == "__main__":
    main()