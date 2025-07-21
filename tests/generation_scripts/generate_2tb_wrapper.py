#!/usr/bin/env python3
"""
Wrapper to generate 2TB test data using existing winrm_helper infrastructure
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from winrm_helper import WinRMConnection

def main():
    conn = WinRMConnection()
    session = conn.connect()
    
    print("Starting 2TB test data generation on NAS...")
    print("Target: \\\\10.20.1.7\\LRArchives\\TestData")
    print("Size: 2048 GB (2 TB)")
    print("\nThis will take several hours to complete.")
    print("-" * 50)
    
    # Create and run the generation command
    cmd = '''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    
    # Import module and get credentials
    Import-Module .\\modules\\ShareCredentialHelper.psm1 -Force
    $cred = Get-ShareCredential -Target "NAS_CREDS"
    
    if ($null -eq $cred) {
        Write-Error "Failed to get NAS credentials"
        exit 1
    }
    
    # Map drive
    if (Get-PSDrive -Name T -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name T -Force
    }
    New-PSDrive -Name T -PSProvider FileSystem -Root $cred.SharePath -Credential $cred.Credential -Persist | Out-Null
    Write-Host "Mapped drive T: to NAS"
    
    # Start generation as a background job
    $job = Start-Job -ScriptBlock {
        Set-Location C:\\LR\\Scripts\\LRArchiveRetention
        & pwsh -File .\\tests\\GenerateTestData.ps1 `
            -RootPath "T:\\TestData" `
            -FolderCount 10000 `
            -MinFiles 50 `
            -MaxFiles 100 `
            -MaxFileSizeMB 50 `
            -MaxSizeGB 2048 `
            -ProgressUpdateIntervalSeconds 30
    } -Name "Generate2TB"
    
    Write-Host "Started background job: $($job.Name) (ID: $($job.Id))"
    Write-Host ""
    Write-Host "Waiting for initial output..."
    Start-Sleep -Seconds 10
    
    # Get initial output
    Receive-Job -Job $job -Keep | Select-Object -First 50
    
    Write-Host ""
    Write-Host "Job is running in background. To check progress:"
    Write-Host "  Get-Job -Name Generate2TB"
    Write-Host "  Receive-Job -Name Generate2TB -Keep"
    '''
    
    result = session.run_ps(cmd)
    print(result.std_out.decode())
    
    if result.std_err:
        print("\nErrors:", result.std_err.decode())

if __name__ == "__main__":
    main()