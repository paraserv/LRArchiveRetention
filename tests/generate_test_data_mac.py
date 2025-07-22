#!/usr/bin/env python3
"""
Generate test data for LogRhythm Archive Retention testing from macOS.
Creates date-based folders with .lca files matching LogRhythm archive format.
Optimized for high-performance parallel generation over network shares.
"""

import os
import sys
import random
import datetime
import argparse
import time
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
import math

# Global counters for thread-safe progress tracking
progress_lock = Lock()
total_bytes_generated = 0
processed_folders = 0
processed_files = 0
last_progress_update = time.time()


def get_nas_credentials():
    """Retrieve NAS credentials from macOS keychain."""
    try:
        # Get username
        username_cmd = ['security', 'find-internet-password', '-s', '10.20.1.7', '-a', 'sanghanas']
        username_result = subprocess.run(username_cmd, capture_output=True, text=True, check=True)
        
        # Get password
        password_cmd = ['security', 'find-internet-password', '-s', '10.20.1.7', '-a', 'sanghanas', '-w']
        password_result = subprocess.run(password_cmd, capture_output=True, text=True, check=True)
        
        return 'sanghanas', password_result.stdout.strip()
    except subprocess.CalledProcessError:
        print("Error: Could not retrieve NAS credentials from keychain")
        print("Please ensure credentials are stored with:")
        print("  security add-internet-password -s '10.20.1.7' -a 'sanghanas' -w")
        sys.exit(1)


def mount_nas_share(mount_point='/Volumes/LRArchives'):
    """Mount NAS share using credentials from keychain."""
    username, password = get_nas_credentials()
    
    # Check if already mounted
    if os.path.exists(mount_point) and os.path.ismount(mount_point):
        print(f"NAS share already mounted at {mount_point}")
        return mount_point
    
    # Mount the share using open command (macOS way)
    smb_url = f'smb://sanghanas:{password}@10.20.1.7/LRArchives'
    
    try:
        # Open the SMB share which will mount it
        subprocess.run(['open', smb_url], capture_output=True, text=True, check=True)
        
        # Wait a moment for mount to complete
        time.sleep(2)
        
        # The share should now be mounted at /Volumes/LRArchives
        if os.path.exists(mount_point):
            print(f"Successfully mounted NAS share at {mount_point}")
            return mount_point
        else:
            print("Error: Mount point not found after mounting")
            sys.exit(1)
            
    except subprocess.CalledProcessError as e:
        print(f"Error mounting NAS share: {e}")
        sys.exit(1)


def show_progress(folder_count, total_folders, file_count, total_files, force=False):
    """Display detailed progress information."""
    global last_progress_update, total_bytes_generated
    
    current_time = time.time()
    elapsed_since_update = current_time - last_progress_update
    
    if not force and elapsed_since_update < args.progress_interval:
        return
    
    elapsed_total = current_time - start_time
    percent_complete = (folder_count / total_folders) * 100 if total_folders > 0 else 0
    
    # Calculate rates
    folders_per_sec = folder_count / elapsed_total if elapsed_total > 0 else 0
    files_per_sec = file_count / elapsed_total if elapsed_total > 0 else 0
    data_rate_mb = (total_bytes_generated / 1024 / 1024) / elapsed_total if elapsed_total > 0 else 0
    data_size_gb = total_bytes_generated / 1024 / 1024 / 1024
    
    # Calculate ETA
    if folders_per_sec > 0 and folder_count > 0:
        remaining_folders = total_folders - folder_count
        eta_seconds = remaining_folders / folders_per_sec
        eta_str = str(datetime.timedelta(seconds=int(eta_seconds)))
    else:
        eta_str = "Calculating..."
    
    print(f"\n{'='*50}")
    print(f"PROGRESS: {percent_complete:.1f}% complete")
    print(f"Folders: {folder_count}/{total_folders}")
    print(f"Files: {file_count} (estimated total: {total_files})")
    print(f"Data generated: {data_size_gb:.2f} GB")
    print(f"Performance: {folders_per_sec:.2f} folders/sec, {files_per_sec:.0f} files/sec")
    print(f"Data rate: {data_rate_mb:.2f} MB/sec")
    print(f"Elapsed: {str(datetime.timedelta(seconds=int(elapsed_total)))}")
    print(f"ETA: {eta_str}")
    print(f"{'='*50}\n")
    
    last_progress_update = current_time


