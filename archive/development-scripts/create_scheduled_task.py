#!/usr/bin/env python3
"""
Create scheduled task on Windows server for Archive Retention
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

def create_scheduled_task():
    """Create the scheduled task for 1-year retention"""
    session = create_session()
    
    print("Creating scheduled task on Windows server...")
    
    # Create the entire task in one PowerShell command
    ps_command = '''
# Task parameters
$TaskName = "LogRhythm Archive Retention - 1 Year"
$ScriptPath = "C:\\LR\\Scripts\\LRArchiveRetention\\ArchiveRetention.ps1"
$CredentialTarget = "NAS_CREDS"
$RetentionDays = 365
$StartTime = "03:00"

Write-Host "Creating task: $TaskName" -ForegroundColor Cyan
Write-Host "Retention: $RetentionDays days (1 year)" -ForegroundColor Yellow

# Build command arguments
$Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -CredentialTarget '$CredentialTarget' -RetentionDays $RetentionDays -Execute -QuietMode`""

# Create task components
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Arguments -WorkingDirectory "C:\\LR\\Scripts\\LRArchiveRetention"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $StartTime
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 8)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Description = "Automated LogRhythm Archive Retention - 1 year retention policy"

# Remove existing task if present
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create the new task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description $Description
    Write-Host "✅ Successfully created scheduled task!" -ForegroundColor Green
    
    $Task = Get-ScheduledTask -TaskName $TaskName
    $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    
    Write-Host ""
    Write-Host "=== Task Details ===" -ForegroundColor Cyan
    Write-Host "Name: $($Task.TaskName)"
    Write-Host "State: $($Task.State)"
    Write-Host "Next Run: $($TaskInfo.NextRunTime)"
    Write-Host "Args: $Arguments"
    Write-Host "SUCCESS_MARKER"
}
catch {
    Write-Host "❌ Failed to create task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "FAILED_MARKER"
}
'''
    
    result = session.run_ps(ps_command)
    
    print("Task creation result:")
    if result.std_out:
        output = result.std_out.decode()
        print(output)
        success = "SUCCESS_MARKER" in output
    else:
        success = False
    
    if result.std_err:
        print("Errors:")
        print(result.std_err.decode())
    
    return success

def test_scheduled_task():
    """Test the scheduled task by running it immediately"""
    session = create_session()
    
    print("Testing the scheduled task...")
    
    # Run the scheduled task
    result = session.run_ps('Start-ScheduledTask -TaskName "LogRhythm Archive Retention - 1 Year"')
    
    if result.status_code == 0:
        print("✅ Scheduled task started successfully")
        
        # Wait a moment and check status
        import time
        time.sleep(3)
        
        status_result = session.run_ps('Get-ScheduledTask -TaskName "LogRhythm Archive Retention - 1 Year" | Get-ScheduledTaskInfo | Select-Object LastRunTime, LastTaskResult')
        print("Task status:")
        print(status_result.std_out.decode())
        
    else:
        print("❌ Failed to start scheduled task")
        if result.std_err:
            print("Error:", result.std_err.decode())

if __name__ == "__main__":
    success = create_scheduled_task()
    if success:
        print("\n" + "="*50)
        print("Scheduled task created successfully!")
        print("Testing the task...")
        test_scheduled_task()
    else:
        print("Failed to create scheduled task")