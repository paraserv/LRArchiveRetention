#!/usr/bin/env python3
"""
Start test data generation on NAS with proper logging
"""

import winrm
import subprocess
import sys
import os

def get_windows_password():
    """Get Windows password from macOS keychain"""
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], 
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def main():
    try:
        # Create WinRM session
        session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                               auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                               transport='kerberos',
                               server_cert_validation='ignore')
        
        # First, copy the Start-TestDataGeneration.ps1 script
        print('Copying Start-TestDataGeneration.ps1 to server...')
        
        # Read the local file
        with open('Start-TestDataGeneration.ps1', 'r') as f:
            script_content = f.read()
        
        # Create a temporary file on the server and write content
        cmd = '''
$scriptPath = "C:\\LR\\Scripts\\LRArchiveRetention\\Start-TestDataGeneration.ps1"
$tempPath = "C:\\LR\\Scripts\\LRArchiveRetention\\temp_start.txt"

# Ensure directory exists
$dir = Split-Path $scriptPath -Parent
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Write base64 encoded content to avoid escaping issues
$content = @'
{}
'@

# Save the content
$content | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

if (Test-Path $scriptPath) {
    Write-Host "Script saved successfully"
} else {
    Write-Host "ERROR: Failed to save script"
}
'''.format(script_content.replace("'", "''"))
        
        result = session.run_ps(cmd)
        if result.status_code != 0:
            print(f'Error copying script: {result.std_err.decode()}')
            sys.exit(1)
        
        print(result.std_out.decode().strip())
        
        # Now copy the monitoring script
        print('\nCopying Monitor-TestDataGeneration.ps1 to server...')
        
        with open('Monitor-TestDataGeneration.ps1', 'r') as f:
            monitor_content = f.read()
        
        cmd = '''
$scriptPath = "C:\\LR\\Scripts\\LRArchiveRetention\\Monitor-TestDataGeneration.ps1"

# Write content
$content = @'
{}
'@

$content | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

if (Test-Path $scriptPath) {
    Write-Host "Monitoring script saved successfully"
} else {
    Write-Host "ERROR: Failed to save monitoring script"
}
'''.format(monitor_content.replace("'", "''"))
        
        result = session.run_ps(cmd)
        if result.status_code != 0:
            print(f'Error copying monitoring script: {result.std_err.decode()}')
            sys.exit(1)
        
        print(result.std_out.decode().strip())
        
        # Start the test data generation
        print('\n' + '='*60)
        print('Starting test data generation...')
        print('='*60 + '\n')
        
        # Run the start script
        cmd = '''
cd C:\\LR\\Scripts\\LRArchiveRetention

# Check if pwsh is available
$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshPath) {
    Write-Host "ERROR: PowerShell 7 (pwsh) is not installed!" -ForegroundColor Red
    Write-Host "Please install PowerShell 7 from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
    exit 1
}

# Run the script
.\\Start-TestDataGeneration.ps1
'''
        
        result = session.run_ps(cmd)
        print(result.std_out.decode())
        
        if result.status_code != 0:
            print(f'\nError: {result.std_err.decode()}')
        else:
            print('\n' + '='*60)
            print('Test data generation job has been started!')
            print('='*60)
            print('\nMonitoring commands:')
            print('  1. Check job status:')
            print('     python3 start_test_generation.py --monitor')
            print('\n  2. View detailed progress:')
            print('     python3 winrm_helper.py custom "cd C:\\\\LR\\\\Scripts\\\\LRArchiveRetention; .\\\\Monitor-TestDataGeneration.ps1"')
            print('\n  3. Check NAS directory size:')
            print('     python3 winrm_helper.py custom "Get-ChildItem \\\\\\\\10.20.1.7\\\\LRArchives\\\\TestData -Recurse | Measure-Object -Property Length -Sum"')
        
    except subprocess.CalledProcessError as e:
        print(f'Error getting Windows password: {e}')
        sys.exit(1)
    except Exception as e:
        print(f'Error: {e}')
        sys.exit(1)

if __name__ == '__main__':
    # Check for monitor flag
    if len(sys.argv) > 1 and sys.argv[1] == '--monitor':
        # Quick monitoring mode
        try:
            session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                                   auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                                   transport='kerberos',
                                   server_cert_validation='ignore')
            
            cmd = 'cd C:\\LR\\Scripts\\LRArchiveRetention; .\\Monitor-TestDataGeneration.ps1'
            result = session.run_ps(cmd)
            print(result.std_out.decode())
            
        except Exception as e:
            print(f'Error: {e}')
            sys.exit(1)
    else:
        main()