# Windows Scheduled Task Setup Guide

## Overview

This guide provides step-by-step instructions for setting up the LogRhythm ArchiveRetention.ps1 script as a Windows Scheduled Task for automated, unattended execution. This is the recommended approach for production environments.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Recommended Schedule](#recommended-schedule)
- [Setup Methods](#setup-methods)
- [Task Configuration](#task-configuration)
- [Security Considerations](#security-considerations)
- [Testing and Validation](#testing-and-validation)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Components
- **Windows Server** with Task Scheduler service running
- **ArchiveRetention.ps1** installed in secure location (e.g., `C:\LogRhythm\Scripts\ArchiveRetention\`)
- **PowerShell 5.1+** installed and execution policy configured
- **Service Account** with appropriate permissions (recommended) or use of SYSTEM account
- **Network Share Credentials** (if using UNC paths) pre-configured with `Save-Credential.ps1`

### Permissions Required
- **Read/Write** access to archive directories (local or network)
- **Read/Write** access to log directories
- **Execute** permissions on PowerShell and the script
- **Log on as a batch job** rights (for service accounts)

---

## Recommended Schedule

### Production Schedule
- **Frequency**: Weekly (recommended) or bi-weekly
- **Day**: Sunday (low activity day)
- **Time**: 2:00 AM (outside business hours)
- **Duration**: Allow 4-6 hours for completion on large datasets

### Considerations
- **Business Hours**: Always run during maintenance windows
- **Resource Usage**: Consider network and disk I/O impact
- **Backup Windows**: Ensure no conflicts with backup operations
- **LogRhythm Services**: Monitor for any impact on SIEM performance

---

## Setup Methods

### Method 1: PowerShell Script Creation (Recommended)

Create this PowerShell script to set up the scheduled task:

```powershell
# CreateScheduledTask.ps1
<#
.SYNOPSIS
    Creates a scheduled task for ArchiveRetention.ps1
.DESCRIPTION
    Sets up automated execution of the LogRhythm Archive Retention script
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath = "C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1",

    [Parameter(Mandatory=$true)]
    [string]$ArchivePath,

    [Parameter(Mandatory=$false)]
    [string]$CredentialTarget,

    [Parameter(Mandatory=$true)]
    [int]$RetentionDays = 365,

    [Parameter(Mandatory=$false)]
    [string]$ServiceAccount,

    [Parameter(Mandatory=$false)]
    [string]$TaskName = "LogRhythm Archive Retention",

    [Parameter(Mandatory=$false)]
    [string]$Schedule = "Weekly",

    [Parameter(Mandatory=$false)]
    [string]$StartTime = "02:00"
)

# Build the PowerShell command
if ($CredentialTarget) {
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -CredentialTarget '$CredentialTarget' -RetentionDays $RetentionDays -Execute`""
} else {
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -ArchivePath '$ArchivePath' -RetentionDays $RetentionDays -Execute`""
}

# Create the scheduled task action
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Arguments

# Create the trigger (Weekly on Sunday at 2:00 AM)
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $StartTime

# Task settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd

# Principal (run as service account or SYSTEM)
if ($ServiceAccount) {
    Write-Host "Creating task to run as service account: $ServiceAccount"
    Write-Host "You will be prompted for the service account password."
    $Principal = New-ScheduledTaskPrincipal -UserId $ServiceAccount -LogonType Password
} else {
    Write-Host "Creating task to run as SYSTEM account"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
}

# Create the task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Automated LogRhythm Archive Retention - Deletes files older than $RetentionDays days"
    Write-Host "Successfully created scheduled task: $TaskName" -ForegroundColor Green

    # Display task information
    Get-ScheduledTask -TaskName $TaskName | Format-List TaskName, State, LastRunTime, NextRunTime

} catch {
    Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    exit 1
}
```

#### Usage Examples:

**For Local Path:**
```powershell
.\CreateScheduledTask.ps1 -ScriptPath "C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1" -ArchivePath "D:\LogRhythm\Archives\Inactive" -RetentionDays 365
```

**For Network Share with Saved Credentials:**
```powershell
.\CreateScheduledTask.ps1 -ScriptPath "C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1" -CredentialTarget "NAS_PROD" -RetentionDays 365
```

**With Service Account:**
```powershell
.\CreateScheduledTask.ps1 -ScriptPath "C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1" -CredentialTarget "NAS_PROD" -RetentionDays 365 -ServiceAccount "DOMAIN\svc_lrarchive"
```

### Method 2: GUI Setup (Task Scheduler)

1. **Open Task Scheduler**
   - Run `taskschd.msc` or navigate via Administrative Tools

2. **Create Basic Task**
   - Right-click "Task Scheduler Library" > "Create Task"
   - Name: `LogRhythm Archive Retention`
   - Description: `Automated cleanup of LogRhythm archive files older than X days`

3. **Security Options**
   - Run whether user is logged on or not: ✓
   - Run with highest privileges: ✓
   - Configure for: Windows Server 2019/2022

4. **Triggers Tab**
   - New Trigger > Weekly
   - Start: Sunday at 2:00 AM
   - Recur every: 1 week

5. **Actions Tab**
   - Program: `PowerShell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -Command "& 'C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1' -CredentialTarget 'NAS_PROD' -RetentionDays 365 -Execute"`
   - Start in: `C:\LogRhythm\Scripts\ArchiveRetention\`

6. **Settings Tab**
   - Allow task to be run on demand: ✓
   - Run task as soon as possible after scheduled start is missed: ✓
   - Stop the task if it runs longer than: 8 hours
   - If the running task does not end when requested, force it to stop: ✓

---

## Task Configuration

### Recommended Settings

| Setting | Value | Reason |
|---------|-------|---------|
| **Run Level** | Highest privileges | Ensure file deletion permissions |
| **Run when user logged off** | Yes | Unattended operation |
| **Wake computer** | No | Avoid unexpected wake-ups |
| **Run only if network available** | Yes | Required for UNC paths |
| **Stop if idle ends** | No | Allow long-running operations |
| **Allow start on batteries** | Yes | Laptops/UPS scenarios |
| **Timeout** | 8 hours | Large datasets need time |
| **Restart on failure** | No | Review logs instead |

### Command Line Arguments

**Basic Template:**
```cmd
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1' -ArchivePath 'PATH' -RetentionDays DAYS -Execute"
```

**With Network Credentials:**
```cmd
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1' -CredentialTarget 'TARGET_NAME' -RetentionDays DAYS -Execute"
```

**With Custom Log Path:**
```cmd
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1' -CredentialTarget 'TARGET_NAME' -RetentionDays DAYS -Execute -LogPath 'C:\Logs\ArchiveRetention\retention.log'"
```

---

## Security Considerations

### Service Account Setup (Recommended)

1. **Create Dedicated Service Account**
   ```powershell
   # Domain environment
   New-ADUser -Name "svc_ArchiveRetention" -UserPrincipalName "svc_ArchiveRetention@domain.com" -AccountPassword (ConvertTo-SecureString "ComplexPassword123!" -AsPlainText -Force) -Enabled $true

   # Local account (if not domain-joined)
   New-LocalUser -Name "svc_ArchiveRetention" -Password (ConvertTo-SecureString "ComplexPassword123!" -AsPlainText -Force) -PasswordNeverExpires
   ```

2. **Grant Required Permissions**
   - **Archive directories**: Full Control
   - **Script directory**: Read & Execute
   - **Log directories**: Modify
   - **User Rights**: "Log on as a batch job"

3. **Configure Credential Storage**
   ```powershell
   # Run as the service account
   runas /user:DOMAIN\svc_ArchiveRetention powershell.exe
   # Then save network credentials
   .\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\nas.domain.com\archives"
   ```

### SYSTEM Account Alternative

If using SYSTEM account:
- **Pros**: No password management, high privileges
- **Cons**: Network access limitations, harder to audit
- **Network Access**: May require additional configuration for UNC paths

### Security Best Practices

- **Principle of Least Privilege**: Grant only necessary permissions
- **Regular Password Rotation**: Update service account passwords periodically
- **Audit Logging**: Enable detailed logging for compliance
- **Script Protection**: Secure script files against modification
- **Credential Protection**: Use encrypted credential storage only

---

## Testing and Validation

### Pre-Production Testing

1. **Manual Test Run**
   ```powershell
   # Test as the service account
   runas /user:DOMAIN\svc_ArchiveRetention powershell.exe
   cd "C:\LogRhythm\Scripts\ArchiveRetention"
   .\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 365 -Verbose
   ```

2. **Scheduled Task Test**
   ```powershell
   # Run the scheduled task immediately
   Start-ScheduledTask -TaskName "LogRhythm Archive Retention"

   # Monitor execution
   Get-ScheduledTask -TaskName "LogRhythm Archive Retention" | Get-ScheduledTaskInfo
   ```

3. **Log Verification**
   - Check `script_logs/ArchiveRetention.log` for execution details
   - Verify `retention_actions/retention_*.log` for deleted files audit trail
   - Review Windows Event Logs for task scheduler events

### Validation Checklist

- [ ] Task executes without errors
- [ ] Correct files are identified for deletion
- [ ] Minimum retention period is enforced (90+ days)
- [ ] Network connectivity works for UNC paths
- [ ] Logs are written correctly
- [ ] Empty directories are cleaned up
- [ ] Task completes within expected timeframe
- [ ] No impact on LogRhythm SIEM performance

---

## Monitoring and Maintenance

### Automated Monitoring

Create a monitoring script to check task status:

```powershell
# MonitorArchiveRetention.ps1
$TaskName = "LogRhythm Archive Retention"
$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($Task) {
    $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName

    Write-Host "=== Archive Retention Task Status ===" -ForegroundColor Cyan
    Write-Host "Task State: $($Task.State)" -ForegroundColor $(if($Task.State -eq 'Ready'){'Green'}else{'Yellow'})
    Write-Host "Last Run Time: $($TaskInfo.LastRunTime)"
    Write-Host "Last Result: $($TaskInfo.LastTaskResult)" -ForegroundColor $(if($TaskInfo.LastTaskResult -eq 0){'Green'}else{'Red'})
    Write-Host "Next Run Time: $($TaskInfo.NextRunTime)"

    # Check recent logs
    $LogPath = "C:\LogRhythm\Scripts\ArchiveRetention\script_logs\ArchiveRetention.log"
    if (Test-Path $LogPath) {
        $RecentLogs = Get-Content $LogPath -Tail 10
        Write-Host "`n=== Recent Log Entries ===" -ForegroundColor Cyan
        $RecentLogs | ForEach-Object { Write-Host $_ }
    }
} else {
    Write-Host "ERROR: Scheduled task '$TaskName' not found!" -ForegroundColor Red
}
```

### Key Metrics to Monitor

- **Task Execution Status**: Success/Failure
- **Execution Duration**: Track performance trends
- **Files Processed**: Count and size of deleted files
- **Error Rates**: Failed file deletions
- **Disk Space Freed**: Storage reclaimed
- **Network Connectivity**: UNC path accessibility

### Maintenance Tasks

**Monthly:**
- Review execution logs for errors or warnings
- Verify task schedule alignment with business needs
- Check disk space trends and retention effectiveness

**Quarterly:**
- Update service account passwords
- Review and test backup/restore procedures
- Validate retention policy compliance

**Annually:**
- Review and update retention periods
- Audit service account permissions
- Update documentation and procedures

---

## Troubleshooting

### Common Issues

| Issue | Symptoms | Solutions |
|-------|----------|-----------|
| **Task fails to start** | Task shows as "Running" but never completes | Check execution policy, script path, permissions |
| **Access denied errors** | Task runs but files aren't deleted | Verify service account permissions on target directories |
| **Network path not found** | UNC path access fails | Check network connectivity, DNS resolution, saved credentials |
| **Task timeout** | Task stops after configured timeout | Increase timeout, optimize script performance, reduce scope |
| **PowerShell execution policy** | Scripts blocked from running | Set execution policy: `Set-ExecutionPolicy RemoteSigned` |

### Diagnostic Commands

```powershell
# Check task status
Get-ScheduledTask -TaskName "LogRhythm Archive Retention" | Format-List

# View task history
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=201} | Where-Object {$_.Message -like "*LogRhythm Archive Retention*"} | Select-Object -First 5

# Test network connectivity
Test-NetConnection -ComputerName "nas.domain.com" -Port 445

# Test PowerShell execution
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'PowerShell execution test successful'"

# Check service account permissions
whoami /groups
```

### Log Analysis

**Key log files to monitor:**
- **Task Scheduler Logs**: `Event Viewer > Windows Logs > System`
- **Script Logs**: `C:\LogRhythm\Scripts\ArchiveRetention\script_logs\ArchiveRetention.log`
- **Retention Audit**: `C:\LogRhythm\Scripts\ArchiveRetention\retention_actions\retention_*.log`
- **PowerShell Logs**: `Event Viewer > Applications and Services Logs > Windows PowerShell`

**Critical error patterns to watch for:**
- "Access is denied"
- "The network path was not found"
- "Execution of scripts is disabled"
- "The system cannot find the file specified"

---

## Example Production Configuration

Here's a complete example for a production LogRhythm environment:

```powershell
# Production setup script
$Config = @{
    TaskName = "LogRhythm Archive Retention - Production"
    ScriptPath = "C:\LogRhythm\Scripts\ArchiveRetention\ArchiveRetention.ps1"
    CredentialTarget = "LR_NAS_PROD"
    RetentionDays = 1095  # 3 years
    ServiceAccount = "DOMAIN\svc_lrarchive"
    Schedule = "Daily"
    StartTime = "03:00"  # 1:00 AM Sunday
    LogPath = "D:\Logs\LogRhythm\ArchiveRetention\retention.log"
}

# Create the task
$Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$($Config.ScriptPath)' -CredentialTarget '$($Config.CredentialTarget)' -RetentionDays $($Config.RetentionDays) -Execute -LogPath '$($Config.LogPath)'`""

$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Arguments -WorkingDirectory "C:\LogRhythm\Scripts\ArchiveRetention"

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $Config.StartTime

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 8)

$Principal = New-ScheduledTaskPrincipal -UserId $Config.ServiceAccount -LogonType Password

Register-ScheduledTask -TaskName $Config.TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Production LogRhythm Archive Retention - 3 year retention policy"
```

---

## Additional Resources

- **LogRhythm Documentation**: [Data Processor Archive Configuration](https://docs.logrhythm.com/lrsiem/docs/change-archive-location)
- **Windows Task Scheduler**: [Microsoft Documentation](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
- **PowerShell Execution Policies**: [Microsoft Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)

---

**Author**: Nathan Church, Exabeam Professional Services
