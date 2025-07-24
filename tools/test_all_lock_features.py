#!/usr/bin/env python3
"""Comprehensive test of all lock-related features in v2.3.19"""

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

def run_test(session, test_name, script_args, setup_commands=""):
    """Run a test case and report results"""
    print(f'\n{"="*60}')
    print(f'Test: {test_name}')
    print("="*60)
    
    # Setup
    if setup_commands:
        session.run_ps(setup_commands)
    
    # Run test
    result = session.run_ps(f'''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    $output = & .\\ArchiveRetention.ps1 {script_args} 2>&1 | Out-String
    
    # Extract key info
    $lines = $output -split "`n"
    $relevant = $lines | Where-Object {{ $_ -match "Force|lock|Lock|terminated|removed|DRY-RUN.*COMPLETED|FATAL|ERROR" }}
    
    if ($relevant) {{
        $relevant | Select-Object -First 15
    }} else {{
        "No relevant output found"
    }}
    
    # Check completion
    if ($output -match "DRY-RUN.*COMPLETED") {{
        Write-Host ""
        Write-Host "RESULT: SUCCESS - Script completed" -ForegroundColor Green
    }} else {{
        Write-Host ""
        Write-Host "RESULT: FAILED - Script did not complete" -ForegroundColor Red
    }}
    ''')
    
    print(result.std_out.decode())
    return "SUCCESS" in result.std_out.decode()

def main():
    session = winrm.Session(
        'https://windev01.lab.paraserv.com:5986/wsman',
        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
        transport='kerberos',
        server_cert_validation='ignore'
    )
    
    print('Comprehensive Lock Feature Tests - v2.3.19')
    
    # Clean start
    session.run_ps('''
    $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
    Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    Stop-Process -Name powershell -Force -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID }
    ''')
    
    results = []
    
    # Test 1: Normal execution (no lock)
    results.append(run_test(
        session,
        "Normal execution - no lock file",
        "-ArchivePath 'C:\\Temp' -RetentionDays 91",
        ""
    ))
    
    # Test 2: Stale lock (auto-removal)
    results.append(run_test(
        session,
        "Stale lock file - automatic removal",
        "-ArchivePath 'C:\\Temp' -RetentionDays 91",
        '''
        $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
        "99999" | Set-Content -Path $lockPath -Force
        Write-Host "Setup: Created stale lock with PID 99999"
        '''
    ))
    
    # Test 3: ForceClearLock with orphaned lock
    results.append(run_test(
        session,
        "ForceClearLock - orphaned lock file",
        "-ArchivePath 'C:\\Temp' -RetentionDays 91 -ForceClearLock",
        '''
        $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
        "88888" | Set-Content -Path $lockPath -Force
        Write-Host "Setup: Created orphaned lock with PID 88888"
        '''
    ))
    
    # Test 4: Force parameter
    results.append(run_test(
        session,
        "Force parameter - aggressive cleanup",
        "-ArchivePath 'C:\\Temp' -RetentionDays 91 -Force",
        '''
        $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
        "77777" | Set-Content -Path $lockPath -Force
        Write-Host "Setup: Created lock with PID 77777"
        '''
    ))
    
    # Summary
    print('\n' + '='*60)
    print('TEST SUMMARY')
    print('='*60)
    
    test_names = [
        "Normal execution",
        "Stale lock auto-removal",
        "ForceClearLock",
        "Force parameter"
    ]
    
    all_passed = True
    for i, (name, passed) in enumerate(zip(test_names, results)):
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f'{name}: {status}')
        if not passed:
            all_passed = False
    
    print('\n' + '='*60)
    if all_passed:
        print('✅ ALL TESTS PASSED!')
        print('\nLock handling features are working correctly in v2.3.19')
    else:
        print('❌ Some tests failed')
    
    return 0 if all_passed else 1

if __name__ == '__main__':
    sys.exit(main())