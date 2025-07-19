#!/usr/bin/env python3
"""
WinRM Helper Script for LRArchiveRetention
Eliminates escape sequence issues and standardizes timeout discipline
"""
import winrm
import subprocess
import sys
import os

def get_windows_password():
    """Get Windows service account password from keychain"""
    result = subprocess.run(['security', 'find-internet-password',
                           '-s', 'windev01.lab.paraserv.com',
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def get_nas_password():
    """Get NAS password from keychain"""
    result = subprocess.run(['security', 'find-internet-password',
                           '-s', '10.20.1.7',
                           '-a', 'sanghanas', '-w'],
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def create_session():
    """Create WinRM session with proper authentication"""
    return winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                        transport='kerberos',
                        server_cert_validation='ignore')

def clean_lock_files(session):
    """Clean any orphaned lock files"""
    # Remove lock files from temp directory
    result = session.run_ps(r'Remove-Item -Path "$env:TEMP\ArchiveRetention.lock" -Force -ErrorAction SilentlyContinue')
    # Wait a moment for cleanup
    import time
    time.sleep(1)
    return result.status_code == 0

def run_powershell(session, command, timeout=10):
    """Run PowerShell command with proper error handling"""
    try:
        result = session.run_ps(command)
        return {
            'exit_code': result.status_code,
            'stdout': result.std_out.decode().strip() if result.std_out else '',
            'stderr': result.std_err.decode().strip() if result.std_err else ''
        }
    except Exception as e:
        return {
            'exit_code': -1,
            'stdout': '',
            'stderr': str(e)
        }

def test_archive_retention_local():
    """Test ArchiveRetention.ps1 with local path"""
    session = create_session()

    # Clean any lock files first
    print("Cleaning lock files...")
    clean_lock_files(session)

    # Simple test with local path
    command = r'& "C:\LR\Scripts\LRArchiveRetention\ArchiveRetention.ps1" -ArchivePath "C:\temp" -RetentionDays 1095 -QuietMode'

    print("Testing ArchiveRetention.ps1 with local path...")
    result = run_powershell(session, command)

    print(f"Exit code: {result['exit_code']}")
    if result['stdout']:
        print("STDOUT:")
        print(result['stdout'])
    if result['stderr']:
        print("STDERR:")
        print(result['stderr'])

    return result['exit_code'] == 0

def test_archive_retention_nas():
    """Test ArchiveRetention.ps1 with NAS credentials"""
    session = create_session()

    # Test with NAS credentials
    command = r'& "C:\LR\Scripts\LRArchiveRetention\ArchiveRetention.ps1" -CredentialTarget "NAS_CREDS" -RetentionDays 1095 -QuietMode'

    print("Testing ArchiveRetention.ps1 with NAS credentials...")
    result = run_powershell(session, command)

    print(f"Exit code: {result['exit_code']}")
    if result['stdout']:
        print("STDOUT:")
        print(result['stdout'])
    if result['stderr']:
        print("STDERR:")
        print(result['stderr'])

    return result['exit_code'] == 0

def test_new_parameters():
    """Test the new v1.2.0 progress parameters"""
    session = create_session()

    # Clean any lock files first
    print("Cleaning lock files...")
    clean_lock_files(session)

    # Test with new progress parameters
    command = r'& "C:\LR\Scripts\LRArchiveRetention\ArchiveRetention.ps1" -ArchivePath "C:\temp" -RetentionDays 1095 -ShowScanProgress -ShowDeleteProgress -ProgressInterval 10'

    print("Testing new v1.2.0 progress parameters...")
    result = run_powershell(session, command)

    print(f"Exit code: {result['exit_code']}")
    if result['stdout']:
        print("STDOUT:")
        print(result['stdout'])
    if result['stderr']:
        print("STDERR:")
        print(result['stderr'])

    return result['exit_code'] == 0

def main():
    """Main function to run tests"""
    if len(sys.argv) < 2:
        print("Usage: python3 winrm_helper.py <test_type>")
        print("test_type: local, nas, parameters")
        sys.exit(1)

    test_type = sys.argv[1]

    if test_type == "local":
        success = test_archive_retention_local()
    elif test_type == "nas":
        success = test_archive_retention_nas()
    elif test_type == "parameters":
        success = test_new_parameters()
    else:
        print(f"Unknown test type: {test_type}")
        sys.exit(1)

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
