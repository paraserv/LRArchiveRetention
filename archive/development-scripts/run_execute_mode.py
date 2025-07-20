#!/usr/bin/env python3
"""
Run the script in execute mode to actually clean up directories
"""
import winrm
import subprocess

def get_windows_password():
    """Get Windows service account password from keychain"""
    result = subprocess.run(['security', 'find-internet-password',
                           '-s', 'windev01.lab.paraserv.com',
                           '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()

def create_session():
    """Create WinRM session with proper authentication"""
    return winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                        transport='kerberos',
                        server_cert_validation='ignore')

def run_execute_mode():
    """Run the script in execute mode with a shorter retention for testing"""
    session = create_session()
    
    print("🚀 Running archive retention in EXECUTE mode...")
    
    # Use a shorter retention period to test execute mode quickly
    cmd = r'& "C:\LR\Scripts\LRArchiveRetention\ArchiveRetention.ps1" -CredentialTarget "NAS_CREDS" -RetentionDays 30 -Execute -ShowScanProgress -ShowDeleteProgress'
    
    result = session.run_ps(cmd)
    
    print(f"Exit code: {result.status_code}")
    if result.std_out:
        output = result.std_out.decode()
        print("Output:")
        print(output)
        
        # Check if it's actually running in execute mode
        if "Mode: EXECUTION" in output:
            print("\n✅ Script is running in EXECUTE mode!")
        elif "DRY RUN" in output:
            print("\n❌ Script is still in DRY RUN mode")
        else:
            print("\n❓ Could not determine execution mode from output")
            
    if result.std_err:
        print("Errors:")
        print(result.std_err.decode())
        
    return result.status_code == 0

def check_results():
    """Check the results of the execution"""
    session = create_session()
    
    print("\n📊 Checking execution results...")
    
    # Check recent logs for actual deletions
    result = session.run_ps(r'''
    $logFile = "C:\LR\Scripts\LRArchiveRetention\script_logs\ArchiveRetention.log"
    
    # Look for actual deletion activity
    $deletionEntries = Get-Content $logFile | Select-String -Pattern "Deleted file:|Removed empty directory:" | Select-Object -Last 10
    
    if ($deletionEntries.Count -gt 0) {
        Write-Host "✅ Found actual deletion activity:" -ForegroundColor Green
        $deletionEntries | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "❌ No actual deletion activity found" -ForegroundColor Red
        
        # Check for dry-run activity instead
        $dryRunEntries = Get-Content $logFile | Select-String -Pattern "Would delete:|Would remove" | Select-Object -Last 5
        if ($dryRunEntries.Count -gt 0) {
            Write-Host "Found dry-run activity instead:" -ForegroundColor Yellow
            $dryRunEntries | ForEach-Object { Write-Host "  $_" }
        }
    }
    
    # Check the latest mode entry
    $modeEntry = Get-Content $logFile | Select-String -Pattern "Mode:" | Select-Object -Last 1
    Write-Host "`nLatest execution mode: $modeEntry"
    ''')
    
    if result.std_out:
        print(result.std_out.decode())
    if result.std_err:
        print("Errors checking results:")
        print(result.std_err.decode())

if __name__ == "__main__":
    success = run_execute_mode()
    if success:
        print("\n" + "="*50)
        check_results()
    else:
        print("\n❌ Script execution failed")