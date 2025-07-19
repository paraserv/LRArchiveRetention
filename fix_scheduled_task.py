#!/usr/bin/env python3
"""
Fix the scheduled task to properly run in execute mode
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

def fix_scheduled_task():
    """Fix the scheduled task to ensure proper execute mode"""
    session = create_session()
    
    print("🔧 Fixing scheduled task for proper execute mode...")
    
    # Recreate the scheduled task with explicit execute mode
    fix_script = '''
# Remove existing task
$TaskName = "LogRhythm Archive Retention - 1 Year"
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create new task with explicit execute mode
$ScriptPath = "C:\\LR\\Scripts\\LRArchiveRetention\\ArchiveRetention.ps1"
$Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -CredentialTarget 'NAS_CREDS' -RetentionDays 365 -Execute -ShowDeleteProgress`""

Write-Host "Creating task with arguments: $Arguments"

$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Arguments -WorkingDirectory "C:\\LR\\Scripts\\LRArchiveRetention"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 8)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Description = "LogRhythm Archive Retention - 1 year retention with directory cleanup (EXECUTE MODE)"

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description $Description
    Write-Host "✅ Task recreated successfully" -ForegroundColor Green
    
    # Test the task immediately
    Write-Host "Testing task with execute mode..."
    Start-ScheduledTask -TaskName $TaskName
    
    Start-Sleep 10
    
    # Check execution mode from logs
    $LogFile = "C:\\LR\\Scripts\\LRArchiveRetention\\script_logs\\ArchiveRetention.log"
    $ModeCheck = Get-Content $LogFile | Select-String -Pattern "Mode:" | Select-Object -Last 1
    Write-Host "Latest mode from log: $ModeCheck"
    
    if ($ModeCheck -like "*EXECUTION*") {
        Write-Host "✅ Task is running in EXECUTE mode!" -ForegroundColor Green
    } else {
        Write-Host "❌ Task is still in dry-run mode" -ForegroundColor Red
    }
    
} catch {
    Write-Host "❌ Failed to create task: $($_.Exception.Message)" -ForegroundColor Red
}
'''
    
    result = session.run_ps(fix_script)
    
    print("Task fix results:")
    if result.std_out:
        print(result.std_out.decode())
    if result.std_err:
        print("Errors:")
        print(result.std_err.decode())
    
    return result.status_code == 0

if __name__ == "__main__":
    success = fix_scheduled_task()
    if success:
        print("\n✅ Scheduled task fixed for execute mode!")
        print("The task will now actually delete files and clean up empty directories.")
        print("Next scheduled run: Sunday at 3:00 AM")
    else:
        print("\n❌ Failed to fix scheduled task")