#!/usr/bin/env python3
"""Test script to verify parallel processing defaults in ArchiveRetention.ps1"""

import winrm
import subprocess
import sys

def get_windows_password():
    """Retrieve Windows password from macOS keychain"""
    result = subprocess.run(
        ['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
         '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def main():
    # Create WinRM session
    session = winrm.Session(
        'https://windev01.lab.paraserv.com:5986/wsman',
        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
        transport='kerberos',
        server_cert_validation='ignore'
    )
    
    # Change to script directory
    session.run_ps('cd C:\\LR\\Scripts\\LRArchiveRetention')
    
    print("Testing ArchiveRetention.ps1 v2.3.7 - Parallel Processing Defaults\n")
    
    # Test 1: Network path auto-enables parallel
    print("=== Test 1: Network path (NAS_CREDS) - should auto-enable parallel ===")
    cmd = '''
    .\\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 1095 -WhatIf *>&1 | 
    Where-Object { $_ -match "(Auto-enabled|Parallel Processing|threads)" } | 
    Select-Object -First 5
    '''
    result = session.run_ps(cmd)
    output = result.std_out.decode().strip()
    print(output if output else "No matching output found")
    
    # Test 2: Check the log file
    print("\n=== Test 2: Check log file for auto-enable confirmation ===")
    cmd = '''
    $logFile = Get-ChildItem .\\script_logs\\ArchiveRetention*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($logFile) {
        Get-Content $logFile.FullName -Tail 50 | Where-Object { $_ -match "(Auto-enabled|Parallel Processing.*threads)" }
    }
    '''
    result = session.run_ps(cmd)
    output = result.std_out.decode().strip()
    print(output if output else "No log entries found")
    
    # Test 3: Sequential override
    print("\n=== Test 3: Network path with -Sequential - should show warning ===")
    cmd = '''
    .\\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 1095 -Sequential -WhatIf *>&1 | 
    Where-Object { $_ -match "(WARNING|Sequential|Parallel Processing)" } | 
    Select-Object -First 5
    '''
    result = session.run_ps(cmd)
    output = result.std_out.decode().strip()
    print(output if output else "No matching output found")
    
    # Test 4: Local path - should remain sequential
    print("\n=== Test 4: Local path - should use sequential (no auto-parallel) ===")
    cmd = '''
    .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1095 -WhatIf *>&1 | 
    Where-Object { $_ -match "Parallel Processing" } | 
    Select-Object -First 5
    '''
    result = session.run_ps(cmd)
    output = result.std_out.decode().strip()
    print(output if output else "No matching output found")
    
    print("\n=== Test Summary ===")
    print("If Test 1 shows 'Auto-enabled parallel' and '8 threads' - SUCCESS")
    print("If Test 3 shows 'PERFORMANCE WARNING' - SUCCESS")
    print("If Test 4 shows 'Disabled (sequential)' - SUCCESS")

if __name__ == "__main__":
    main()