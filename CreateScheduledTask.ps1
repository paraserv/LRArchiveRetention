# CreateScheduledTask.ps1
#requires -Version 5.1

<#
.SYNOPSIS
    Creates a scheduled task for the ArchiveRetention.ps1 script.

.DESCRIPTION
    Sets up automated execution of the LogRhythm Archive Retention script with
    flexible scheduling options and proper error handling.

.PARAMETER ScriptPath
    Path to the ArchiveRetention.ps1 script. Defaults to current directory.

.PARAMETER ArchivePath
    Path to archive directory (for local paths).

.PARAMETER CredentialTarget
    Name of saved credential target (for network shares).

.PARAMETER RetentionDays
    Number of days to retain files. Default: 365

.PARAMETER TaskName
    Name of the scheduled task. Default: "LogRhythm Archive Retention"

.PARAMETER ServiceAccount
    Service account to run the task. If not specified, runs as SYSTEM.

.PARAMETER Schedule
    Schedule type: Daily, Weekly, or Monthly. Default: Weekly

.PARAMETER StartTime
    Time to run the task. Default: 03:00

.PARAMETER DaysOfWeek
    Days of week for weekly schedule. Default: Sunday

.PARAMETER DayOfMonth
    Day of month for monthly schedule. Default: 1

.PARAMETER ParallelThreads
    Number of parallel threads for file processing. Default: 4

.PARAMETER ConfigFile
    Path to configuration file for the retention script.

.PARAMETER Description
    Custom description for the scheduled task.

.EXAMPLE
    .\CreateScheduledTask.ps1 -ArchivePath "D:\Archives" -RetentionDays 180
    Creates a weekly task running Sundays at 3 AM

.EXAMPLE
    .\CreateScheduledTask.ps1 -CredentialTarget "NAS_Archive" -Schedule Daily -StartTime "22:00"
    Creates a daily task for network share at 10 PM

.EXAMPLE
    .\CreateScheduledTask.ps1 -ArchivePath "E:\Logs" -Schedule Monthly -DayOfMonth 15 -ServiceAccount "DOMAIN\svc_archive"
    Creates a monthly task on the 15th running as service account

.NOTES
    Requires administrative privileges to create scheduled tasks
    Version: 2.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$true, ParameterSetName='LocalPath')]
    [string]$ArchivePath,
    
    [Parameter(Mandatory=$true, ParameterSetName='NetworkShare')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', 
        Justification='CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,
    
    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 365,
    
    [Parameter()]
    [string]$TaskName = "LogRhythm Archive Retention",
    
    [Parameter()]
    [string]$ServiceAccount,
    
    [Parameter()]
    [ValidateSet('Daily', 'Weekly', 'Monthly')]
    [string]$Schedule = 'Weekly',
    
    [Parameter()]
    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$StartTime = '03:00',
    
    [Parameter()]
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string[]]$DaysOfWeek = @('Sunday'),
    
    [Parameter()]
    [ValidateRange(1, 31)]
    [int]$DayOfMonth = 1,
    
    [Parameter()]
    [ValidateRange(1, 16)]
    [int]$ParallelThreads = 4,
    
    [Parameter()]
    [string]$ConfigFile,
    
    [Parameter()]
    [string]$Description
)

# Validate running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run as Administrator."
    exit 1
}

# Determine script path if not provided
if (-not $ScriptPath) {
    $ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "ArchiveRetention.ps1"
}

# Validate script exists
if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
    Write-Error "ArchiveRetention.ps1 not found at: $ScriptPath"
    exit 1
}

# Build PowerShell arguments
$scriptArgs = @()

if ($CredentialTarget) {
    $scriptArgs += "-CredentialTarget `"$CredentialTarget`""
    $pathInfo = "Network share via credential '$CredentialTarget'"
} else {
    $scriptArgs += "-ArchivePath `"$ArchivePath`""
    $pathInfo = "Local path: $ArchivePath"
}

$scriptArgs += "-RetentionDays $RetentionDays"
$scriptArgs += "-Execute"  # Always execute in scheduled task
$scriptArgs += "-ParallelThreads $ParallelThreads"

