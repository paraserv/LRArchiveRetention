#!/usr/bin/env python3
"""Run comprehensive ForceClearLock tests on Windows server"""

import winrm
import subprocess
import sys
import os

def get_windows_password():
    """Get Windows service account password from macOS keychain"""
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
    
    # Read test script
    test_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'test_forceclearlock_v2318.ps1')
    with open(test_path, 'r') as f:
        test_content = f.read()
    
    # Upload test script
    print('Uploading test script to Windows server...')
    
    # Use base64 encoding to avoid escaping issues
    import base64
    encoded = base64.b64encode(test_content.encode('utf-8')).decode('ascii')
    
    upload_cmd = f'''
    $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("{encoded}"))
    Set-Content -Path C:\\LR\\Scripts\\LRArchiveRetention\\test_forceclearlock_v2318.ps1 -Value $content -Encoding UTF8
    '''
    
    result = session.run_ps(upload_cmd)
    if result.status_code != 0:
        print(f'Failed to upload test script: {result.std_err.decode()}')
        sys.exit(1)
    
    print('Running comprehensive ForceClearLock tests...')
    print('=' * 70)
    
    # Run the test
    test_cmd = '''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    .\\test_forceclearlock_v2318.ps1
    '''
    
    result = session.run_ps(test_cmd)
    print(result.std_out.decode())
    
    if result.std_err:
        print('\nErrors:')
        print(result.std_err.decode())
    
    # Check if all tests passed
    if 'ALL TESTS PASSED!' in result.std_out.decode():
        print('\n✅ All tests passed successfully!')
        return 0
    else:
        print('\n❌ Some tests failed')
        return 1

if __name__ == '__main__':
    sys.exit(main())