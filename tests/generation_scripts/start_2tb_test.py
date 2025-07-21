#!/usr/bin/env python3
"""
Start 2TB test data generation on NAS
"""

import winrm
import subprocess
import sys
from datetime import datetime

def get_windows_password():
    """Get Windows password from macOS keychain"""
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], 
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def main():
    try:
        # Create WinRM session
        print("Connecting to Windows server...")
        session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                               auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                               transport='kerberos',
                               server_cert_validation='ignore')
        
        # Check if PowerShell 7 is available
        print("\nChecking PowerShell 7 availability...")
        cmd = '''
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) {
    Write-Host "PowerShell 7 found at: $($pwsh.Source)"
    $true
} else {
    Write-Host "ERROR: PowerShell 7 (pwsh) is required but not installed!"
    $false
}
'''
        result = session.run_ps(cmd)
        output = result.std_out.decode().strip()
        print(output)
        
        if "ERROR:" in output or result.status_code != 0:
            print("\nPowerShell 7 is required. Please install from:")
            print("https://github.com/PowerShell/PowerShell/releases")
            sys.exit(1)
        
        # Check if test data script exists
        print("\nVerifying test data script...")
        cmd = '''
$scriptPath = "C:\\LR\\Scripts\\LRArchiveRetention\\tests\\GenerateTestData.ps1"
if (Test-Path $scriptPath) {
    Write-Host "Test data script found: $scriptPath"
    $true
} else {
    Write-Host "ERROR: Test data script not found at: $scriptPath"
    $false
}
'''
        result = session.run_ps(cmd)
        if "ERROR:" in result.std_out.decode() or result.status_code != 0:
            print(result.std_out.decode())
            sys.exit(1)
        
        # Check NAS credentials
        print("\nChecking NAS credentials...")
        cmd = '''
Import-Module C:\\LR\\Scripts\\LRArchiveRetention\\modules\\ShareCredentialHelper.psm1 -Force
$creds = Get-SavedCredentials | Where-Object { $_.Target -eq "NAS_CREDS" }
if ($creds) {
    Write-Host "NAS credentials found: NAS_CREDS"
    Write-Host "  User: $($creds.UserName)"
    Write-Host "  Path: $($creds.NetworkPath)"
    $true
} else {
    Write-Host "ERROR: NAS_CREDS not found. Please run Save-Credential.ps1 first."
    $false
}
'''
        result = session.run_ps(cmd)
        output = result.std_out.decode()
        print(output)
        
        if "ERROR:" in output or result.status_code != 0:
            print("\nTo save NAS credentials, run:")
            print('python3 winrm_helper.py custom ".\\Save-Credential.ps1 -Target NAS_CREDS -SharePath \\\\\\\\10.20.1.7\\\\LRArchives -UserName sanghanas"')
            sys.exit(1)
        
        # Create log directory
        print("\nPreparing log directory...")
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = f"C:\\\\LR\\\\Scripts\\\\LRArchiveRetention\\\\logs\\\\TestDataGeneration_{timestamp}.log"
        
        cmd = '''
$logDir = "C:\\LR\\Scripts\\LRArchiveRetention\\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Host "Created log directory: $logDir"
} else {
    Write-Host "Log directory exists: $logDir"
}
'''
        result = session.run_ps(cmd)
        print(result.std_out.decode().strip())
        
        # Start the test data generation job
        print("\n" + "="*60)
        print("Starting 2TB test data generation job...")
        print("="*60)
        
        cmd = f'''
cd C:\\LR\\Scripts\\LRArchiveRetention

# Define the job script block
$jobScript = {{
    try {{
        # Change to script directory
        Set-Location "C:\\LR\\Scripts\\LRArchiveRetention"
        
        # Log start time
        $startTime = Get-Date
        "*" * 60 | Out-File "{log_file}" -Encoding UTF8
        "Test Data Generation Started: $startTime" | Out-File "{log_file}" -Append -Encoding UTF8
        "Target: \\\\10.20.1.7\\LRArchives\\TestData" | Out-File "{log_file}" -Append -Encoding UTF8
        "Size: 2TB" | Out-File "{log_file}" -Append -Encoding UTF8
        "*" * 60 | Out-File "{log_file}" -Append -Encoding UTF8
        
        # Run the test data generation script
        & pwsh -File ".\\tests\\GenerateTestData.ps1" `
            -RootPath "\\\\10.20.1.7\\LRArchives\\TestData" `
            -TargetTotalSize 2TB `
            -UseCredential "NAS_CREDS" `
            -Verbose *>&1 | Tee-Object -FilePath "{log_file}" -Append
        
        # Log completion
        $endTime = Get-Date
        $duration = $endTime - $startTime
        "" | Out-File "{log_file}" -Append -Encoding UTF8
        "*" * 60 | Out-File "{log_file}" -Append -Encoding UTF8
        "Test Data Generation Completed: $endTime" | Out-File "{log_file}" -Append -Encoding UTF8
        "Duration: $duration" | Out-File "{log_file}" -Append -Encoding UTF8
        "*" * 60 | Out-File "{log_file}" -Append -Encoding UTF8
    }} catch {{
        "ERROR: $_" | Out-File "{log_file}" -Append -Encoding UTF8
        throw
    }}
}}

# Start the job
$job = Start-Job -ScriptBlock $jobScript -Name "TestDataGen_2TB_{timestamp}"

if ($job) {{
    Write-Host ""
    Write-Host "Job started successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Job Details:"
    Write-Host "  ID: $($job.Id)"
    Write-Host "  Name: $($job.Name)"
    Write-Host "  State: $($job.State)"
    Write-Host "  Log File: {log_file}"
    Write-Host ""
    
    # Get first few lines of output
    Start-Sleep -Seconds 2
    $output = Receive-Job -Job $job -Keep
    if ($output) {{
        Write-Host "Initial output:"
        $output | Select-Object -First 5 | ForEach-Object {{ Write-Host "  $_" }}
    }}
    
    $job.Id
}} else {{
    Write-Error "Failed to start job"
    exit 1
}}
'''
        
        result = session.run_ps(cmd)
        output = result.std_out.decode()
        print(output)
        
        if result.status_code == 0 and "Job started successfully!" in output:
            # Extract job ID from output
            lines = output.strip().split('\n')
            job_id = lines[-1].strip() if lines[-1].strip().isdigit() else None
            
            print("\n" + "="*60)
            print("SUCCESS: Test data generation is running!")
            print("="*60)
            print(f"\nLog file: {log_file}")
            
            if job_id:
                print(f"\nJob ID: {job_id}")
                print("\nMonitoring commands:")
                print(f"\n1. Check job status:")
                print(f'   python3 winrm_helper.py custom "Get-Job -Id {job_id} | Format-List"')
                print(f"\n2. View live output:")
                print(f'   python3 winrm_helper.py custom "Receive-Job -Id {job_id} -Keep | Select-Object -Last 20"')
                print(f"\n3. View log file:")
                print(f'   python3 winrm_helper.py custom "Get-Content \'{log_file}\' -Tail 20"')
            
            print("\n4. Check all test data jobs:")
            print('   python3 winrm_helper.py custom "Get-Job | Where-Object { $_.Name -like \'*TestData*\' } | Format-Table Id, Name, State, PSBeginTime -AutoSize"')
            
            print("\n5. Monitor NAS directory size:")
            print('   python3 winrm_helper.py custom "$files = Get-ChildItem \\\\\\\\10.20.1.7\\\\LRArchives\\\\TestData -Recurse -File; \'Files: \' + $files.Count + \', Size: \' + [Math]::Round(($files | Measure-Object Length -Sum).Sum / 1GB, 2) + \' GB\'"')
            
        else:
            print("\nError starting job:")
            if result.std_err:
                print(result.std_err.decode())
            sys.exit(1)
        
    except subprocess.CalledProcessError as e:
        print(f"Error getting Windows password: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {type(e).__name__}: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()