if ($ConfigFile) {
    $scriptArgs += "-ConfigFile `"$ConfigFile`""
}

# Build the full command
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $($scriptArgs -join ' ')"

# Display configuration
Write-Host "`nScheduled Task Configuration:" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Task Name:        $TaskName" -ForegroundColor White
Write-Host "Script Path:      $ScriptPath" -ForegroundColor White
Write-Host "Target:           $pathInfo" -ForegroundColor White
Write-Host "Retention Days:   $RetentionDays" -ForegroundColor White
Write-Host "Schedule:         $Schedule" -ForegroundColor White
Write-Host "Start Time:       $StartTime" -ForegroundColor White
if ($Schedule -eq 'Weekly') {
    Write-Host "Days of Week:     $($DaysOfWeek -join ', ')" -ForegroundColor White
} elseif ($Schedule -eq 'Monthly') {
    Write-Host "Day of Month:     $DayOfMonth" -ForegroundColor White
}
Write-Host "Parallel Threads: $ParallelThreads" -ForegroundColor White
if ($ServiceAccount) {
    Write-Host "Run As:           $ServiceAccount" -ForegroundColor White
} else {
    Write-Host "Run As:           SYSTEM" -ForegroundColor White
}

# Create scheduled task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
                                 -Argument $arguments `
                                 -WorkingDirectory (Split-Path $ScriptPath -Parent)

# Create trigger based on schedule type
switch ($Schedule) {
    'Daily' {
        $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
    }
    'Weekly' {
        # Convert day names to DayOfWeek enum values
        $dayEnums = $DaysOfWeek | ForEach-Object {
            [System.DayOfWeek]::Parse([System.DayOfWeek], $_, $true)
        }
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayEnums -At $StartTime
    }
    'Monthly' {
        # Create a monthly trigger using CIM instance
        $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
        # Modify to monthly after creation
    }
}

# Task settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12) `
    -Priority 7

# Create principal (user context)
if ($ServiceAccount) {
    Write-Host "`nConfiguring task to run as: $ServiceAccount" -ForegroundColor Yellow
    Write-Host "You will be prompted for the service account password." -ForegroundColor Yellow
    $principal = New-ScheduledTaskPrincipal -UserId $ServiceAccount `
                                           -LogonType Password `
                                           -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
                                           -LogonType ServiceAccount `
                                           -RunLevel Highest
}

# Build description
if (-not $Description) {
    $Description = "Automated LogRhythm Archive Retention - "
    $Description += "Deletes files older than $RetentionDays days from "
    if ($CredentialTarget) {
        $Description += "network share (credential: '$CredentialTarget')"
    } else {
        $Description += "'$ArchivePath'"
    }
    $Description += ". Runs $Schedule at $StartTime."
}

# Create the task
if ($PSCmdlet.ShouldProcess($TaskName, "Create scheduled task")) {
    try {
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Warning "Task '$TaskName' already exists. It will be replaced."
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Register the task
        Write-Host "`nCreating scheduled task..." -ForegroundColor Green
        $task = Register-ScheduledTask -TaskName $TaskName `
                                      -Action $action `
                                      -Trigger $trigger `
                                      -Settings $settings `
                                      -Principal $principal `
                                      -Description $Description `
                                      -Force
        
        # For monthly schedules, update the trigger
        if ($Schedule -eq 'Monthly') {
            # Get the task and modify trigger
            $task = Get-ScheduledTask -TaskName $TaskName
            $newTrigger = $task.Triggers[0]
            $newTrigger.Repetition = $null
            
            # Create monthly trigger using COM object
            $taskService = New-Object -ComObject Schedule.Service
            $taskService.Connect()
            $taskFolder = $taskService.GetFolder("\")
            $taskDef = $taskFolder.GetTask($TaskName).Definition
            
            $taskDef.Triggers.Clear()
            $monthlyTrigger = $taskDef.Triggers.Create(4) # 4 = Monthly
            $monthlyTrigger.StartBoundary = (Get-Date -Format "yyyy-MM-dd") + "T$StartTime`:00"
            $monthlyTrigger.DaysOfMonth = [Math]::Pow(2, $DayOfMonth - 1)
            $monthlyTrigger.Enabled = $true
            
            $taskFolder.RegisterTaskDefinition($TaskName, $taskDef, 4, $null, $null, 3) | Out-Null
        }
        
        Write-Host "Successfully created scheduled task: $TaskName" -ForegroundColor Green
        
        # Display task information
        $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
        $task = Get-ScheduledTask -TaskName $TaskName
        
        Write-Host "`n=== Task Summary ===" -ForegroundColor Cyan
        Write-Host "Task Name:     $($task.TaskName)" -ForegroundColor White
        Write-Host "State:         $($task.State)" -ForegroundColor White
        Write-Host "Next Run Time: $($taskInfo.NextRunTime)" -ForegroundColor White
        
        Write-Host "`n=== Command Details ===" -ForegroundColor Cyan
        Write-Host "Program:    $($action.Execute)" -ForegroundColor White
        Write-Host "Arguments:  $($action.Arguments)" -ForegroundColor White
        Write-Host "Directory:  $($action.WorkingDirectory)" -ForegroundColor White
        
        Write-Host "`nTask created successfully!" -ForegroundColor Green
        Write-Host "To test the task, run: " -NoNewline
        Write-Host "Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Yellow
        
        # Export task XML for backup
        $exportPath = Join-Path -Path $PSScriptRoot -ChildPath "ScheduledTasks"
        if (-not (Test-Path -Path $exportPath)) {
            New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
        }
        $xmlPath = Join-Path -Path $exportPath -ChildPath "$TaskName.xml"
        Export-ScheduledTask -TaskName $TaskName | Out-File -FilePath $xmlPath -Encoding UTF8
        Write-Host "`nTask definition exported to: $xmlPath" -ForegroundColor Gray
        
    } catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "`nWhat if: Would create scheduled task '$TaskName'" -ForegroundColor Yellow
    Write-Host "Command: PowerShell.exe $arguments" -ForegroundColor Gray
}

# End of script 