def generate_folder_data(folder_count, min_files, max_files, max_file_size_mb):
    """Pre-generate all folder and file metadata."""
    print("Pre-generating folder and file metadata...")
    
    base_date = datetime.datetime.now()
    start_date = base_date - datetime.timedelta(days=1095)  # 3 years back
    
    all_folders = []
    total_estimated_files = 0
    
    for i in range(folder_count):
        # Random date within the last 3 years
        days_offset = random.randint(0, 1095)
        folder_date = start_date + datetime.timedelta(days=days_offset)
        
        date_str = folder_date.strftime("%Y%m%d")
        ticks = int(folder_date.timestamp() * 10000000) + 621355968000000000  # .NET ticks
        folder_name = f"{date_str}_1_1_1_{ticks}"
        
        # Generate file metadata for this folder
        file_count = random.randint(min_files, max_files)
        total_estimated_files += file_count
        
        files = []
        for f in range(file_count):
            # File date within ±5 days of folder date
            file_date_offset = random.randint(-5, 5)
            file_date = folder_date + datetime.timedelta(days=file_date_offset)
            file_date = file_date.replace(
                hour=random.randint(0, 23),
                minute=random.randint(0, 59),
                second=random.randint(0, 59)
            )
            
            time_str = file_date.strftime("%H%M%S")
            random_num = random.randint(1000, 9999)
            file_name = f"{date_str}_{time_str}_{random_num}.lca"
            
            # File size between 20KB and max_file_size_mb
            file_size = random.randint(20 * 1024, max_file_size_mb * 1024 * 1024)
            
            files.append({
                'name': file_name,
                'size': file_size,
                'date': file_date
            })
        
        all_folders.append({
            'name': folder_name,
            'date': folder_date,
            'files': files
        })
    
    return all_folders, total_estimated_files


def create_folder_with_files(folder_data, root_path, buffer_patterns):
    """Create a single folder with all its files."""
    global total_bytes_generated, processed_folders, processed_files
    
    folder_path = os.path.join(root_path, folder_data['name'])
    
    try:
        # Create folder
        os.makedirs(folder_path, exist_ok=True)
        
        # Add small delay for network shares
        time.sleep(0.01)
        
        folder_bytes = 0
        folder_files = 0
        
        # Create files
        for file_data in folder_data['files']:
            file_path = os.path.join(folder_path, file_data['name'])
            
            try:
                # Write file with pattern data
                with open(file_path, 'wb') as f:
                    bytes_written = 0
                    file_size = file_data['size']
                    pattern_index = hash(folder_data['name']) % len(buffer_patterns)
                    buffer = buffer_patterns[pattern_index]
                    
                    while bytes_written < file_size:
                        write_size = min(len(buffer), file_size - bytes_written)
                        f.write(buffer[:write_size])
                        bytes_written += write_size
                
                # Set file timestamps
                timestamp = file_data['date'].timestamp()
                os.utime(file_path, (timestamp, timestamp))
                
                folder_bytes += file_size
                folder_files += 1
                
            except Exception as e:
                print(f"Warning: Failed to create file {file_data['name']}: {e}")
        
        # Update global counters (thread-safe)
        with progress_lock:
            total_bytes_generated += folder_bytes
            processed_folders += 1
            processed_files += folder_files
        
        return folder_bytes, folder_files
        
    except Exception as e:
        print(f"Error creating folder {folder_data['name']}: {e}")
        return 0, 0


def auto_scale_parameters(folder_count, min_files, max_files, max_file_size_mb, max_size_gb):
    """Auto-scale parameters to fit within size limit."""
    avg_files_per_folder = (min_files + max_files) / 2
    avg_file_size = (max_file_size_mb * 1024 * 1024) / 2
    estimated_total_files = folder_count * avg_files_per_folder
    estimated_total_bytes = estimated_total_files * avg_file_size
    
    # Add 5% safety margin
    safety_margin = 0.05
    required_space_gb = (estimated_total_bytes * (1 + safety_margin)) / 1024 / 1024 / 1024
    
    if required_space_gb <= max_size_gb:
        return folder_count, max_files  # No scaling needed
    
    print(f"\nRequested size ({required_space_gb:.2f} GB) exceeds limit ({max_size_gb} GB)")
    print("Auto-scaling parameters...")
    
    # Calculate how many files we can actually generate
    max_bytes = max_size_gb * 1024 * 1024 * 1024
    total_files_allowed = int(max_bytes / (avg_file_size * (1 + safety_margin)))
    
    # Try to maintain file range by reducing folder count
    ideal_folder_count = int(total_files_allowed / avg_files_per_folder)
    
    if ideal_folder_count >= 1:
        new_folder_count = min(ideal_folder_count, folder_count)
        new_max_files = max_files
    else:
        # Need to reduce both folders and files
        new_folder_count = max(int(total_files_allowed / min_files), 1)
        max_files_per_folder = int(total_files_allowed / new_folder_count)
        new_max_files = max(min(max_files_per_folder, max_files), min_files)
    
    print(f"  Original: {folder_count} folders, {min_files}-{max_files} files each")
    print(f"  Scaled to: {new_folder_count} folders, {min_files}-{new_max_files} files each")
    
    return new_folder_count, new_max_files


