#!/usr/bin/env python3
"""
Check progress of 2TB test data generation on NAS
"""

import winrm
import subprocess
import sys

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
        
        print("Test Data Generation Progress Check")
        print("=" * 60)
        
        # Check running PowerShell processes
        cmd = '''
$processes = Get-Process pwsh -ErrorAction SilentlyContinue
if ($processes) {
    Write-Host "PowerShell 7 processes running: $($processes.Count)"
    $processes | Select-Object Id, StartTime, CPU | Format-Table -AutoSize
} else {
    Write-Host "No PowerShell 7 processes found running"
}
'''
        result = session.run_ps(cmd)
        print("Process Status:")
        print(result.std_out.decode('utf-8', errors='replace'))
        
        # Check NAS directory
        print("\nNAS Directory Status:")
        cmd = '''
Import-Module C:\\LR\\Scripts\\LRArchiveRetention\\modules\\ShareCredentialHelper.psm1 -Force -ErrorAction SilentlyContinue

# Try to access NAS with saved credentials
$testPath = "\\\\10.20.1.7\\LRArchives\\TestData"

# First try direct access
if (Test-Path $testPath -ErrorAction SilentlyContinue) {
    Write-Host "Direct access to NAS successful"
    $accessGranted = $true
} else {
    # Try with saved credential
    $cred = Get-SavedCredential -Target "NAS_CREDS" -ErrorAction SilentlyContinue
    if ($cred) {
        try {
            $null = New-PSDrive -Name NASTEMP -PSProvider FileSystem -Root $testPath -Credential $cred -ErrorAction Stop
            Write-Host "Access via saved credentials successful"
            $accessGranted = $true
            $useDrive = $true
        } catch {
            Write-Host "Error accessing NAS: $_"
            $accessGranted = $false
        }
    } else {
        Write-Host "No saved credentials found for NAS_CREDS"
        $accessGranted = $false
    }
}

if ($accessGranted) {
    $searchPath = if ($useDrive) { "NASTEMP:\\" } else { $testPath }
    
    Write-Host "Analyzing TestData directory..."
    Write-Host "This may take a moment for large directories..."
    
    # Get file count and size
    $files = @()
    try {
        $files = @(Get-ChildItem $searchPath -Recurse -File -ErrorAction Stop)
    } catch {
        # If full recursion fails, try to get at least top-level info
        Write-Host "Full scan failed, trying limited scan..."
        $files = @(Get-ChildItem $searchPath -File -ErrorAction SilentlyContinue)
    }
    
    if ($files.Count -gt 0) {
        $totalSize = ($files | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
        if (-not $totalSize) { $totalSize = 0 }
        
        Write-Host ""
        Write-Host "Current Statistics:"
        Write-Host "  Total Files: $($files.Count)"
        Write-Host "  Total Size: $([Math]::Round($totalSize / 1GB, 2)) GB"
        Write-Host "  Progress to 2TB: $([Math]::Round(($totalSize / 2TB) * 100, 2))%"
        
        if ($files.Count -lt 100) {
            # Show all files if there aren't many
            Write-Host ""
            Write-Host "Files created:"
            $files | Sort-Object CreationTime -Descending | ForEach-Object {
                Write-Host "  $($_.Name) - $([Math]::Round($_.Length / 1MB, 2)) MB"
            }
        } else {
            # Show summary for many files
            Write-Host ""
            Write-Host "Recent files (last 5):"
            $files | Sort-Object CreationTime -Descending | Select-Object -First 5 | ForEach-Object {
                Write-Host "  $($_.Name) - $([Math]::Round($_.Length / 1MB, 2)) MB - $($_.CreationTime)"
            }
            
            # Get directory structure
            Write-Host ""
            Write-Host "Directory structure:"
            $dirs = Get-ChildItem $searchPath -Directory -ErrorAction SilentlyContinue
            if ($dirs) {
                $dirs | Select-Object -First 10 | ForEach-Object {
                    $dirFiles = @(Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue)
                    Write-Host "  $($_.Name)/ - $($dirFiles.Count) files"
                }
                if ($dirs.Count -gt 10) {
                    Write-Host "  ... and $($dirs.Count - 10) more directories"
                }
            }
        }
        
        # Estimate completion time
        if ($totalSize -gt 0 -and $files.Count -gt 1) {
            $oldestFile = $files | Sort-Object CreationTime | Select-Object -First 1
            $newestFile = $files | Sort-Object CreationTime -Descending | Select-Object -First 1
            $timeSpan = $newestFile.CreationTime - $oldestFile.CreationTime
            
            if ($timeSpan.TotalSeconds -gt 0) {
                $bytesPerSecond = $totalSize / $timeSpan.TotalSeconds
                $remainingBytes = 2TB - $totalSize
                $remainingSeconds = $remainingBytes / $bytesPerSecond
                $eta = (Get-Date).AddSeconds($remainingSeconds)
                
                Write-Host ""
                Write-Host "Performance Metrics:"
                Write-Host "  Generation Rate: $([Math]::Round($bytesPerSecond / 1MB, 2)) MB/s"
                Write-Host "  Estimated Completion: $($eta.ToString('yyyy-MM-dd HH:mm:ss'))"
                Write-Host "  Time Remaining: $([Math]::Round($remainingSeconds / 3600, 2)) hours"
            }
        }
    } else {
        Write-Host "No files found in TestData directory yet."
        Write-Host "The generation process may still be initializing..."
    }
    
    if ($useDrive) {
        Remove-PSDrive NASTEMP -Force -ErrorAction SilentlyContinue
    }
}
'''
        
        result = session.run_ps(cmd)
        print(result.std_out.decode('utf-8', errors='replace'))
        
        print("\n" + "=" * 60)
        print("Progress check completed.")
        print("\nNote: The test data generation runs in the background.")
        print("It may take several hours to generate 2TB of data.")
        print("Run this script again to check updated progress.")
        
    except subprocess.CalledProcessError as e:
        print(f"Error getting Windows password: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {type(e).__name__}: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()