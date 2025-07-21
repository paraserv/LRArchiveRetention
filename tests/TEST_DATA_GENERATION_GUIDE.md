# Test Data Generation Guide for NAS

This guide documents the complete process for generating large test datasets (2TB+) on the NAS using the `GenerateTestData.ps1` script.

## Overview

The `GenerateTestData.ps1` script creates realistic LogRhythm archive test data with:
- Date-based folder structures matching LogRhythm format
- .lca files with proper timestamps
- Configurable size limits and auto-scaling
- High-performance parallel generation

## Prerequisites

1. **PowerShell 7+ (pwsh)** must be installed on the Windows server
2. **NAS credentials** must be saved using `Save-Credential.ps1`
3. **Sufficient disk space** on the target NAS location

## Known Issues & Solutions

### 1. Module Path Issue

**Problem**: The test script looks for modules relative to its own location (`tests/modules/`), not the main modules folder.

**Solution**: Copy the modules to the test directory:

```powershell
# Create the module directory structure in tests folder
$testModulesPath = "C:\LR\Scripts\LRArchiveRetention\tests\modules"
if (!(Test-Path $testModulesPath)) {
    New-Item -ItemType Directory -Path $testModulesPath -Force | Out-Null
}

# Copy the ShareCredentialHelper module
Copy-Item -Path "C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1" -Destination $testModulesPath -Force

# Create and copy the credential store
$testCredStore = "C:\LR\Scripts\LRArchiveRetention\tests\modules\CredentialStore"
New-Item -ItemType Directory -Path $testCredStore -Force | Out-Null
Copy-Item -Path "C:\LR\Scripts\LRArchiveRetention\modules\CredentialStore\*.cred" -Destination $testCredStore -Force
```

### 2. Process Management

**Problem**: Multiple PowerShell processes can interfere with each other.

**Solution**: Kill all PowerShell processes before starting:

```bash
# Via SSH or WinRM
taskkill /F /IM powershell.exe
taskkill /F /IM pwsh.exe
```

### 3. Credential Access

**Problem**: Credential files have restricted permissions (SYSTEM and service account only).

**Solution**: Run the script using WinRM with proper authentication, not via direct SSH.

## Step-by-Step Process

### 1. Connect via WinRM (from Mac/Linux)

```bash
# Activate Python environment
source winrm_env/bin/activate

# Test connection
python3 -c "
import winrm, subprocess

def get_windows_password():
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], capture_output=True, text=True, check=True)
    return result.stdout.strip()

session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                       transport='kerberos',
                       server_cert_validation='ignore')

result = session.run_ps('Write-Host \"Connected successfully\"')
print(result.std_out.decode())
"
```

### 2. Prepare the Environment

```powershell
# Run via WinRM session
cd C:\LR\Scripts\LRArchiveRetention

# Ensure modules are in the correct location (see Known Issues #1)
# Kill any existing PowerShell processes (see Known Issues #2)
```

### 3. Start the Generation

**For 2TB generation:**

```powershell
cd C:\LR\Scripts\LRArchiveRetention
& pwsh -File .\tests\GenerateTestData.ps1 `
    -RootPath "\\10.20.1.7\LRArchives\TestData" `
    -FolderCount 10000 `
    -MinFiles 50 `
    -MaxFiles 100 `
    -MaxFileSizeMB 50 `
    -MaxSizeGB 2048 `
    -CredentialTarget "NAS_CREDS" `
    -ProgressUpdateIntervalSeconds 30
```

**Note**: The script will auto-scale parameters to fit within the MaxSizeGB limit.

### 4. Run as Background Process

To run in background and capture logs:

```powershell
# Via WinRM
Start-Process pwsh -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "C:\LR\Scripts\LRArchiveRetention\tests\GenerateTestData.ps1",
    "-RootPath", "\\10.20.1.7\LRArchives\TestData",
    "-FolderCount", "10000",
    "-MinFiles", "50",
    "-MaxFiles", "100",
    "-MaxFileSizeMB", "50",
    "-MaxSizeGB", "2048",
    "-CredentialTarget", "NAS_CREDS",
    "-ProgressUpdateIntervalSeconds", "30"
) -WindowStyle Hidden -RedirectStandardOutput "C:\temp\generate_2tb_output.log" -PassThru
```

### 5. Monitor Progress

```powershell
# Check the log file
Get-Content C:\temp\generate_2tb_output.log -Tail 20

# Check process status
Get-Process pwsh | Select-Object Id, StartTime, CPU

# Monitor specific log file (if you know the name)
Get-Content C:\temp\generate_2tb_20250720_204432.log -Tail 15
```

## Expected Performance