def main():
    global args, start_time
    
    parser = argparse.ArgumentParser(description='Generate test data for LogRhythm Archive Retention')
    parser.add_argument('--root-path', default='/Volumes/LRArchives/TestData',
                        help='Root directory for test data')
    parser.add_argument('--folder-count', type=int, default=5000,
                        help='Number of folders to create')
    parser.add_argument('--min-files', type=int, default=20,
                        help='Minimum files per folder')
    parser.add_argument('--max-files', type=int, default=500,
                        help='Maximum files per folder')
    parser.add_argument('--max-file-size-mb', type=int, default=10,
                        help='Maximum file size in MB')
    parser.add_argument('--max-size-gb', type=float, default=None,
                        help='Maximum total size in GB (will auto-scale if exceeded)')
    parser.add_argument('--threads', type=int, default=4,
                        help='Number of parallel threads (default: 4 for network shares)')
    parser.add_argument('--progress-interval', type=int, default=30,
                        help='Progress update interval in seconds')
    parser.add_argument('--mount-nas', action='store_true',
                        help='Mount NAS share before generating data')
    
    args = parser.parse_args()
    start_time = time.time()
    
    print("LogRhythm Archive Test Data Generator")
    print("=====================================")
    print(f"Target: {args.folder_count} folders with {args.min_files}-{args.max_files} files each")
    print(f"Max file size: {args.max_file_size_mb} MB")
    print(f"Threads: {args.threads}")
    
    # Mount NAS if requested
    if args.mount_nas:
        mount_point = mount_nas_share()
        args.root_path = os.path.join(mount_point, 'TestData')
    
    # Auto-scale if size limit specified
    folder_count = args.folder_count
    max_files = args.max_files
    
    if args.max_size_gb:
        print(f"Size limit: {args.max_size_gb} GB")
        folder_count, max_files = auto_scale_parameters(
            args.folder_count, args.min_files, args.max_files,
            args.max_file_size_mb, args.max_size_gb
        )
    
    # Create root directory
    os.makedirs(args.root_path, exist_ok=True)
    print(f"\nRoot path: {args.root_path}")
    
    # Create test .txt file in root
    test_file_path = os.path.join(args.root_path, 'testing_other_extensions.txt')
    with open(test_file_path, 'w') as f:
        f.write("This is a test file with a different extension.")
    
    # Generate buffer patterns for file content
    print("\nGenerating buffer patterns...")
    buffer_patterns = []
    for i in range(10):
        pattern = bytearray((i * 65536 + j) % 256 for j in range(65536))
        buffer_patterns.append(bytes(pattern))
    
    # Pre-generate all folder/file metadata
    all_folders, total_estimated_files = generate_folder_data(
        folder_count, args.min_files, max_files, args.max_file_size_mb
    )
    
    estimated_size_gb = (total_estimated_files * args.max_file_size_mb * 0.5) / 1024
    print(f"\nGenerated metadata for {len(all_folders)} folders")
    print(f"Estimated files: {total_estimated_files:,}")
    print(f"Estimated size: {estimated_size_gb:.2f} GB")
    
    # Process folders in parallel
    print(f"\nStarting parallel generation with {args.threads} threads...")
    print("This may take several hours for large datasets.\n")
    
    # Show initial progress
    show_progress(0, len(all_folders), 0, total_estimated_files, force=True)
    
    # Process in batches for better progress reporting
    batch_size = 25
    
    with ThreadPoolExecutor(max_workers=args.threads) as executor:
        for batch_start in range(0, len(all_folders), batch_size):
            batch_end = min(batch_start + batch_size, len(all_folders))
            batch = all_folders[batch_start:batch_end]
            
            # Submit batch
            futures = []
            for folder_data in batch:
                future = executor.submit(
                    create_folder_with_files,
                    folder_data, args.root_path, buffer_patterns
                )
                futures.append(future)
            
            # Wait for batch to complete
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    print(f"Error in thread: {e}")
            
            # Show progress
            show_progress(processed_folders, len(all_folders),
                         processed_files, total_estimated_files)
    
    # Final statistics
    end_time = time.time()
    total_time = end_time - start_time
    
    print(f"\n{'='*50}")
    print("GENERATION COMPLETE")
    print(f"{'='*50}")
    print(f"Created: {processed_folders} folders")
    print(f"Created: {processed_files} files")
    print(f"Total size: {total_bytes_generated / 1024 / 1024 / 1024:.2f} GB")
    print(f"Total time: {str(datetime.timedelta(seconds=int(total_time)))}")
    print(f"Average: {processed_folders / total_time:.2f} folders/second")
    print(f"File rate: {processed_files / total_time:.0f} files/second")
    print(f"Data rate: {(total_bytes_generated / 1024 / 1024) / total_time:.2f} MB/second")
    print(f"\nData location: {args.root_path}")


if __name__ == "__main__":
    main()