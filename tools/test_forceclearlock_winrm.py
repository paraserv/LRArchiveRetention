#!/usr/bin/env python3
"""Test ForceClearLock functionality via WinRM"""

import winrm
import subprocess
import sys

def get_windows_password():
    result = subprocess.run(
        ['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
         '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def main():
    session = winrm.Session(
        'https://windev01.lab.paraserv.com:5986/wsman',
        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
        transport='kerberos',
        server_cert_validation='ignore'
    )
    
    print('Testing ForceClearLock in v2.3.18\n')
    
    # Simple test case
    print('Creating stale lock and running with ForceClearLock...')
    
    test_script = '''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    
    # Create stale lock
    $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
    "99999" | Set-Content -Path $lockPath -Force
    
    # Run with ForceClearLock
    $output = & .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1 -ForceClearLock 2>&1
    
    # Check results
    $staleRemoved = $output -match "Stale lock file removed"
    $completed = $output -match "DRY-RUN"
    $raceError = $output -match "lock file in use"
    
    Write-Host "Results:"
    Write-Host "  Stale lock removed: $($staleRemoved.Count -gt 0)"
    Write-Host "  Script completed: $($completed.Count -gt 0)"
    Write-Host "  Race error: $($raceError.Count -gt 0)"
    
    if ($staleRemoved -and $completed -and -not $raceError) {
        Write-Host "PASS: ForceClearLock works correctly!"
    } else {
        Write-Host "FAIL: Race condition detected"
        Write-Host ""
        Write-Host "Key output lines:"
        $output | Where-Object { $_ -match "lock|Lock|Orphaned|removed|FATAL|ERROR" } | Select-Object -First 10
    }
    '''
    
    result = session.run_ps(test_script)
    print(result.std_out.decode())
    
    if result.std_err:
        print('\nErrors:')
        print(result.std_err.decode())
    
    return 0

if __name__ == '__main__':
    sys.exit(main())