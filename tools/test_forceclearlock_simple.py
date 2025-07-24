#!/usr/bin/env python3
"""Simple test for ForceClearLock race condition fix"""

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
    
    print('Testing ForceClearLock race condition fix (v2.3.18)...\n')
    
    # Test 1: Clean start
    print('Test 1: Clean environment (no lock file)')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    Remove-Item -Path "$env:TEMP\\ArchiveRetention.lock" -Force -ErrorAction SilentlyContinue
    .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1 -WhatIf 2>&1 | 
        Select-String -Pattern "What if:|FATAL|ERROR" | Select-Object -First 5
    ''')
    output1 = result.std_out.decode()
    print(output1)
    
    # Test 2: Stale lock file
    print('\nTest 2: Stale lock file (should auto-remove)')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    # Create fake lock with non-existent PID
    "99999`n$(Get-Date)" | Set-Content -Path "$env:TEMP\\ArchiveRetention.lock" -Force
    .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1 -WhatIf 2>&1 | 
        Select-String -Pattern "stale|Stale|What if:|FATAL|ERROR" | Select-Object -First 5
    ''')
    output2 = result.std_out.decode()
    print(output2)
    
    # Test 3: ForceClearLock with orphaned lock
    print('\nTest 3: ForceClearLock with orphaned lock (main test)')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    # Create fake lock
    "88888`n$(Get-Date)" | Set-Content -Path "$env:TEMP\\ArchiveRetention.lock" -Force
    .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1 -WhatIf -ForceClearLock 2>&1 | 
        Select-String -Pattern "ForceClearLock|Orphaned|removed|What if:|lock file in use|FATAL|ERROR" | Select-Object -First 10
    ''')
    output3 = result.std_out.decode()
    print(output3)
    
    # Check results
    print('\n' + '='*60)
    print('RESULTS:')
    
    test1_pass = 'What if:' in output1 and 'FATAL' not in output1
    test2_pass = 'What if:' in output2 and 'stale' in output2.lower()
    test3_pass = 'What if:' in output3 and 'lock file in use' not in output3
    
    print(f'Test 1 (Clean start): {"✅ PASS" if test1_pass else "❌ FAIL"}')
    print(f'Test 2 (Stale lock): {"✅ PASS" if test2_pass else "❌ FAIL"}')
    print(f'Test 3 (ForceClearLock): {"✅ PASS" if test3_pass else "❌ FAIL"}')
    
    if test3_pass:
        print('\n✅ ForceClearLock race condition is FIXED!')
    else:
        print('\n❌ ForceClearLock race condition still exists')
    
    # Test 4: Multiple rapid ForceClearLock attempts
    print('\nTest 4: Rapid succession (5 attempts)')
    race_detected = False
    for i in range(5):
        result = session.run_ps('''
        cd C:\\LR\\Scripts\\LRArchiveRetention
        "77777`n$(Get-Date)" | Set-Content -Path "$env:TEMP\\ArchiveRetention.lock" -Force
        .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 1 -WhatIf -ForceClearLock 2>&1 | 
            Select-String -Pattern "lock file in use|What if:" | Select-Object -First 2
        ''')
        output = result.std_out.decode()
        if 'lock file in use' in output:
            race_detected = True
            print(f'  Attempt {i+1}: ❌ Race condition detected!')
        else:
            print(f'  Attempt {i+1}: ✅ Success')
    
    if not race_detected:
        print('\n✅ No race conditions in rapid succession test!')
    
    return 0 if all([test1_pass, test2_pass, test3_pass, not race_detected]) else 1

if __name__ == '__main__':
    sys.exit(main())