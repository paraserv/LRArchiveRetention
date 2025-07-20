#!/usr/bin/env python3
"""Test script to compare performance between original and optimized ArchiveRetention scripts"""

import winrm
import subprocess
import time
from datetime import datetime

def get_windows_password():
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], 
                           capture_output=True, text=True, check=True)
    return result.stdout.strip()

def create_test_data(session, path, file_count=1000):
    """Create test data with random dates"""
    print(f"Creating {file_count} test files in {path}...")
    
    # Create directory structure
    session.run_ps(f'''
    if (!(Test-Path "{path}")) {{
        New-Item -ItemType Directory -Path "{path}" -Force | Out-Null
    }}
    
    # Create subdirectories
    1..10 | ForEach-Object {{
        New-Item -ItemType Directory -Path "{path}\\Subfolder_$_" -Force | Out-Null
    }}
    ''')
    
    # Create files with various dates
    session.run_ps(f'''
    $baseDate = Get-Date
    $random = New-Object System.Random
    
    for ($i = 1; $i -le {file_count}; $i++) {{
        $folder = "{path}\\Subfolder_" + ($i % 10 + 1)
        $fileName = "$folder\\test_$i.lca"
        
        # Create empty file
        New-Item -ItemType File -Path $fileName -Force | Out-Null
        
        # Set random date between 0-730 days ago
        $daysAgo = $random.Next(0, 730)
        $fileDate = $baseDate.AddDays(-$daysAgo)
        (Get-Item $fileName).LastWriteTime = $fileDate
        
        if ($i % 100 -eq 0) {{
            Write-Host "Created $i files..."
        }}
    }}
    
    Write-Host "Test data creation complete. Created {file_count} files."
    ''')

def test_script_performance(session, script_name, test_path, retention_days=365):
    """Test a script and return performance metrics"""
    print(f"\nTesting {script_name}...")
    
    start_time = time.time()
    
    result = session.run_ps(f'''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    .\\{script_name} -ArchivePath "{test_path}" -RetentionDays {retention_days}
    ''')
    
    end_time = time.time()
    duration = end_time - start_time
    
    output = result.std_out.decode()
    
    # Extract key metrics from output
    metrics = {
        'duration': duration,
        'output': output,
        'errors': result.std_err.decode() if result.std_err else None
    }
    
    # Try to extract specific metrics from the output
    lines = output.split('\n')
    for line in lines:
        if 'Total files scanned:' in line:
            try:
                metrics['files_scanned'] = int(line.split(':')[-1].strip())
            except:
                pass
        elif 'Files deleted:' in line or 'Files to delete:' in line:
            try:
                metrics['files_deleted'] = int(line.split(':')[-1].strip())
            except:
                pass
        elif 'Enumeration time:' in line:
            try:
                metrics['enum_time'] = float(line.split(':')[-1].replace('seconds', '').strip())
            except:
                pass
        elif 'Total execution time:' in line:
            try:
                metrics['total_time'] = float(line.split(':')[-1].replace('seconds', '').strip())
            except:
                pass
    
    return metrics

def main():
    print("LogRhythm Archive Retention Performance Test")
    print("=" * 50)
    
    # Connect to Windows server
    session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                           auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                           transport='kerberos',
                           server_cert_validation='ignore')
    
    # Test paths
    test_path_original = "D:\\TestOriginal"
    test_path_optimized = "D:\\TestOptimized"
    file_count = 5000  # Moderate test size
    
    # Create test data for both scripts
    create_test_data(session, test_path_original, file_count)
    create_test_data(session, test_path_optimized, file_count)
    
    # Test original script
    print("\n" + "=" * 50)
    original_metrics = test_script_performance(session, "ArchiveRetention.ps1", test_path_original)
    
    # Test optimized script
    print("\n" + "=" * 50)
    optimized_metrics = test_script_performance(session, "ArchiveRetention_Optimized.ps1", test_path_optimized)
    
    # Compare results
    print("\n" + "=" * 50)
    print("PERFORMANCE COMPARISON")
    print("=" * 50)
    
    print(f"\nOriginal Script:")
    print(f"  Total Duration: {original_metrics['duration']:.2f} seconds")
    if 'files_scanned' in original_metrics:
        print(f"  Files Scanned: {original_metrics['files_scanned']}")
    if 'total_time' in original_metrics:
        print(f"  Script Reported Time: {original_metrics['total_time']:.2f} seconds")
    
    print(f"\nOptimized Script:")
    print(f"  Total Duration: {optimized_metrics['duration']:.2f} seconds")
    if 'files_scanned' in optimized_metrics:
        print(f"  Files Scanned: {optimized_metrics['files_scanned']}")
    if 'enum_time' in optimized_metrics:
        print(f"  Enumeration Time: {optimized_metrics['enum_time']:.2f} seconds")
    if 'total_time' in optimized_metrics:
        print(f"  Script Reported Time: {optimized_metrics['total_time']:.2f} seconds")
    
    # Calculate improvement
    if original_metrics['duration'] > 0:
        improvement = ((original_metrics['duration'] - optimized_metrics['duration']) / original_metrics['duration']) * 100
        speedup = original_metrics['duration'] / optimized_metrics['duration']
        print(f"\nPerformance Improvement:")
        print(f"  Speed Improvement: {improvement:.1f}%")
        print(f"  Speedup Factor: {speedup:.1f}x faster")
    
    # Clean up test data
    print("\nCleaning up test data...")
    session.run_ps(f'Remove-Item -Path "{test_path_original}" -Recurse -Force -ErrorAction SilentlyContinue')
    session.run_ps(f'Remove-Item -Path "{test_path_optimized}" -Recurse -Force -ErrorAction SilentlyContinue')
    
    print("\nTest complete!")

if __name__ == "__main__":
    main()