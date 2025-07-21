#!/usr/bin/env python3
"""
Start 2TB test data generation on NAS
"""
import winrm
import subprocess
import time
import sys

def get_windows_password():
    result = subprocess.run(['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'], capture_output=True, text=True, check=True)
    return result.stdout.strip()

print('Connecting to Windows server...')
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                       transport='kerberos',
                       server_cert_validation='ignore')

# Create the generation script
print('Creating generation script...')
result = session.run_ps("""
$script = @'
Set-Location C:\LR\Scripts\LRArchiveRetention
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "C:\\temp\\generate_2tb_$timestamp.log"

"Starting 2TB test data generation at $(Get-Date)" | Out-File $logFile
"Target: \\\\10.20.1.7\\LRArchives\\TestData" | Add-Content $logFile
"" | Add-Content $logFile

try {
    & pwsh -File .\\tests\\GenerateTestData.ps1 `
        -RootPath "\\\\10.20.1.7\\LRArchives\\TestData" `
        -FolderCount 10000 `
        -MinFiles 50 `
        -MaxFiles 100 `
        -MaxFileSizeMB 50 `
        -MaxSizeGB 2048 `
        -CredentialTarget "NAS_CREDS" `
        -ProgressUpdateIntervalSeconds 30 `
        *>&1 | Add-Content $logFile
} catch {
    "ERROR: $_" | Add-Content $logFile
}

"Completed at $(Get-Date)" | Add-Content $logFile
'@

$script | Out-File C:\\temp\\run_2tb_generation.ps1 -Encoding UTF8 -Force
"Script created at C:\\temp\\run_2tb_generation.ps1"
""")
print(result.std_out.decode())

# Start the generation
print('Starting generation process...')
result = session.run_ps("""
$proc = Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File C:\\temp\\run_2tb_generation.ps1" -PassThru -WindowStyle Hidden
"Started process with PID: $($proc.Id)"
""")
print(result.std_out.decode())

# Monitor progress
print('\nMonitoring progress...')
for i in range(5):
    time.sleep(10)
    print(f'\n--- Check {i+1} ---')
    
    # Check process
    result = session.run_ps('Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object Id, CPU, WS | Format-Table -AutoSize')
    print('Active processes:')
    print(result.std_out.decode())
    
    # Check latest log
    result = session.run_ps("""
    $latest = Get-ChildItem C:\\temp\\generate_2tb_*.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        "Log file: $($latest.Name)"
        "Size: $([math]::Round($latest.Length/1KB, 2)) KB"
        ""
        Get-Content $latest.FullName -Tail 20
    } else {
        "No log files found yet..."
    }
    """)
    print(result.std_out.decode())

print('\n\nGeneration process has been started. The script will continue running in the background.')
print('To monitor progress, check the log files in C:\\temp\\ on the Windows server.')