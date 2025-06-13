# CreateScheduledTask.ps1
<#
.SYNOPSIS
    Creates a scheduled task for ArchiveRetention.ps1
.DESCRIPTION
    Sets up automated execution of the LogRhythm Archive Retention script
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ScriptPath = "C:\LogRhythm\Scripts\ArchiveV2\ArchiveRetention.ps1",
    
    [Parameter(Mandatory=$false)]
    [string]$ArchivePath,
    
    [Parameter(Mandatory=$false)]
    [string]$CredentialTarget,
    
    [Parameter(Mandatory=$false)]
    [int]$RetentionDays = 365,
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceAccount,
    
    [Parameter(Mandatory=$false)]
    [string]$TaskName = "LogRhythm Archive Retention",
    
    [Parameter(Mandatory=$false)]
    [string]$Schedule = "Daily",
    
    [Parameter(Mandatory=$false)]
    [string]$StartTime = "03:00"
)

# Validate parameters
if (-not $ArchivePath -and -not $CredentialTarget) {
    Write-Error "Either -ArchivePath or -CredentialTarget must be specified"
    exit 1
}

if ($ArchivePath -and $CredentialTarget) {
    Write-Error "Cannot specify both -ArchivePath and -CredentialTarget. Use one or the other."
    exit 1
}

# Build the PowerShell command
if ($CredentialTarget) {
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -CredentialTarget '$CredentialTarget' -RetentionDays $RetentionDays -Execute`""
    Write-Host "Setting up scheduled task with credential target: $CredentialTarget" -ForegroundColor Cyan
} else {
    # For UNC paths, we need to be careful with escaping - use double quotes around the path in the command
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$ScriptPath' -ArchivePath `"$ArchivePath`" -RetentionDays $RetentionDays -Execute`""
    Write-Host "Setting up scheduled task with archive path: $ArchivePath" -ForegroundColor Cyan
}

Write-Host "Task Name: $TaskName" -ForegroundColor Yellow
Write-Host "Retention Period: $RetentionDays days" -ForegroundColor Yellow
Write-Host "Schedule: $Schedule at $StartTime" -ForegroundColor Yellow

# Create the scheduled task action
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Arguments -WorkingDirectory (Split-Path $ScriptPath -Parent)

# Create the trigger (Weekly on Sunday at specified time)
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $StartTime

# Task settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 8)

# Principal (run as service account or SYSTEM)
if ($ServiceAccount) {
    Write-Host "Creating task to run as service account: $ServiceAccount" -ForegroundColor Yellow
    Write-Host "You will be prompted for the service account password." -ForegroundColor Yellow
    $Principal = New-ScheduledTaskPrincipal -UserId $ServiceAccount -LogonType Password
} else {
    Write-Host "Creating task to run as SYSTEM account" -ForegroundColor Yellow
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
}

# Create the task description
$Description = "Automated LogRhythm Archive Retention - Deletes files older than $RetentionDays days"
if ($CredentialTarget) {
    $Description += " (Network share: credential target '$CredentialTarget')"
} else {
    $Description += " (Path: '$ArchivePath')"
}

# Create the task
try {
    Write-Host "`nCreating scheduled task..." -ForegroundColor Green
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description $Description
    
    Write-Host "Successfully created scheduled task: $TaskName" -ForegroundColor Green
    Write-Host ""
    
    # Display task information
    $TaskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    $Task = Get-ScheduledTask -TaskName $TaskName
    
    Write-Host "=== Task Details ===" -ForegroundColor Cyan
    Write-Host "Task Name: $($Task.TaskName)" -ForegroundColor White
    Write-Host "State: $($Task.State)" -ForegroundColor White
    Write-Host "Next Run Time: $($TaskInfo.NextRunTime)" -ForegroundColor White
    Write-Host "Description: $($Task.Description)" -ForegroundColor White
    
    Write-Host "`n=== Command Details ===" -ForegroundColor Cyan
    Write-Host "Program: $($Action.Execute)" -ForegroundColor White
    Write-Host "Arguments: $($Action.Arguments)" -ForegroundColor White
    Write-Host "Working Directory: $($Action.WorkingDirectory)" -ForegroundColor White
    
    Write-Host "`nScheduled task created successfully!" -ForegroundColor Green
    Write-Host "You can test it by running: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    exit 1
} 