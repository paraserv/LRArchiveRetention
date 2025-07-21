#!/usr/bin/env python3
"""
Deploy scripts and start test data generation on Windows server
"""

import winrm
import subprocess
import sys
import base64

def get_windows_password():
    """Get Windows password from macOS keychain"""
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], 
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def deploy_script(session, local_path, remote_path):
    """Deploy a script file to the Windows server using base64 encoding"""
    print(f'Deploying {local_path} to {remote_path}...')
    
    # Read the local file
    with open(local_path, 'r') as f:
        content = f.read()
    
    # Encode to base64 to avoid escaping issues
    encoded = base64.b64encode(content.encode('utf-8')).decode('ascii')
    
    # PowerShell command to decode and save
    cmd = f'''
$encodedContent = "{encoded}"
$bytes = [System.Convert]::FromBase64String($encodedContent)
$content = [System.Text.Encoding]::UTF8.GetString($bytes)
$content | Out-File -FilePath "{remote_path}" -Encoding UTF8 -Force

if (Test-Path "{remote_path}") {{
    $size = (Get-Item "{remote_path}").Length
    Write-Host "File saved successfully: $size bytes"
}} else {{
    Write-Host "ERROR: Failed to save file"
}}
'''
    
    result = session.run_ps(cmd)
    if result.status_code != 0:
        print(f'Error: {result.std_err.decode()}')
        return False
    
    print(result.std_out.decode().strip())
    return True

def main():
    try:
        # Create WinRM session
        session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                               auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                               transport='kerberos',
                               server_cert_validation='ignore')
        
        # Deploy both scripts
        scripts = [
            ('Start-TestDataGeneration.ps1', 'C:\\LR\\Scripts\\LRArchiveRetention\\Start-TestDataGeneration.ps1'),
            ('Monitor-TestDataGeneration.ps1', 'C:\\LR\\Scripts\\LRArchiveRetention\\Monitor-TestDataGeneration.ps1')
        ]
        
        for local, remote in scripts:
            if not deploy_script(session, local, remote):
                print(f'Failed to deploy {local}')
                sys.exit(1)
        
        print('\n' + '='*60)
        print('Starting test data generation process...')
        print('='*60 + '\n')
        
        # First check if PowerShell 7 is available
        cmd = '''
$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshPath) {
    Write-Host "PowerShell 7 found at: $($pwshPath.Source)"
    $pwshPath.Source
} else {
    Write-Host "ERROR: PowerShell 7 (pwsh) is not installed!"
    Write-Host "Test data generation requires PowerShell 7"
    exit 1
}
'''
        
        result = session.run_ps(cmd)
        print(result.std_out.decode())
        
        if result.status_code != 0:
            print('\nPowerShell 7 is required but not installed.')
            print('Please install from: https://github.com/PowerShell/PowerShell/releases')
            sys.exit(1)
        
        # Now start the test data generation
        cmd = '''
cd C:\\LR\\Scripts\\LRArchiveRetention

# Run the start script
& pwsh -File .\\Start-TestDataGeneration.ps1
'''
        
        result = session.run_ps(cmd)
        output = result.std_out.decode()
        print(output)
        
        if result.status_code != 0:
            print(f'\nError: {result.std_err.decode()}')
        else:
            # Check if a job was started
            if "Job started successfully" in output:
                print('\n' + '='*60)
                print('SUCCESS: Test data generation job is running!')
                print('='*60)
                print('\nMonitoring options:')
                print('\n1. Quick status check:')
                print('   python3 deploy_and_start_test.py --monitor')
                print('\n2. Detailed monitoring:')
                print('   python3 winrm_helper.py custom "cd C:\\\\LR\\\\Scripts\\\\LRArchiveRetention; pwsh -File .\\\\Monitor-TestDataGeneration.ps1"')
                print('\n3. Check background jobs:')
                print('   python3 winrm_helper.py custom "Get-Job | Where-Object { $_.Name -like \'*TestData*\' } | Format-List"')
                print('\n4. View recent log entries:')
                print('   python3 winrm_helper.py custom "Get-Content C:\\\\LR\\\\Scripts\\\\LRArchiveRetention\\\\logs\\\\TestDataGeneration_*.log -Tail 20"')
        
    except subprocess.CalledProcessError as e:
        print(f'Error getting Windows password: {e}')
        sys.exit(1)
    except Exception as e:
        print(f'Error: {type(e).__name__}: {e}')
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--monitor':
        # Quick monitoring mode
        try:
            session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                                   auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                                   transport='kerberos',
                                   server_cert_validation='ignore')
            
            cmd = 'cd C:\\LR\\Scripts\\LRArchiveRetention; pwsh -File .\\Monitor-TestDataGeneration.ps1'
            result = session.run_ps(cmd)
            print(result.std_out.decode())
            
        except Exception as e:
            print(f'Error: {e}')
            sys.exit(1)
    else:
        main()