For 2TB generation on NAS:
- **Data Rate**: 400-500 MB/sec
- **File Rate**: 15-20 files/sec
- **Total Time**: 1-2 hours
- **Auto-scaling**: Script will adjust folder/file counts to fit within size limit

## Complete Python Script for Remote Execution

Save this as `run_2tb_generation.py`:

```python
#!/usr/bin/env python3
import winrm
import subprocess
import time
import sys

def get_windows_password():
    result = subprocess.run(
        ['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
         '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def main():
    print("Connecting to Windows server...")
    session = winrm.Session(
        'https://windev01.lab.paraserv.com:5986/wsman',
        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
        transport='kerberos',
        server_cert_validation='ignore'
    )
    
    # Step 1: Fix module paths
    print("\nStep 1: Setting up module paths...")
    setup_cmd = '''
    $testModulesPath = "C:\\LR\\Scripts\\LRArchiveRetention\\tests\\modules"
    if (!(Test-Path $testModulesPath)) {
        New-Item -ItemType Directory -Path $testModulesPath -Force | Out-Null
    }
    Copy-Item -Path "C:\\LR\\Scripts\\LRArchiveRetention\\modules\\ShareCredentialHelper.psm1" -Destination $testModulesPath -Force
    
    $testCredStore = "$testModulesPath\\CredentialStore"
    if (!(Test-Path $testCredStore)) {
        New-Item -ItemType Directory -Path $testCredStore -Force | Out-Null
    }
    Copy-Item -Path "C:\\LR\\Scripts\\LRArchiveRetention\\modules\\CredentialStore\\*.cred" -Destination $testCredStore -Force
    
    "Module setup complete"
    '''
    result = session.run_ps(setup_cmd)
    print(result.std_out.decode())
    
    # Step 2: Kill existing processes
    print("\nStep 2: Cleaning up existing processes...")
    session.run_cmd('taskkill /F /IM pwsh.exe')
    
    # Step 3: Start generation
    print("\nStep 3: Starting 2TB generation...")
    start_cmd = '''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "C:\\temp\\generate_2tb_$timestamp.log"
    
    Start-Process pwsh -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ".\\tests\\GenerateTestData.ps1",
        "-RootPath", "\\\\10.20.1.7\\LRArchives\\TestData",
        "-FolderCount", "10000",
        "-MinFiles", "50",
        "-MaxFiles", "100",
        "-MaxFileSizeMB", "50",
        "-MaxSizeGB", "2048",
        "-CredentialTarget", "NAS_CREDS",
        "-ProgressUpdateIntervalSeconds", "30"
    ) -WindowStyle Hidden -RedirectStandardOutput $logFile -PassThru | Select-Object Id, Name
    
    Write-Host "Log file: $logFile"
    '''
    result = session.run_ps(start_cmd)
    print(result.std_out.decode())
    
    # Step 4: Monitor initial progress
    print("\nStep 4: Monitoring initial progress...")
    time.sleep(15)
    
    monitor_cmd = '''
    $latest = Get-ChildItem C:\\temp\\generate_2tb_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Get-Content $latest.FullName -Tail 20
    }
    '''
    result = session.run_ps(monitor_cmd)
    print(result.std_out.decode())
    
    print("\n" + "="*60)
    print("2TB generation started successfully!")
    print("Monitor progress in the log file shown above.")

if __name__ == "__main__":
    main()
```

## Troubleshooting

### "Access Denied" Errors
- Ensure you're using WinRM with proper service account credentials
- Check that NAS_CREDS was saved with the correct service account
- Verify the credential files were copied to `tests/modules/CredentialStore/`

### "Module not found" Errors
- The test script expects modules in `tests/modules/`, not the main modules folder
- Always copy modules as shown in Step 1

### Process Hangs
- Kill all PowerShell processes before starting
- Check for lock files: `Remove-Item C:\LR\Scripts\LRArchiveRetention\*.lock -Force`

### Auto-scaling Messages
- This is normal - the script adjusts parameters to fit within the specified size limit
- For 2TB limit, it typically scales down from 10,000 to ~1,000 folders

## Important Notes

1. **Always use WinRM** for running this script, not direct SSH
2. **Module paths are critical** - the test script has different expectations than the main script
3. **The process runs for hours** - use background execution with logging
4. **Auto-scaling is normal** - the script ensures it won't exceed the size limit
5. **Monitor via log files** - don't rely on terminal output for long operations

## Quick Command Reference

```bash
# From Mac/Linux with winrm_env activated:

# Quick test (small dataset)
python3 run_2tb_generation.py

# Monitor existing generation
ssh windev01 "Get-Content C:\\temp\\generate_2tb_*.log -Tail 20"

# Check process
ssh windev01 "Get-Process pwsh | Select-Object Id, CPU, StartTime"

# Kill all PowerShell
ssh windev01 "taskkill /F /IM pwsh.exe"
```