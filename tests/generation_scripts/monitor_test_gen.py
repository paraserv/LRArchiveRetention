#!/usr/bin/env python3
"""
Monitor the 2TB test data generation progress
"""

import winrm
import subprocess
import sys
import time

def get_windows_password():
    """Get Windows password from macOS keychain"""
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], 
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def format_size(size_bytes):
    """Format bytes to human readable size"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} PB"

def main():
    try:
        session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                               auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                               transport='kerberos',
                               server_cert_validation='ignore')
        
        print("Monitoring Test Data Generation Progress")
        print("=" * 60)
        
        # Check job status
        cmd = '''
$jobs = Get-Job | Where-Object { $_.Name -like "*TestData*2TB*" }
if ($jobs) {
    $job = $jobs | Select-Object -First 1
    Write-Host "Job Name: $($job.Name)"
    Write-Host "Job ID: $($job.Id)"
    Write-Host "State: $($job.State)"
    Write-Host "Start Time: $($job.PSBeginTime)"
    
    if ($job.State -eq "Running") {
        $runtime = (Get-Date) - $job.PSBeginTime
        Write-Host "Runtime: $([Math]::Round($runtime.TotalMinutes, 2)) minutes"
    } elseif ($job.PSEndTime) {
        $runtime = $job.PSEndTime - $job.PSBeginTime
        Write-Host "Total Runtime: $([Math]::Round($runtime.TotalMinutes, 2)) minutes"
    }
    
    # Get log file
    $logFiles = Get-ChildItem C:\\LR\\Scripts\\LRArchiveRetention\\logs\\TestData*.log -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -gt $job.PSBeginTime } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
                
    if ($logFiles) {
        Write-Host "Log File: $($logFiles.FullName)"
    }
} else {
    Write-Host "No test data generation jobs found."
}
'''
        
        result = session.run_ps(cmd)
        print(result.std_out.decode())
        
        # Check NAS directory progress
        print("\nChecking NAS directory progress...")
        cmd = '''
Import-Module C:\\LR\\Scripts\\LRArchiveRetention\\modules\\ShareCredentialHelper.psm1 -Force
$cred = Get-SavedCredential -Target "NAS_CREDS"
if ($cred) {
    try {
        $null = New-PSDrive -Name NASTEMP -PSProvider FileSystem -Root "\\\\10.20.1.7\\LRArchives\\TestData" -Credential $cred -ErrorAction Stop
        
        Write-Host "Analyzing TestData directory..."
        $files = @(Get-ChildItem NASTEMP:\\ -Recurse -File -ErrorAction SilentlyContinue)
        
        if ($files.Count -gt 0) {
            $totalSize = ($files | Measure-Object Length -Sum).Sum
            $avgSize = $totalSize / $files.Count
            
            Write-Host ""
            Write-Host "Current Progress:"
            Write-Host "  Files Created: $($files.Count)"
            Write-Host "  Total Size: $([Math]::Round($totalSize / 1GB, 2)) GB"
            Write-Host "  Average File Size: $([Math]::Round($avgSize / 1MB, 2)) MB"
            Write-Host "  Progress to 2TB: $([Math]::Round(($totalSize / 2TB) * 100, 2))%"
            
            # Estimate completion
            $targetSize = 2TB
            if ($totalSize -gt 0) {
                $remainingSize = $targetSize - $totalSize
                $filesNeeded = [Math]::Ceiling($remainingSize / $avgSize)
                Write-Host "  Estimated files remaining: $filesNeeded"
            }
            
            # Show recent files
            Write-Host ""
            Write-Host "Recent files created:"
            $files | Sort-Object CreationTime -Descending | Select-Object -First 5 | ForEach-Object {
                Write-Host "  $($_.Name) - $([Math]::Round($_.Length / 1MB, 2)) MB - $($_.CreationTime)"
            }
        } else {
            Write-Host "No files found in TestData directory yet."
        }
        
        Remove-PSDrive NASTEMP -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Error accessing NAS: $_"
    }
} else {
    Write-Host "NAS_CREDS not found"
}
'''
        
        result = session.run_ps(cmd)
        print(result.std_out.decode())
        
        # Get last few lines from log if available
        print("\nRecent log entries:")
        cmd = '''
$logFiles = Get-ChildItem C:\\LR\\Scripts\\LRArchiveRetention\\logs\\TestData*.log -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
            
if ($logFiles) {
    Get-Content $logFiles.FullName -Tail 10 -ErrorAction SilentlyContinue
} else {
    Write-Host "No log file found yet."
}
'''
        
        result = session.run_ps(cmd)
        log_output = result.std_out.decode().strip()
        if log_output:
            print(log_output)
        
        print("\n" + "=" * 60)
        print("Monitor script completed.")
        
    except subprocess.CalledProcessError as e:
        print(f"Error getting Windows password: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {type(e).__name__}: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()