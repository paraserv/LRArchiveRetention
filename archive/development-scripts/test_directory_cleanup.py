#!/usr/bin/env python3
"""
Test directory cleanup functionality specifically
"""
import winrm
import subprocess
import time

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

def test_directory_cleanup():
    """Test directory cleanup with a focused test"""
    session = create_session()
    
    print("🔍 Testing directory cleanup functionality...")
    
    # Run the script with a much smaller scope to see directory cleanup in action
    # Using 30 days retention to process fewer files and reach directory cleanup faster
    test_script = '''
# Run with short retention to process quickly and reach directory cleanup
$LogFile = "C:\\temp\\test_cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-Host "Starting test with log file: $LogFile"

try {
    & "C:\\LR\\Scripts\\LRArchiveRetention\\ArchiveRetention.ps1" -CredentialTarget "NAS_CREDS" -RetentionDays 30 -Execute -ShowScanProgress -ShowDeleteProgress 2>&1 | Tee-Object -FilePath $LogFile
    
    Write-Host "`n=== CHECKING LOG FOR DIRECTORY CLEANUP ===" -ForegroundColor Cyan
    $Content = Get-Content $LogFile -Raw
    
    if ($Content -match "empty directory cleanup") {
        Write-Host "✅ Directory cleanup phase was executed!" -ForegroundColor Green
        $Content | Select-String -Pattern "directory.*cleanup|removed.*directory|empty.*director" | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "❌ Directory cleanup phase not found in logs" -ForegroundColor Red
    }
    
    if ($Content -match "SCRIPT COMPLETED SUCCESSFULLY") {
        Write-Host "✅ Script completed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Script did not complete successfully" -ForegroundColor Red
        Write-Host "Last 10 lines of log:"
        Get-Content $LogFile | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" }
    }
    
} catch {
    Write-Host "❌ Error running test: $($_.Exception.Message)" -ForegroundColor Red
}
'''
    
    print("Running directory cleanup test...")
    result = session.run_ps(test_script)
    
    print("Test Results:")
    if result.std_out:
        print(result.std_out.decode())
    if result.std_err:
        print("Errors:")
        print(result.std_err.decode())
    
    return result.status_code == 0

if __name__ == "__main__":
    success = test_directory_cleanup()
    if success:
        print("\n✅ Directory cleanup test completed")
    else:
        print("\n❌ Directory cleanup test failed")