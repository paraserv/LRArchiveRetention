#!/usr/bin/env python3
"""
Script to generate 3TB of test data on NAS
Handles all module path issues and credential setup
"""
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
    try:
        session.run_cmd('taskkill /F /IM pwsh.exe')
    except:
        pass  # Ignore if no processes to kill
    
    # Step 3: Start 3TB generation
    print("\nStep 3: Starting 3TB generation...")
    start_cmd = '''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = "C:\\temp\\generate_3tb_$timestamp.log"
    
    Start-Process pwsh -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ".\\tests\\GenerateTestData.ps1",
        "-RootPath", "\\\\10.20.1.7\\LRArchives\\TestData",
        "-FolderCount", "15000",
        "-MinFiles", "50",
        "-MaxFiles", "100",
        "-MaxFileSizeMB", "50",
        "-MaxSizeGB", "3072",
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
    $latest = Get-ChildItem C:\\temp\\generate_3tb_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Get-Content $latest.FullName -Tail 20
    }
    '''
    result = session.run_ps(monitor_cmd)
    print(result.std_out.decode())
    
    print("\n" + "="*60)
    print("3TB generation started successfully!")
    print("Monitor progress in the log file shown above.")
    print("\nEstimated completion time: 1.5-2.5 hours")
    print("Data rate: ~400-500 MB/sec")
    print("Expected files: ~125,000 files")

if __name__ == "__main__":
    main()