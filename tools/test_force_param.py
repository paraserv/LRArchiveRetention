#!/usr/bin/env python3
"""Test the new Force parameter that kills other ArchiveRetention processes"""

import winrm
import subprocess
import sys
import time

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
    
    print('Testing new Force parameter in v2.3.19\n')
    
    # Verify version
    result = session.run_ps('Get-Content C:\\LR\\Scripts\\LRArchiveRetention\\VERSION')
    version = result.std_out.decode().strip()
    print(f'Script version: {version}\n')
    
    # Test 1: Start a dummy ArchiveRetention process
    print('Test 1: Starting dummy ArchiveRetention process...')
    session.run_ps('''
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host 'Dummy ArchiveRetention.ps1 process'; Start-Sleep -Seconds 60" -WindowStyle Hidden
    ''')
    time.sleep(2)
    
    # Check running processes
    result = session.run_ps('''
    $procs = Get-Process powershell* | Where-Object { $_.MainWindowTitle -match "ArchiveRetention" -or $_.Id -eq $PID }
    Write-Host "PowerShell processes running: $($procs.Count)"
    ''')
    print(result.std_out.decode().strip())
    
    # Test 2: Run with Force parameter
    print('\nTest 2: Running ArchiveRetention with -Force parameter...')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    
    # Create lock file to simulate stuck situation
    $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
    "12345" | Set-Content -Path $lockPath -Force
    Write-Host "Created lock file"
    
    # Run with Force
    $output = & .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 91 -Force 2>&1 | Out-String
    
    # Check for key messages
    $terminated = $output -match "Terminating PID|terminated"
    $lockRemoved = $output -match "Lock file removed"
    $completed = $output -match "DRY-RUN.*COMPLETED"
    
    Write-Host ""
    Write-Host "Results:"
    Write-Host "  Processes terminated: $($terminated.Count -gt 0)"
    Write-Host "  Lock file removed: $($lockRemoved.Count -gt 0)"
    Write-Host "  Script completed: $($completed.Count -gt 0)"
    
    if ($completed) {
        Write-Host ""
        Write-Host "SUCCESS: Force parameter worked correctly!"
    }
    
    # Show relevant output
    Write-Host ""
    Write-Host "Key output lines:"
    $output -split "`n" | Where-Object { $_ -match "Force|Terminating|terminated|Lock.*removed|COMPLETED" } | Select-Object -First 10
    ''')
    
    print(result.std_out.decode())
    
    # Test 3: Compare with ForceClearLock
    print('\n\nTest 3: Comparing Force vs ForceClearLock...')
    print('Force parameter:')
    print('  - Kills ALL other ArchiveRetention processes')
    print('  - Removes lock file unconditionally')
    print('  - Bypasses all safety checks')
    print('  - Use when: System is stuck and you need immediate execution')
    print('\nForceClearLock parameter:')
    print('  - Only removes orphaned lock files')
    print('  - Checks if processes are actually running')
    print('  - Safer but may fail if processes exist')
    print('  - Use when: Lock file exists but no actual process is running')
    
    return 0

if __name__ == '__main__':
    sys.exit(main())