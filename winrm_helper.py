#!/usr/bin/env python3
"""
WinRM Helper Script for LRArchiveRetention
Production-ready utility for reliable remote PowerShell operations

Version: See VERSION file
Documentation: README_winrm_helper.md
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

    # Clean any lock files first
    print("Cleaning lock files...")
    clean_lock_files(session)

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

def run_nas_dry_run(retention_days=456):
    """Run dry-run against NAS with specified retention period"""
    session = create_session()

    # Clean any lock files first
    print("Cleaning lock files...")
    clean_lock_files(session)

    # Dry run with progress monitoring
    command = f'& "C:\\LR\\Scripts\\LRArchiveRetention\\ArchiveRetention.ps1" -CredentialTarget "NAS_CREDS" -RetentionDays {retention_days} -ShowScanProgress -ShowDeleteProgress -ProgressInterval 30'

    print(f"Running NAS dry-run with {retention_days} days retention...")
    result = run_powershell(session, command, timeout=300)  # 5-minute timeout for NAS operations

    print(f"Exit code: {result['exit_code']}")
    if result['stdout']:
        print("STDOUT:")
        print(result['stdout'])
    if result['stderr']:
        print("STDERR:")
        print(result['stderr'])

    return result

def run_nas_execute(retention_days=456):
    """Execute actual deletion against NAS with specified retention period"""
    session = create_session()

    # Clean any lock files first
    print("Cleaning lock files...")
    clean_lock_files(session)

    # Execute with progress monitoring
    command = f'& "C:\\LR\\Scripts\\LRArchiveRetention\\ArchiveRetention.ps1" -CredentialTarget "NAS_CREDS" -RetentionDays {retention_days} -Execute -ShowScanProgress -ShowDeleteProgress -ProgressInterval 30'

    print(f"EXECUTING NAS deletion with {retention_days} days retention...")
    result = run_powershell(session, command, timeout=600)  # 10-minute timeout for execution

    print(f"Exit code: {result['exit_code']}")
    if result['stdout']:
        print("STDOUT:")
        print(result['stdout'])
    if result['stderr']:
        print("STDERR:")
        print(result['stderr'])

    return result

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

def get_version():
    """Get version from VERSION file"""
    try:
        with open('VERSION', 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return "2.0.0"  # Fallback version

def main():
    """Main function to run tests"""
    if len(sys.argv) < 2:
        print("LogRhythm Archive Retention WinRM Helper")
        print(f"Version: {get_version()}")
        print()
        print("Usage: python3 winrm_helper.py <command> [retention_days]")
        print("Commands:")
        print("  local               - Test with local path")
        print("  nas                 - Test NAS credentials")
        print("  parameters          - Test v2.0.0 features")
        print("  nas_dry_run [days]  - Production dry-run (default: 456 days)")
        print("  nas_execute [days]  - Production execution (default: 456 days)")
        print("  version             - Show version information")
        print()
        print("retention_days: optional, defaults to 456 (15 months)")
        sys.exit(1)

    test_type = sys.argv[1]

    if test_type == "version":
        print(f"WinRM Helper Version: {get_version()}")
        print("Part of LogRhythm Archive Retention Manager")
        sys.exit(0)

    retention_days = int(sys.argv[2]) if len(sys.argv) > 2 else 456

    if test_type == "local":
        success = test_archive_retention_local()
        sys.exit(0 if success else 1)
    elif test_type == "nas":
        success = test_archive_retention_nas()
        sys.exit(0 if success else 1)
    elif test_type == "parameters":
        success = test_new_parameters()
        sys.exit(0 if success else 1)
    elif test_type == "nas_dry_run":
        result = run_nas_dry_run(retention_days)
        sys.exit(0 if result['exit_code'] == 0 else 1)
    elif test_type == "nas_execute":
        result = run_nas_execute(retention_days)
        sys.exit(0 if result['exit_code'] == 0 else 1)
    else:
        print(f"Unknown test type: {test_type}")
        sys.exit(1)

if __name__ == "__main__":
    main()
