#!/usr/bin/env python3
"""Final test for ForceClearLock race condition fix in v2.3.18"""

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
    
    print('Testing ForceClearLock fix in v2.3.18\n')
    
    # Verify version
    result = session.run_ps('Get-Content C:\\LR\\Scripts\\LRArchiveRetention\\VERSION')
    version = result.std_out.decode().strip()
    print(f'Script version: {version}\n')
    
    if version != '2.3.18':
        print(f'❌ ERROR: Expected version 2.3.18, got {version}')
        return 1
    
    # Test 1: Clean start
    print('Test 1: Normal execution (no lock)')
    result = session.run_ps(r'''
    cd C:\LR\Scripts\LRArchiveRetention
    $lockPath = [System.IO.Path]::Combine($env:TEMP, 'ArchiveRetention.lock')
    Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    .\ArchiveRetention.ps1 -ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf 2>&1 | Out-String
    ''')
    output1 = result.std_out.decode()
    test1_pass = 'What if:' in output1
    print(f'Result: {"✅ PASS" if test1_pass else "❌ FAIL"}')
    
    # Test 2: ForceClearLock with orphaned lock (THE MAIN TEST)
    print('\nTest 2: ForceClearLock with orphaned lock')
    result = session.run_ps(r'''
    cd C:\LR\Scripts\LRArchiveRetention
    $lockPath = [System.IO.Path]::Combine($env:TEMP, 'ArchiveRetention.lock')
    # Create orphaned lock
    "99999`n$(Get-Date)" | Set-Content -Path $lockPath -Force
    Write-Host "Created lock file at: $lockPath"
    
    # Run with ForceClearLock
    .\ArchiveRetention.ps1 -ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock 2>&1 | Out-String
    ''')
    output2 = result.std_out.decode()
    
    # Show relevant lines
    print('\nRelevant output:')
    for line in output2.split('\n'):
        if any(word in line for word in ['ForceClearLock', 'Orphaned', 'lock', 'What if:', 'FATAL', 'ERROR', 'removed']):
            print(f'  {line.strip()}')
    
    # Check for success
    has_orphaned_msg = 'Orphaned lock file removed' in output2
    has_completion = 'What if:' in output2
    has_race_error = 'lock file in use' in output2 or 'being used by another process' in output2
    
    test2_pass = has_orphaned_msg and has_completion and not has_race_error
    
    print(f'\nChecks:')
    print(f'  - Found "Orphaned lock file removed": {has_orphaned_msg}')
    print(f'  - Script completed (found "What if:"): {has_completion}')
    print(f'  - Race condition error: {has_race_error}')
    print(f'\nResult: {"✅ PASS - No race condition!" if test2_pass else "❌ FAIL - Race condition still exists"}')
    
    # Test 3: Rapid succession
    print('\nTest 3: Rapid succession (5 attempts)')
    race_count = 0
    for i in range(5):
        result = session.run_ps(r'''
        cd C:\LR\Scripts\LRArchiveRetention
        $lockPath = [System.IO.Path]::Combine($env:TEMP, 'ArchiveRetention.lock')
        "88888`n$(Get-Date)" | Set-Content -Path $lockPath -Force
        .\ArchiveRetention.ps1 -ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock 2>&1 | Out-String
        ''')
        output = result.std_out.decode()
        if 'lock file in use' in output or 'being used by another process' in output:
            race_count += 1
            print(f'  Attempt {i+1}: ❌ Race condition')
        elif 'What if:' in output:
            print(f'  Attempt {i+1}: ✅ Success')
        else:
            print(f'  Attempt {i+1}: ⚠️  Unclear result')
    
    test3_pass = race_count == 0
    print(f'\nResult: {"✅ PASS" if test3_pass else f"❌ FAIL - {race_count} race conditions"}')
    
    # Summary
    print('\n' + '='*60)
    all_pass = test1_pass and test2_pass and test3_pass
    print(f'OVERALL: {"✅ ALL TESTS PASSED!" if all_pass else "❌ Some tests failed"}')
    
    if test2_pass:
        print('\n🎉 ForceClearLock race condition is FIXED in v2.3.18!')
    else:
        print('\n⚠️  ForceClearLock race condition still needs work')
    
    return 0 if all_pass else 1

if __name__ == '__main__':
    sys.exit(main())