<#
.SYNOPSIS
    Archive (delete) files older than a specified retention period.

.DESCRIPTION
    This script processes files in a specified directory (including subdirectories) and deletes files that are older than the specified retention period.

    For network shares, it uses a secure, two-step credential workflow. A separate helper script, Save-Credential.ps1, is used for the one-time interactive saving of a credential. The main script then uses this saved credential for non-interactive execution.

    Features:
    - Batch and robust deletion with retry logic
    - File type filtering (include/exclude)
    - Detailed logging and log rotation
    - Dry-run mode (default)
    - Progress and error reporting
    - Minimum retention safety

.PARAMETER ArchivePath
    Path to archive directory that needs to be processed.

.PARAMETER RetentionDays
    Number of days to retain files. Files older than this will be processed. (1-3650)

.PARAMETER Execute
    Actually perform the operations (default: dry-run). Without this, script runs in dry-run mode.

.PARAMETER LogPath
    Path to log file. Defaults to folder inside script directory.

.PARAMETER MaxRetries
    Maximum number of retries for failed operations. Default: 3

.PARAMETER RetryDelaySeconds
    Delay between retry attempts in seconds. Default: 1

.PARAMETER SkipDirCleanup
    If specified, skips the empty directory cleanup step after file processing. Default: cleanup is performed.

.PARAMETER IncludeFileTypes
    File types to include (e.g., '.lca', '.txt'). Defaults to '.lca'.

.PARAMETER CredentialTarget
    The name of a credential previously saved with the Save-Credential.ps1 helper script. When this is used, the script will connect to the network share associated with that credential, and the -ArchivePath parameter is not needed.

.PARAMETER ForceClearLock
    Force clear the lock file if no other ArchiveRetention processes are running. Use this when a previous run crashed and left an orphaned lock file.

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "\\server\share" -RetentionDays 90
    (Dry run: shows summary of what would be deleted)

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 365 -Execute
    (Actually deletes files older than 365 days)

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 365 -Verbose
    (Displays detailed logging, including every file that would be deleted; but in dry-run mode)

.EXAMPLE
    .\ArchiveRetention.ps1 -CredentialTarget "LR_NAS" -RetentionDays 180 -Execute
    (Connects to the network share associated with the 'LR_NAS' credential and deletes files older than 180 days.)

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 90 -ForceClearLock
    (Clears orphaned lock file if no other instances are running, then performs dry run)

.NOTES
    Requires PowerShell 5.1 or later
#>

# Script Parameters
[CmdletBinding(DefaultParameterSetName='LocalPath')]
param(
    # --- Parameter Set: LocalPath for local file processing ---
    [Parameter(Mandatory = $true, ParameterSetName = 'LocalPath', Position = 0, HelpMessage = "Path to the local archive directory to process.")]
    [string]$ArchivePath,

    # --- Parameter Set: NetworkShare for remote file processing ---
    [Parameter(Mandatory = $true, ParameterSetName = 'NetworkShare', HelpMessage = "The name of the saved credential to use for network access.")]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,

    # --- Common Parameters for both sets ---
    [Parameter(Mandatory = $true, ParameterSetName = 'LocalPath', Position = 1, HelpMessage = "Number of days to retain files.")]
    [Parameter(Mandatory = $true, ParameterSetName = 'NetworkShare', Position = 1, HelpMessage = "Number of days to retain files.")]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Actually perform file operations. Default is a dry-run.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Actually perform file operations. Default is a dry-run.")]
    [switch]$Execute,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Path to the log file.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Path to the log file.")]
    [string]$LogPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Maximum number of retries for failed operations.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Maximum number of retries for failed operations.")]
    [ValidateRange(0, 10)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Delay in seconds between retry attempts.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Delay in seconds between retry attempts.")]
    [ValidateRange(1, 300)]
    [int]$RetryDelaySeconds = 1,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Skip empty directory cleanup after file processing.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Skip empty directory cleanup after file processing.")]
    [switch]$SkipDirCleanup,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "File types to include (e.g., '.lca').")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "File types to include (e.g., '.lca').")]
    [string[]]$IncludeFileTypes = @('.lca'),

    # --- Progress and Performance Parameters ---
    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Disable all progress updates for scheduled tasks (optimizes performance).")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Disable all progress updates for scheduled tasks (optimizes performance).")]
    [switch]$QuietMode,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Show progress during file scanning phase.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Show progress during file scanning phase.")]
    [switch]$ShowScanProgress,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Show real-time deletion progress counters.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Show real-time deletion progress counters.")]
    [switch]$ShowDeleteProgress,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Progress update interval in seconds (default: 30, 0 = disable).")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Progress update interval in seconds (default: 30, 0 = disable).")]
    [ValidateRange(0, 300)]
    [int]$ProgressInterval = 30,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Number of files to process in each batch for better network performance (default: 500).")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Number of files to process in each batch for better network performance (default: 500).")]
    [ValidateRange(1, 5000)]
    [int]$BatchSize = 500,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Enable parallel file processing using runspaces.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Enable parallel file processing using runspaces.")]
    [switch]$ParallelProcessing,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Force sequential (single-threaded) processing.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Force sequential (single-threaded) processing.")]
    [switch]$Sequential,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Number of parallel threads for file operations (default: 8, max: 16).")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Number of parallel threads for file operations (default: 8, max: 16).")]
    [ValidateRange(1, 16)]
    [int]$ThreadCount = 8,

    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Force clear lock file if no other instances are running.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Force clear lock file if no other instances are running.")]
    [switch]$ForceClearLock,
    
    [Parameter(Mandatory = $false, ParameterSetName = 'LocalPath', HelpMessage = "Force kill all other ArchiveRetention processes and proceed.")]
    [Parameter(Mandatory = $false, ParameterSetName = 'NetworkShare', HelpMessage = "Force kill all other ArchiveRetention processes and proceed.")]
    [switch]$Force,

    # --- Help Parameter ---
    [Parameter(ParameterSetName = 'Help')]
    [switch]$Help
)

# Define Write-Log function before it's used
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [AllowEmptyString()]
        [string]$Message = " ",

        [Parameter(Position=1)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL', 'VERBOSE', 'SUCCESS')]
        [string]$Level = 'INFO',

        [switch]$NoConsoleOutput
    )

    # Handle empty, null, or whitespace-only messages
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    # Filter DEBUG/VERBOSE unless -Verbose is set
    if (($Level -eq 'DEBUG' -or $Level -eq 'VERBOSE') -and $VerbosePreference -ne 'Continue') {
        return
    }

    # Get current timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

    # Format the log message
    $logMessage = "$timestamp [$Level] - $Message"

    # Write to console if not suppressed
    if (-not $NoConsoleOutput) {
        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'INFO'    { Write-Host $logMessage -ForegroundColor White }
            'DEBUG'   { Write-Debug $logMessage }
            'FATAL'   { Write-Host $logMessage -BackgroundColor Red -ForegroundColor White }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            'VERBOSE' { if ($VerbosePreference -eq 'Continue') { Write-Host $logMessage -ForegroundColor Gray } }
            default   { Write-Host $logMessage }
        }
    }

    # Write to log file if path is set
    if (-not [string]::IsNullOrEmpty($script:LogFile)) {
        try {
            # Check if log rotation is needed (every 100 log entries to reduce overhead)
            if ($script:LogEntryCount -ge 100) {
                $script:LogEntryCount = 0
                Invoke-LogRotation -LogFile $script:LogFile -MaxLogSizeMB 10 -MaxLogFiles 10
            }
            # Append to log file using BOM-less StreamWriter
            $sw = New-Object System.IO.StreamWriter($script:LogFile, $true, ([System.Text.UTF8Encoding]::new($false)))
            $sw.WriteLine($logMessage)
            $sw.Close()
        } catch {
            # If we can't write to the log file, write to console and continue
            Write-Host "WARNING: Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Write to log file if writer is available
    if ($script:LogWriter -and -not $script:LogWriter.BaseStream.IsClosed) {
        try {
            $script:LogWriter.WriteLine($logMessage)
            $script:LogWriter.Flush()
        } catch {
            Write-Error "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

# Function to clean up script resources and finalize execution
function Complete-ScriptExecution {
    [CmdletBinding()]
    param(
        [bool]$Success = $false,
        [string]$Message = $null,
        [int]$FilesDeleted = 0,
        [int]$DirectoriesRemoved = 0,
        [double]$SpaceFreedGB = 0
    )

    $defaultSuccessMsg = "Script completed successfully"
    try {
        # Mark script as completed
        $script:completed = $true
        $script:endTime = Get-Date
        
        # Close deletion log writer first to allow summary to be appended
        if ($script:DeletionLogWriter) {
            try {
                if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                    $script:DeletionLogWriter.Flush()
                    $script:DeletionLogWriter.Close()
                    $script:DeletionLogWriter.Dispose()
                    $script:DeletionLogWriter = $null
                }
            } catch {
                Write-Log "Error closing deletion log writer in Complete-ScriptExecution: $($_.Exception.Message)" -Level WARNING
            }
        }

        # Calculate elapsed time
        $scriptCompleted = $script:endTime
        $elapsed = $script:endTime - $script:startTime
        $elapsedTimeStr = '{0:hh\:mm\:ss\.fff}' -f $elapsed

        # Stop and dispose the progress timer if it exists
        if ($null -ne $script:progressTimer) {
            try {
                $script:progressTimer.Stop()
                $script:progressTimer.Dispose()
                $script:progressTimer = $null
            } catch {
                Write-Log "Error disposing progress timer: $($_.Exception.Message)" -Level WARNING
            }
            # Clear any progress display
            try {
                Write-Progress -Activity "" -Completed -ErrorAction SilentlyContinue
            } catch {}
        }

        # Log completion status
        if ($script:terminated) {
            $localTime = $scriptCompleted.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $statusLine = "SCRIPT TERMINATED BY USER (local: $localTime, elapsed: $elapsedTimeStr)"
            Write-Log $statusLine -Level WARNING
            if (-not [string]::IsNullOrWhiteSpace($Message)) {
                Write-Log " - $Message" -Level WARNING
            }
        } elseif ($Success) {
            $localTime = $scriptCompleted.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $statusLine = "SCRIPT COMPLETED SUCCESSFULLY (local: $localTime, elapsed: $elapsedTimeStr)"
            Write-Log $statusLine -Level INFO
            if (-not [string]::IsNullOrWhiteSpace($Message) -and $Message -ne $defaultSuccessMsg) {
                Write-Log " - $Message" -Level INFO
            }
        } else {
            $localTime = $scriptCompleted.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $statusLine = "SCRIPT FAILED (local: $localTime, elapsed: $elapsedTimeStr)"
            Write-Log $statusLine -Level ERROR
            if (-not [string]::IsNullOrWhiteSpace($Message)) {
                Write-Log " - Reason: $Message" -Level ERROR
            }
        }
        
        # Write summary to retention action log if in execute mode
        if ($script:DeletionLogPath -and (Test-Path $script:DeletionLogPath)) {
            try {
                $completionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $summaryLines = @(
                    "",
                    "# Completion Summary",
                    "# Completed at: $completionTime",
                    "# Total files deleted: $FilesDeleted",
                    "# Total directories removed: $DirectoriesRemoved",
                    "# Total space freed: $SpaceFreedGB GB",
                    "# Total execution time: $elapsedTimeStr",
                    "# Status: $(if ($script:terminated) { 'TERMINATED' } elseif ($Success) { 'SUCCESS' } else { 'FAILED' })"
                )
                Add-Content -Path $script:DeletionLogPath -Value $summaryLines -Encoding UTF8
            } catch {
                Write-Log "Failed to write summary to retention log: $($_.Exception.Message)" -Level WARNING
            }
        }
    } catch {
        Write-Log "CRITICAL ERROR in Complete-ScriptExecution: $($_.Exception.Message)" -Level FATAL
    }
}

# Import credential helper module (only when needed)
# Module import moved to the credential handling section below

# Script version (read from VERSION file)
$SCRIPT_VERSION = if (Test-Path "$PSScriptRoot\VERSION") {
    (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
} else {
    "2.0.0"  # Fallback version
}

# Show help if no parameters are provided or -Help is used
if ($Help -or $MyInvocation.BoundParameters.Count -eq 0) {
    Get-Help $MyInvocation.MyCommand.Path
    exit
}

# Display help if no parameters are provided
if ($MyInvocation.BoundParameters.Count -eq 0) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit
}

# Set script preferences
$ConfirmPreference = 'None'  # Disable confirmation prompts
$ErrorActionPreference = 'Continue'  # Don't terminate on non-critical errors
$script:OriginalErrorActionPreference = $ErrorActionPreference  # Save for critical sections

# Set script start time for accurate timing in summary (local time only)
$script:startTime = Get-Date

# Initialize termination flag
$script:terminated = $false

# Initialize global counters for tracking progress
$script:totalFilesDeleted = 0
$script:totalDirsRemoved = 0
$script:totalSpaceFreed = 0

# Trap handler for Ctrl-C interruption
trap {
    $exceptionType = $_.Exception.GetType().Name
    $exceptionMessage = $_.Exception.Message
    
    # Check for various termination conditions
    if ($exceptionType -eq "PipelineStoppedException" -or 
        $exceptionType -eq "OperationCanceledException" -or
        $exceptionType -eq "ThreadAbortException" -or
        $exceptionMessage -match "pipeline.*stopped|cancelled|terminated|The pipeline has been stopped|The running command stopped|operation.*cancel" -or
        $_.CategoryInfo.Category -eq "OperationStopped") {
        
        Write-Host "`nScript execution interrupted by user (Ctrl+C)" -ForegroundColor Yellow
        Write-Log "Script execution interrupted by user (Ctrl+C) - Exception: $exceptionType" -Level WARNING
        $script:terminated = $true
        
        # Update script-level variables with current values
        if ($null -ne $successCount) { $script:totalFilesDeleted = $successCount }
        if ($null -ne $removedCount) { $script:totalDirsRemoved = $removedCount }
        if ($null -ne $processedSize) { $script:totalSpaceFreed = [math]::Round($processedSize / 1GB, 2) }
        
        # Close deletion log writer
        if ($script:DeletionLogWriter) {
            try {
                if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                    $script:DeletionLogWriter.Flush()
                    $script:DeletionLogWriter.Close()
                    $script:DeletionLogWriter.Dispose()
                    $script:DeletionLogWriter = $null
                }
            } catch {}
        }
        
        # Call completion with terminated flag
        Complete-ScriptExecution -Success $false -Message "Script terminated by user (Ctrl+C)" -FilesDeleted $script:totalFilesDeleted -DirectoriesRemoved $script:totalDirsRemoved -SpaceFreedGB $script:totalSpaceFreed
        exit 1
    }
    else {
        # Re-throw other exceptions
        throw $_
    }
}

# --- Start of Script ---

# Register Ctrl+C handler (only in interactive sessions)
if ([Environment]::UserInteractive -and $Host.UI.RawUI.KeyAvailable -ne $null) {
    try {
        $null = [console]::TreatControlCAsInput = $false
    } catch {
        # Ignore console errors in non-interactive sessions
    }
}

Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if (-not $script:completed) {
        $script:terminated = $true
        Write-Host "`nScript terminated by user" -ForegroundColor Yellow
    }
} | Out-Null

# -------------------------------------------------------------
# Single-instance lock (prevents concurrent executions)
# -------------------------------------------------------------
$script:LockFilePath = Join-Path -Path $env:TEMP -ChildPath "ArchiveRetention.lock"

function Test-StaleLock {
    param([string]$LockFilePath)

    if (-not (Test-Path $LockFilePath)) {
        return $false
    }

    try {
        $lockContent = Get-Content $LockFilePath -ErrorAction Stop
        if ($lockContent.Count -ge 1) {
            $lockPID = [int]$lockContent[0]
            # Check if process is still running
            if (Get-Process -Id $lockPID -ErrorAction SilentlyContinue) {
                return $false  # Process still running, lock is valid
            } else {
                Write-Log "Detected stale lock file from terminated process $lockPID. Removing..." -Level WARNING
                Remove-Item -Path $LockFilePath -Force -ErrorAction SilentlyContinue
                return $true   # Stale lock removed
            }
        }
    }
    catch {
        Write-Log "Lock file exists but couldn't read PID. Attempting to remove stale lock..." -Level WARNING
        Remove-Item -Path $LockFilePath -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}

# Handle Force parameter - kill other ArchiveRetention processes
if ($Force) {
    Write-Log "Force parameter specified. Checking for other ArchiveRetention processes..." -Level WARNING
    
    try {
        # Find all PowerShell processes running ArchiveRetention except current one
        $processesToKill = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop | 
            Where-Object { 
                $_.CommandLine -like "*ArchiveRetention.ps1*" -and 
                $_.ProcessId -ne $PID 
            }
        
        if ($processesToKill.Count -gt 0) {
            Write-Log "Found $($processesToKill.Count) ArchiveRetention process(es) to terminate:" -Level WARNING
            foreach ($proc in $processesToKill) {
                try {
                    Write-Log "  Terminating PID $($proc.ProcessId)..." -Level WARNING
                    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                    Write-Log "  Process $($proc.ProcessId) terminated." -Level SUCCESS
                } catch {
                    Write-Log "  Failed to terminate process $($proc.ProcessId): $_" -Level ERROR
                }
            }
            
            # Clean up any orphaned lock files
            if (Test-Path $script:LockFilePath) {
                Write-Log "Removing orphaned lock file..." -Level WARNING
                Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
                Write-Log "Lock file removed." -Level SUCCESS
            }
            
            # Brief pause to ensure processes are terminated
            Start-Sleep -Milliseconds 1000
        } else {
            Write-Log "No other ArchiveRetention processes found." -Level INFO
            
            # Still remove lock file if it exists
            if (Test-Path $script:LockFilePath) {
                Write-Log "Removing orphaned lock file..." -Level WARNING
                Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
                Write-Log "Lock file removed." -Level SUCCESS
            }
        }
    } catch {
        Write-Log "Error checking for processes: $_" -Level WARNING
        # Continue anyway with Force - just remove the lock
        if (Test-Path $script:LockFilePath) {
            Write-Log "Removing lock file (force mode)..." -Level WARNING
            Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
            Write-Log "Lock file removed." -Level SUCCESS
        }
    }
}

# Handle ForceClearLock parameter
if ($ForceClearLock) {
    Write-Log "ForceClearLock specified. Checking for orphaned lock file..." -Level INFO
    if (Test-Path $script:LockFilePath) {
        # Check if any ArchiveRetention process is actually running
        $runningProcesses = @()
        try {
            $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
            $runningProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | 
                Where-Object { $_.CommandLine -like "*$scriptName*" -and $_.ProcessId -ne $PID }
        } catch {
            # Fallback to Get-Process if CIM fails
            try {
                $runningProcesses = Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Id -ne $PID }
            } catch {
                Write-Log "Could not check for running processes: $_" -Level WARNING
            }
        }
        
        if ($runningProcesses.Count -eq 0) {
            Write-Log "No other ArchiveRetention processes found. Removing orphaned lock file..." -Level WARNING
            Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
            Write-Log "Orphaned lock file removed." -Level SUCCESS
            # Give the file system a moment to release the file
            Start-Sleep -Milliseconds 500
        } else {
            Write-Log "Found $($runningProcesses.Count) PowerShell process(es) that might be running ArchiveRetention:" -Level WARNING
            foreach ($proc in $runningProcesses) {
                $cmdLine = if ($proc.CommandLine) { 
                    $truncated = if ($proc.CommandLine.Length -gt 100) { 
                        $proc.CommandLine.Substring(0, 100) + "..." 
                    } else { 
                        $proc.CommandLine 
                    }
                    $truncated
                } else { 
                    "(command line not available)" 
                }
                Write-Log "  PID $($proc.ProcessId): $cmdLine" -Level INFO
            }
            
            # Check if lock file contains current PID
            if (Test-Path $script:LockFilePath) {
                try {
                    $lockContent = Get-Content $script:LockFilePath -Raw
                    if ($lockContent -match '(\d+)') {
                        $lockPID = [int]$matches[1]
                        Write-Log "Lock file contains PID: $lockPID" -Level INFO
                        
                        # Check if that specific process exists
                        $lockProcess = Get-Process -Id $lockPID -ErrorAction SilentlyContinue
                        if (-not $lockProcess) {
                            Write-Log "Process $lockPID from lock file is not running. Lock file is stale." -Level WARNING
                            Write-Log "Removing stale lock file..." -Level WARNING
                            Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
                            Write-Log "Stale lock file removed." -Level SUCCESS
                            Start-Sleep -Milliseconds 500  # Give file system time to release
                            return  # Don't exit, continue with script
                        }
                    }
                } catch {
                    Write-Log "Error reading lock file: $_" -Level WARNING
                }
            }
            
            Write-Log "Cannot force clear lock - other PowerShell processes are running." -Level ERROR
            Write-Log "Use Task Manager to end orphaned PowerShell processes if needed." -Level INFO
            exit 9
        }
    } else {
        Write-Log "No lock file found. Proceeding normally." -Level INFO
    }
}

# Check for and clean up stale locks first (skip if ForceClearLock or Force already handled it)
if (-not $ForceClearLock -and -not $Force) {
    try {
        Test-StaleLock -LockFilePath $script:LockFilePath | Out-Null
    } catch {
        Write-Log "Error checking stale locks: $_" -Level WARNING
    }
}

# Also check for running ArchiveRetention processes (skip if Force was used)
if (-not $Force) {
    try {
        $runningProcesses = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { 
            $_.CommandLine -like "*ArchiveRetention.ps1*" -and $_.ProcessId -ne $PID 
        }
    } catch {
        # Fallback if CIM fails - just check with Get-Process
        Write-Log "Could not check for running processes via CIM. Using basic process check." -Level DEBUG
        $runningProcesses = @()
        # Simple check for other PowerShell processes with our script name
        $psProcesses = Get-Process -Name powershell* -ErrorAction SilentlyContinue
        if ($psProcesses) {
            foreach ($proc in $psProcesses) {
                if ($proc.Id -ne $PID) {
                    try {
                        $cmd = $proc.CommandLine
                        if ($cmd -like "*ArchiveRetention.ps1*") {
                            $runningProcesses += $proc
                        }
                    } catch {
                        # Can't access CommandLine, skip this process
                    }
                }
            }
        }
    }
    
    if ($runningProcesses) {
        Write-Log "Found existing ArchiveRetention.ps1 process(es) running:" -Level WARNING
        foreach ($proc in $runningProcesses) {
            Write-Log "  PID: $($proc.ProcessId), Command: $($proc.CommandLine -replace '^(.{100}).*', '$1...')" -Level WARNING
        }
        Write-Log "Another instance appears to be running. Exiting to prevent conflicts." -Level FATAL
        exit 9
    }
}

try {
    $script:LockFileStream = [System.IO.FileStream]::new(
        $script:LockFilePath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
    # Record PID and timestamp for diagnostics
    $pidInfo = [System.Text.Encoding]::UTF8.GetBytes("$PID`n$(Get-Date)")
    $script:LockFileStream.SetLength(0)
    $script:LockFileStream.Write($pidInfo, 0, $pidInfo.Length)
    $script:LockFileStream.Flush()
    Write-Log "Acquired single-instance lock ($script:LockFilePath)" -Level DEBUG
}
catch [System.IO.IOException] {
    Write-Log "Lock file is in use. Checking for stale lock..." -Level DEBUG
    # Try once more after stale lock cleanup
    Start-Sleep -Milliseconds 500
    
    $staleLockRemoved = $false
    try {
        $staleLockRemoved = Test-StaleLock -LockFilePath $script:LockFilePath
    } catch {
        Write-Log "Error during stale lock check: $_" -Level WARNING
    }
    
    if ($staleLockRemoved) {
        Start-Sleep -Milliseconds 500  # Extra delay after removal
        try {
            $script:LockFileStream = [System.IO.FileStream]::new(
                $script:LockFilePath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            $pidInfo = [System.Text.Encoding]::UTF8.GetBytes("$PID`n$(Get-Date)")
            $script:LockFileStream.SetLength(0)
            $script:LockFileStream.Write($pidInfo, 0, $pidInfo.Length)
            $script:LockFileStream.Flush()
            Write-Log "Acquired single-instance lock after stale lock cleanup ($script:LockFilePath)" -Level DEBUG
        }
        catch {
            Write-Log "Failed to acquire lock even after cleanup: $($_.Exception.Message)" -Level ERROR
            Write-Log "Another instance may be starting. Try again in a few seconds or use -ForceClearLock." -Level FATAL
            exit 9
        }
    } else {
        Write-Log "Lock file is actively in use by another process." -Level ERROR
        Write-Log "Use -ForceClearLock if you're sure no other instance is running." -Level FATAL
        exit 9
    }
}

$tempDriveName = $null

# Handle network credentials if a target is specified
if (-not [string]::IsNullOrEmpty($CredentialTarget)) {
    # Import credential helper module (only when using network credentials)
    try {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules/ShareCredentialHelper.psm1'
        Import-Module -Name $modulePath -Force
        Write-Log "Imported ShareCredentialHelper module for network credentials." -Level DEBUG
    }
    catch {
        $errorMsg = "Failed to import ShareCredentialHelper module from '$modulePath'. Ensure it is in the 'modules' subdirectory. Error: $($_.Exception.Message)"
        Write-Log $errorMsg -Level FATAL
        Write-Error $errorMsg
        exit 1
    }

    Write-Log "CredentialTarget '$CredentialTarget' specified. Attempting to map network drive." -Level INFO
    try {
        $credentialInfo = $null
        try {
            $credentialInfo = Get-ShareCredential -Target $CredentialTarget
        }
        catch {
            # Check if it's a decryption error
            if ($_.Exception.Message -like "*machine-bound*" -or $_.Exception.Message -like "*Padding is invalid*") {
                Write-Log "Credential decryption failed - credential was saved under a different user or machine context" -Level ERROR
                Write-Log "Current user: $([System.Environment]::UserDomainName)\$([System.Environment]::UserName)" -Level INFO
                Write-Log "To fix this issue, either:" -Level INFO
                Write-Log "  1. Re-save the credential: .\Save-Credential.ps1 -Target '$CredentialTarget' -SharePath '\\server\share' -UserName 'username'" -Level INFO
                Write-Log "  2. Run the script as the user who originally saved the credential" -Level INFO
                Write-Log "  3. Use WinRM: python3 tools/winrm_helper.py nas_execute <days>" -Level INFO
                $errorMsg = "Cannot decrypt credential '$CredentialTarget' - it was saved under a different security context"
            } else {
                $errorMsg = "Failed to retrieve credential '$CredentialTarget': $($_.Exception.Message)"
            }
            Write-Log $errorMsg -Level FATAL
            
            # Close deletion log writer before exit
            if ($script:DeletionLogWriter) {
                try {
                    if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                        $script:DeletionLogWriter.Flush()
                        $script:DeletionLogWriter.Close()
                        $script:DeletionLogWriter.Dispose()
                        $script:DeletionLogWriter = $null
                    }
                } catch {
                    Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
                }
            }
            
            Complete-ScriptExecution -Success $false -Message $errorMsg
            exit 1
        }

        if ($null -eq $credentialInfo) {
            $errorMsg = "Failed to retrieve saved credential for target '$CredentialTarget'. Please run Save-Credential.ps1 first."
            Write-Log $errorMsg -Level FATAL
            
            # Close deletion log writer before completion to allow summary to be written
            if ($script:DeletionLogWriter) {
                try {
                    if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                        $script:DeletionLogWriter.Flush()
                        $script:DeletionLogWriter.Close()
                        $script:DeletionLogWriter.Dispose()
                        $script:DeletionLogWriter = $null
                    }
                } catch {
                    Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
                }
            }
            
            Complete-ScriptExecution -Success $false -Message $errorMsg
            exit 1
        }

        # Create a temporary PSDrive
        $tempDriveName = "ArchiveMount" # A fixed but temporary name
        $ArchivePath = $credentialInfo.SharePath
        New-PSDrive -Name $tempDriveName -PSProvider FileSystem -Root $credentialInfo.SharePath -Credential $credentialInfo.Credential -ErrorAction Stop
        $ArchivePath = (Get-PSDrive $tempDriveName).Root

    } catch {
        $errorMsg = "Failed to map network drive using credential '$CredentialTarget'. Error: $($_.Exception.Message)"
        Write-Log $errorMsg -Level FATAL
        
        # Close deletion log writer before completion to allow summary to be written
        if ($script:DeletionLogWriter) {
            try {
                if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                    $script:DeletionLogWriter.Flush()
                    $script:DeletionLogWriter.Close()
                    $script:DeletionLogWriter.Dispose()
                    $script:DeletionLogWriter = $null
                }
            } catch {
                Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
            }
        }
        
        Complete-ScriptExecution -Success $false -Message $errorMsg -FilesDeleted 0 -DirectoriesRemoved 0 -SpaceFreedGB 0
        exit 1
    }
}

# Set up script log directory
$scriptLogsDir = Join-Path -Path $PSScriptRoot -ChildPath "script_logs"
if (-not (Test-Path -Path $scriptLogsDir)) {
    New-Item -ItemType Directory -Path $scriptLogsDir -Force | Out-Null
}

# Set up logging
if ([string]::IsNullOrEmpty($LogPath)) {
    $script:LogFile = Join-Path -Path $scriptLogsDir -ChildPath "ArchiveRetention.log"
} else {
    $script:LogFile = $LogPath
}

$script:MaxLogSizeMB = 10
$script:MaxLogFiles = 10

# Ensure log directory exists
$logDir = Split-Path -Path $script:LogFile -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$script:LogLevel = 'INFO'  # Default log level
$script:LogWriter = $null
$script:DeletionLogPath = $null
$script:DeletionLogWriter = $null
$script:LogEntryCount = -1

# Define Write-Log function before it's used
# (Implementation is at the beginning of the script)

# Set up retention actions log if in execute mode
if ($Execute) {
    $retentionLogsDir = Join-Path -Path (Split-Path $MyInvocation.MyCommand.Path) -ChildPath 'retention_actions'

    # Create retention_actions directory if it doesn't exist
    if (-not (Test-Path -Path $retentionLogsDir)) {
        try {
            New-Item -ItemType Directory -Path $retentionLogsDir -Force | Out-Null
            Write-Log "Created retention actions directory: $retentionLogsDir" -Level INFO
        } catch {
            Write-Error "Failed to create retention actions directory: $($_.Exception.Message)"
            throw
        }
    }

    # Create timestamped log file
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:DeletionLogPath = Join-Path -Path $retentionLogsDir -ChildPath "retention_${timestamp}.log"

    try {
        # Initialize the log file with header information
        $script:DeletionLogWriter = [System.IO.StreamWriter]::new($script:DeletionLogPath, $false, [System.Text.UTF8Encoding]::new($false))
        $script:DeletionLogWriter.WriteLine("# Retention Action Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $script:DeletionLogWriter.WriteLine("# Script: $($MyInvocation.MyCommand.Name)")
        $script:DeletionLogWriter.WriteLine("# Archive Path: $ArchivePath")
        $script:DeletionLogWriter.WriteLine("# Retention Days: $RetentionDays")
        $script:DeletionLogWriter.WriteLine("# Mode: $($PSCmdlet.ParameterSetName)")
        $script:DeletionLogWriter.WriteLine("# Generated by: $env:USERDOMAIN\$env:USERNAME")
        $script:DeletionLogWriter.WriteLine("")
        $script:DeletionLogWriter.Flush()

        Write-Log "Retention actions will be logged to: $($script:DeletionLogPath)" -Level INFO
    } catch {
        $errorMsg = "Failed to initialize retention action log: $($_.Exception.Message)"
        Write-Error $errorMsg
        Write-Log $errorMsg -Level ERROR
    }

    # Note: Consider implementing log rotation/archiving for retention_actions directory
    # if the number of log files becomes excessive in the future
}

# Set log level based on Verbose switch
if ($VerbosePreference -eq 'Continue') {
    $script:LogLevel = 'DEBUG'
}

# Register script termination handler
try {
    # Register handler for script termination
    $null = Register-EngineEvent -SourceIdentifier 'PowerShell.Exiting' -Action {
        try {
            if ($script:LogWriter) {
                Write-Log "Script is terminating. Performing cleanup..." -Level INFO -NoConsoleOutput
                Close-Logging
            }
        } catch {
            # Suppress any errors during cleanup
        }
    }
} catch {
    Write-Warning "Failed to register PowerShell.Exiting event handler: $($_.Exception.Message)"
}

# Initialize logging
function Initialize-Logging {
    [CmdletBinding()]
    param(
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 10
    )

    try {
        # Ensure log directory exists
        $logDir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            Write-Log "Created log directory: $logDir" -Level INFO
        }

        # If log file exists, rename it with a timestamp before creating a new one
        if (Test-Path -Path $script:LogFile) {
            $logItem = Get-Item -Path $script:LogFile
            $timestamp = $logItem.LastWriteTime.ToString('yyyyMMdd_HHmmss')
            $logName = [System.IO.Path]::GetFileNameWithoutExtension($script:LogFile)
            $logExt = [System.IO.Path]::GetExtension($script:LogFile)
            $logDir = Split-Path -Path $script:LogFile -Parent
            $archivedLog = Join-Path $logDir ("${logName}_$timestamp$logExt")
            try {
                Move-Item -Path $script:LogFile -Destination $archivedLog -Force
                Write-Host "Previous log archived as: $archivedLog" -ForegroundColor Yellow
            } catch {
                Write-Host "WARNING: Could not archive previous log: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Close and clean up any existing writer
        if ($null -ne $script:LogWriter) {
            try {
                $script:LogWriter.Dispose()
            } catch {
                Write-Host "WARNING: Error disposing previous log writer: $($_.Exception.Message)" -ForegroundColor Yellow
            } finally {
                $script:LogWriter = $null
            }
        }

        # Check if we need to rotate the log file
        if (Test-Path -Path $script:LogFile) {
            $logSize = (Get-Item -Path $script:LogFile -ErrorAction SilentlyContinue).Length / 1MB
            if ($logSize -gt $MaxLogSizeMB) {
                Invoke-LogRotation -LogFile $script:LogFile -MaxLogSizeMB $MaxLogSizeMB -MaxLogFiles $MaxLogFiles
            }
        }

        # Create or clear the log file (empty, BOM-less)
        $sw = New-Object System.IO.StreamWriter($script:LogFile, $false, ([System.Text.UTF8Encoding]::new($false)))
        $sw.Close()
        Write-Host "Logging initialized. Log file: $($script:LogFile)" -ForegroundColor Green
        # Initialize log entry counter
        $script:LogEntryCount = 0
    }
    catch {
        $errorMsg = "Logging initialization failed: $($_.Exception.Message)"
        Write-Error $errorMsg -ErrorAction Continue
        throw $errorMsg
    }
}

function Close-Logging {
    # Close main log
    if ($script:LogWriter) {
        try {
            if (-not $script:LogWriter.BaseStream.IsClosed) {
                $script:LogWriter.Flush()
                $script:LogWriter.Close()
            }
        }
        catch {
            Write-Error "Error closing main log writer: $($_.Exception.Message)"
        }
        finally {
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
        }
    }

    # Close deletion log
    if ($script:DeletionLogPath) {
        try {
            # Only close if still open
            if ($script:DeletionLogWriter -and -not $script:DeletionLogWriter.BaseStream.IsClosed) {
                $script:DeletionLogWriter.Flush()
                $script:DeletionLogWriter.Close()
                $script:DeletionLogWriter.Dispose()
                $script:DeletionLogWriter = $null
            }
            # Check if we should add a "no files" message
            if (Test-Path $script:DeletionLogPath) {
                $lines = Get-Content -Path $script:DeletionLogPath
                if ($lines.Count -le 7) {  # Only header present
                    Add-Content -Path $script:DeletionLogPath -Value "# No files were deleted or processed during this run."
                }
            }
        } catch {
            Write-Log "Error in Close-Logging deletion log handling: $($_.Exception.Message)" -Level WARNING
        }
    }
}

# Function to convert bytes to human readable format
function Format-FileSize {
    param ([long]$Size)
    $sizes = 'B','KB','MB','GB','TB'
    $index = 0
    while ($Size -ge 1KB -and $index -lt ($sizes.Count - 1)) {
        $Size = $Size / 1KB
        $index++
    }
    return "{0:N2} {1}" -f $Size, $sizes[$index]
}

# Simple log rotation function without keeping file handles open
function Invoke-LogRotation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogFile,
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 10,
        [switch]$IsRetentionLog
    )

    try {
        # Check if log file exists and get its size
        if (Test-Path -Path $LogFile) {
            $logItem = Get-Item -Path $LogFile -ErrorAction SilentlyContinue
            if (-not $logItem) { return }

            $logSize = $logItem.Length / 1MB

            # Rotate if file is larger than max size
            if ($logSize -gt $MaxLogSizeMB) {
                Write-Host "Rotating log file (Size: $('{0:N2}' -f $logSize) MB)" -ForegroundColor Yellow

                # Generate timestamp for rotated log
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $logDir = Split-Path -Path $LogFile -Parent
                $logName = [System.IO.Path]::GetFileNameWithoutExtension($LogFile)
                $logExt = [System.IO.Path]::GetExtension($LogFile)

                # In Invoke-LogRotation, update rotatedLogsDir for script logs
                if ($logDir -like '*script_logs') {
                    $rotatedLogsDir = Join-Path -Path $logDir -ChildPath "rotated_logs"
                } else {
                    $rotatedLogsDir = Join-Path -Path $logDir -ChildPath "rotated_logs"
                }

                # Generate a unique name for the rotated log
                $rotatedLogPath = Join-Path -Path $rotatedLogsDir -ChildPath "${logName}_${timestamp}${logExt}"
                $counter = 1
                while (Test-Path $rotatedLogPath) {
                    $rotatedLogPath = Join-Path -Path $rotatedLogsDir -ChildPath "${logName}_${timestamp}_${counter}${logExt}"
                    $counter++
                }

                # Try to move the current log file
                try {
                    Move-Item -Path $LogFile -Destination $rotatedLogPath -Force -ErrorAction Stop
                    Write-Host "Rotated log to: $rotatedLogPath" -ForegroundColor Green

                    # Clean up old log files
                    try {
                        $logFiles = Get-ChildItem -Path $rotatedLogsDir -Filter "${logName}_*${logExt}*" |
                                    Sort-Object LastWriteTime -Descending

                        if ($logFiles.Count -gt $MaxLogFiles) {
                            $filesToDelete = $logFiles | Select-Object -Skip $MaxLogFiles
                            foreach ($file in $filesToDelete) {
                                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                            }
                            Write-Host "Cleaned up $($filesToDelete.Count) old log files" -ForegroundColor Gray
                        }
                    } catch {
                        Write-Host "Failed to clean up old log files: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Failed to rotate log file: $LogFile - $($_.Exception.Message)" -ForegroundColor Red
                    # Try to continue with the existing log file
                }
            }
        }
    } catch {
        Write-Host "ERROR in log rotation: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        # Don't rethrow to prevent script failure due to logging issues
    }
}

# Function to compress log files into zip archives
function Compress-LogFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [switch]$DeleteOriginal = $false
    )

    try {
        # Check if file exists
        if (-not (Test-Path -Path $FilePath)) {
            Write-Log "File not found: $FilePath" -Level WARNING
            return $false
        }

        $file = Get-Item -Path $FilePath -ErrorAction Stop
        $zipPath = "$($file.FullName).zip"

        # Skip if zip already exists and is newer than the log file
        if (Test-Path -Path $zipPath) {
            $zipFile = Get-Item -Path $zipPath
            if ($zipFile.LastWriteTime -ge $file.LastWriteTime) {
                Write-Log "Skipping compression - zip file is up to date: $zipPath" -Level DEBUG
                if ($DeleteOriginal) {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                }
                return $true
            }
        }

        # Create a temporary zip file
        $tempZip = [System.IO.Path]::GetTempFileName()
        Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
        $tempZip = "$tempZip.zip"

        try {
            # Load the compression assembly
            Add-Type -AssemblyName System.IO.Compression.FileSystem

            # Create a new zip archive
            $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            $zipArchive = [System.IO.Compression.ZipFile]::Open($tempZip, [System.IO.Compression.ZipArchiveMode]::Create)

            try {
                # Add the file to the archive
                $entryName = [System.IO.Path]::GetFileName($file.FullName)
                $entry = $zipArchive.CreateEntry($entryName, $compressionLevel)

                # Copy file contents to the zip entry
                $sourceStream = [System.IO.File]::OpenRead($file.FullName)
                $targetStream = $entry.Open()

                try {
                    $sourceStream.CopyTo($targetStream)
                } finally {
                    $sourceStream.Dispose()
                    $targetStream.Dispose()
                }

            } finally {
                $zipArchive.Dispose()
            }

            # Move the temp zip to final location
            Move-Item -Path $tempZip -Destination $zipPath -Force -ErrorAction Stop

            # Set the last write time to match the original file
            (Get-Item $zipPath).LastWriteTime = $file.LastWriteTime

            Write-Log "Successfully compressed log file: $FilePath -> $zipPath" -Level DEBUG

            # Delete original if requested
            if ($DeleteOriginal) {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Log "Removed original log file: $FilePath" -Level DEBUG
            }

            return $true

        } catch {
            # Clean up temp file if it exists
            if (Test-Path -Path $tempZip) {
                Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
            }
            throw
        }

    } catch {
        Write-Log "Failed to compress log file: $FilePath - $($_.Exception.Message)" -Level WARNING
        Write-Log $_.ScriptStackTrace -Level DEBUG
        return $false
    }
}

# Function to get elapsed time in readable format
function Get-ElapsedTime {
    param ([DateTime]$StartTime)
    $elapsed = (Get-Date) - $StartTime
    return "{0:hh\:mm\:ss}" -f $elapsed
}

# Function to get processing rate
function Get-ProcessingRate {
    param (
        [DateTime]$StartTime,
        [int]$ProcessedCount
    )
    $elapsed = (Get-Date) - $StartTime
    if ($elapsed.TotalSeconds -gt 0) {
        $rate = $ProcessedCount / $elapsed.TotalSeconds
        return "$([math]::Round($rate, 1)) items/sec"
    }
    return "0 items/sec"
}

# Function to get estimated time remaining
function Get-EstimatedTimeRemaining {
    param (
        [DateTime]$StartTime,
        [int]$ProcessedCount,
        [int]$TotalCount
    )
    if ($ProcessedCount -eq 0) { return "Calculating..." }

    $elapsed = (Get-Date) - $StartTime
    $itemsRemaining = $TotalCount - $ProcessedCount
    $secondsPerItem = $elapsed.TotalSeconds / $ProcessedCount
    $secondsRemaining = $itemsRemaining * $secondsPerItem

    return "$([math]::Round($secondsRemaining / 60, 1)) minutes"
}

# Function to sanitize and normalize path
function Get-NormalizedPath {
    param (
        [string]$Path
    )

    try {
        # Convert to .NET path format
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.TrimEnd('\', '/'))

        # Handle UNC paths specifically
        if ($normalizedPath -match '^\\\\\w+\\.*') {
            # Ensure UNC format is preserved
            if (-not $normalizedPath.StartsWith('\\')) {
                $normalizedPath = '\\' + $normalizedPath.TrimStart('\')
            }
        }

        return $normalizedPath
    }
    catch {
        Write-Log "Warning: Error normalizing path: $Path - $($_.Exception.Message)" -Level WARNING
        return $Path
    }
}

# Function to safely get file date
function Test-FileDate {
    param (
        [System.IO.FileInfo]$File,
        [datetime]$CutoffDate
    )

    try {
        $lastWrite = $File.LastWriteTime
        if ($lastWrite -and $lastWrite -is [DateTime]) {
            return $lastWrite -lt $CutoffDate
        }
    }
    catch {
        return $false
    }
    return $false
}

# Function to calculate total size of files
function Get-TotalFileSize {
    param (
        [array]$Files
    )

    $total = 0
    foreach ($file in $Files) {
        if ($file.Length -is [long]) {
            $total += $file.Length
        }
    }
    return $total
}

# Function to test UNC path access
function Test-UNCPath {
    param (
        [string]$Path
    )

    try {
        if ($Path -match '^\\\\') {
            # Create a DirectoryInfo object to test access
            $dirInfo = New-Object System.IO.DirectoryInfo($Path)

            # Try to access the directory
            $null = $dirInfo.GetDirectories()
            return $true
        }
        return $true
    }
    catch {
        Write-Log "Unable to access UNC path: $Path. Error: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# Function to get age in days
function Get-FileAge {
    param (
        [DateTime]$LastWriteTime
    )
    return [math]::Round(((Get-Date) - $LastWriteTime).TotalDays, 1)
}

# Function to get cache file path
function Get-CacheFilePath {
    param (
        [string]$BasePath
    )

    $hashInput = [System.Text.Encoding]::UTF8.GetBytes($BasePath)
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash($hashInput)
    $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

    $cacheDir = Join-Path $env:TEMP "ArchiveRetention"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    return Join-Path $cacheDir "cache_$hashString.json"
}

# Function to check if cache is valid
function Test-CacheValidity {
    param (
        [string]$CacheFile,
        [string]$BasePath,
        [int]$RetentionDays,
        [int]$CacheValidityHours = 12
    )

    if (-not (Test-Path $CacheFile)) { return $false }

    try {
        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
        $cacheAge = (Get-Date) - [DateTime]$cache.Timestamp

        # Cache is valid if:
        # 1. It's less than CacheValidityHours old
        # 2. The base path matches
        # 3. The retention days match
        if ($cacheAge.TotalHours -le $CacheValidityHours -and
            $cache.BasePath -eq $BasePath -and
            $cache.RetentionDays -eq $RetentionDays) {

            # Quick check if directory exists
            if (Test-Path -Path $BasePath) {
                return $true
            }
        }
    }
    catch {
        Write-Log "Cache validation error: $($_.Exception.Message)" -Level WARNING
    }

    return $false
}

# Function to test file type against include/exclude filters
function Test-FileTypeFilter {
    param (
        [string]$FileName,
        [string[]]$IncludeFileTypes,
        [string[]]$ExcludeFileTypes
    )

    $extension = [System.IO.Path]::GetExtension($FileName).ToLower()

    # Normalize extensions to include dot
    $normalizedIncludes = @()
    if ($IncludeFileTypes -and $IncludeFileTypes.Count -gt 0) {
        $normalizedIncludes = $IncludeFileTypes | ForEach-Object {
            if ($_.StartsWith('.')) { $_ } else { ".$_" }
        }
    }

    $normalizedExcludes = @()
    if ($ExcludeFileTypes -and $ExcludeFileTypes.Count -gt 0) {
        $normalizedExcludes = $ExcludeFileTypes | ForEach-Object {
            if ($_.StartsWith('.')) { $_ } else { ".$_" }
        }
    }

    # If include types specified, file must match one
    if ($normalizedIncludes.Count -gt 0) {
        return $normalizedIncludes -contains $extension
    }

    # If exclude types specified, file must not match any
    if ($normalizedExcludes.Count -gt 0) {
        return -not ($normalizedExcludes -contains $extension)
    }

    # If no filters specified, include all files
    return $true
}

# Function to safely enumerate files in a directory
function Get-FilesRecursively {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [datetime]$CutoffDate,

        [string[]]$IncludeFileTypes = @(),

        [string[]]$ExcludeFileTypes = @()
    )

    try {
        $currentTime = Get-Date

        # Log timing information
        Write-Log "Current time (Local): $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
        Write-Log "Cutoff date (Local): $($CutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
        Write-Log "System timezone: $([System.TimeZoneInfo]::Local.DisplayName)" -Level INFO

        # Get all files
        Write-Log "Scanning directory: $Path" -Level INFO
        try {
            $allFiles = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction Stop
        } catch {
            Write-Log "Error enumerating files in path: $Path" -Level WARNING
            Write-Log "Exception: $($_.Exception.Message)" -Level WARNING
            Write-Log "StackTrace: $($_.ScriptStackTrace)" -Level WARNING
            $allFiles = @()
        }
        $allFiles = $allFiles | Where-Object { $_ -ne $null }

        # Apply file type filters
        if ($IncludeFileTypes -or $ExcludeFileTypes) {
            $allFiles = $allFiles | Where-Object {
                Test-FileTypeFilter -FileName $_.Name -IncludeFileTypes $IncludeFileTypes -ExcludeFileTypes $ExcludeFileTypes
            }
        }

        # Filter files by last write time
        $oldFiles = $allFiles | Where-Object { $_.LastWriteTime -lt $CutoffDate }

        # Log summary
        Write-Log "Found $($allFiles.Count) total files matching type criteria" -Level INFO
        Write-Log "Found $($oldFiles.Count) files older than cutoff date" -Level INFO

        # Log sample of files
        if ($oldFiles.Count -gt 0) {
            Write-Log "Sample of files to be processed:" -Level INFO
            $oldFiles | Select-Object -First 10 | ForEach-Object {
                $age = [math]::Round(($currentTime - $_.LastWriteTime).TotalDays, 2)
                Write-Log ("  {0} | {1} | {2} days old | {3:N2} GB" -f
                    $_.Name,
                    $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
                    $age,
                    ($_.Length/1GB)) -Level INFO
            }
            if ($oldFiles.Count -gt 10) {
                Write-Log "  ... and $($oldFiles.Count - 10) more files..." -Level INFO
            }
        }

        return $oldFiles
    }
    catch {
        Write-Log "Error in Get-FilesRecursively: $($_.Exception.Message)" -Level ERROR
        Write-Log $_.ScriptStackTrace -Level ERROR
        return @()
    }


}

# Function to perform operation with retry
function Invoke-WithRetry {
    param (
        [scriptblock]$Operation,
        [string]$Description,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5
    )

    $attempt = 1
    $success = $false
    $lastError = $null

    while (-not $success -and $attempt -le $MaxRetries) {
        try {
            if ($attempt -gt 1) {
                Write-Log "Retry attempt $attempt for: $Description" -Level WARNING
                Start-Sleep -Seconds ($DelaySeconds * ($attempt - 1))
            }

            & $Operation
            $success = $true
        }
        catch {
            $lastError = $_
            $attempt++

            if ($attempt -gt $MaxRetries) {
                Write-Log "Failed after $MaxRetries attempts: $Description" -Level ERROR
                Write-Log "Last error: $($lastError.Exception.Message)" -Level ERROR
                throw $lastError
            }
        }
    }
}

# Function for parallel file processing using runspaces
function Invoke-ParallelFileProcessing {
    param (
        [array]$Files,
        [bool]$Execute,
        [int]$ThreadCount = 4,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 1,
        [string]$DeletionLogPath = $null
    )

    Write-Log "Starting parallel file processing with $ThreadCount threads for $($Files.Count) files" -Level INFO
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.Open()
    
    # Thread-safe collections for results
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $modifiedDirs = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
    
    # Script block for file processing
    $scriptBlock = {
        param($FileInfo, $Execute, $MaxRetries, $RetryDelaySeconds, $DeletionLogPath)
        
        $result = @{
            FilePath = $FileInfo.FullName
            Success = $false
            Error = $null
            Size = $FileInfo.Length
            ParentDir = Split-Path -Path $FileInfo.FullName -Parent
        }
        
        try {
            if ($Execute) {
                $attempt = 1
                $success = $false
                
                while (-not $success -and $attempt -le $MaxRetries) {
                    try {
                        [System.IO.File]::Delete($FileInfo.FullName)
                        $success = $true
                        $result.Success = $true
                        
                        # Don't write to deletion log here - will be handled by main thread
                        # Just mark the file as successfully deleted
                    }
                    catch {
                        if ($attempt -ge $MaxRetries) {
                            $result.Error = $_.Exception.Message
                            break
                        }
                        Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
                        $attempt++
                    }
                }
            } else {
                # Dry-run mode
                $result.Success = $true
            }
        }
        catch {
            $result.Error = $_.Exception.Message
        }
        
        return $result
    }
    
    # Create and start jobs
    $jobs = @()
    $jobIndex = 0
    
    foreach ($file in $Files) {
        $powerShell = [powershell]::Create()
        $powerShell.RunspacePool = $runspacePool
        $powerShell.AddScript($scriptBlock).AddArgument($file).AddArgument($Execute).AddArgument($MaxRetries).AddArgument($RetryDelaySeconds).AddArgument($DeletionLogPath) | Out-Null
        
        $job = @{
            PowerShell = $powerShell
            Handle = $powerShell.BeginInvoke()
            Index = $jobIndex++
        }
        $jobs += $job
    }
    
    # Monitor job completion with progress reporting
    $completedJobs = 0
    $successCount = 0
    $errorCount = 0
    $processedSize = 0
    $startTime = Get-Date
    
    Write-Log "Waiting for $($jobs.Count) parallel jobs to complete..." -Level INFO
    
    while ($completedJobs -lt $jobs.Count) {
        Start-Sleep -Milliseconds 100
        
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            $job = $jobs[$i]
            if ($job.Handle.IsCompleted -and $job.PowerShell) {
                try {
                    $result = $job.PowerShell.EndInvoke($job.Handle)
                    
                    # Add result to the collection
                    $results.Add($result) | Out-Null
                    
                    if ($result.Success) {
                        $successCount++
                        $processedSize += $result.Size
                        # Track modified directory
                        $modifiedDirs.TryAdd($result.ParentDir, $true) | Out-Null
                    } else {
                        $errorCount++
                        if ($result.Error) {
                            Write-Log "Parallel processing error for $($result.FilePath): $($result.Error)" -Level ERROR
                        }
                    }
                }
                catch {
                    $errorCount++
                    Write-Log "Job completion error: $($_.Exception.Message)" -Level ERROR
                }
                finally {
                    $job.PowerShell.Dispose()
                    $job.PowerShell = $null
                    $completedJobs++
                }
            }
        }
        
        # Progress reporting every 5% or 10 seconds
        $percentComplete = [Math]::Round(($completedJobs / $jobs.Count) * 100, 1)
        $elapsed = (Get-Date) - $startTime
        
        if ($script:showProgress -and ($completedJobs % [Math]::Max(1, [Math]::Floor($jobs.Count / 20)) -eq 0 -or $elapsed.TotalSeconds % 10 -eq 0)) {
            $rate = if ($elapsed.TotalSeconds -gt 0) { [Math]::Round($completedJobs / $elapsed.TotalSeconds, 1) } else { 0 }
            Write-Host "  Parallel progress: $percentComplete% ($completedJobs/$($jobs.Count)) - Rate: $rate files/sec" -ForegroundColor Green
        }
    }
    
    # Cleanup
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    $finalElapsed = (Get-Date) - $startTime
    $finalRate = if ($finalElapsed.TotalSeconds -gt 0) { [Math]::Round($jobs.Count / $finalElapsed.TotalSeconds, 1) } else { 0 }
    
    Write-Log "Parallel processing completed: $successCount successful, $errorCount errors in $([Math]::Round($finalElapsed.TotalSeconds, 1)) seconds ($finalRate files/sec)" -Level INFO
    
    # Collect successfully deleted files
    $deletedFiles = @()
    Write-Log "Collecting deleted files from $($results.Count) results (Execute=$Execute)" -Level DEBUG
    foreach ($result in $results) {
        if ($result.Success -and $Execute) {
            $deletedFiles += $result.FilePath
        }
    }
    Write-Log "Collected $($deletedFiles.Count) deleted files to return" -Level DEBUG
    
    return @{
        SuccessCount = $successCount
        ErrorCount = $errorCount
        ProcessedSize = $processedSize
        ModifiedDirectories = $modifiedDirs
        Duration = $finalElapsed
        DeletedFiles = $deletedFiles
    }
}

# Main script execution
try {
    # Initialize logging with timestamp and rotation
    try {
        # Set max log size to 10MB and keep 5 rotated logs
        Initialize-Logging -MaxLogSizeMB 10 -MaxLogFiles 10

        # Set up log rotation for retention logs if in execute mode
        if ($Execute -and $script:DeletionLogPath) {
            $script:RetentionLogRotationParams = @{
                LogFile = $script:DeletionLogPath
                MaxLogSizeMB = 50
                MaxLogFiles = 10
                IsRetentionLog = $true
            }

            # Ensure the log rotation function is called for retention logs
            Invoke-LogRotation @script:RetentionLogRotationParams
        }

        Write-Log "Starting Archive Retention Script (Version $SCRIPT_VERSION)" -Level INFO
    }
    catch {
        Write-Error "Failed to initialize logging: $($_.Exception.Message)"
        exit 1
    }

    $scriptStartTime = Get-Date

    # Minimum retention safety mechanism
    $MINIMUM_RETENTION_DAYS = 90
    if ($RetentionDays -lt $MINIMUM_RETENTION_DAYS) {
        if ($Execute) {
            Write-Host "WARNING: The specified retention period ($RetentionDays days) is less than the enforced minimum ($MINIMUM_RETENTION_DAYS days). The minimum will be enforced for deletion." -ForegroundColor Yellow
            try { Write-Log "WARNING: The specified retention period ($RetentionDays days) is less than the enforced minimum ($MINIMUM_RETENTION_DAYS days). The minimum will be enforced for deletion." -Level WARNING } catch {}
            $RetentionDays = $MINIMUM_RETENTION_DAYS
        } else {
            Write-Host "WARNING: The specified retention period ($RetentionDays days) is less than the enforced minimum ($MINIMUM_RETENTION_DAYS days). This is a dry run, so no files will be deleted, but this value is not allowed for actual deletion." -ForegroundColor Yellow
            try { Write-Log "WARNING: The specified retention period ($RetentionDays days) is less than the enforced minimum ($MINIMUM_RETENTION_DAYS days). This is a dry run, so no files will be deleted, but this value is not allowed for actual deletion." -Level WARNING } catch {}
        }
    }

    # Define cutoff date
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

    # Auto-enable parallel processing for network paths unless explicitly disabled
    if (-not $PSBoundParameters.ContainsKey('ParallelProcessing') -and -not $Sequential) {
        Write-Log "Checking if path '$ArchivePath' is network path for auto-parallel" -Level DEBUG
        if ($ArchivePath -match '^\\\\') {
            $ParallelProcessing = $true
            Write-Log "Auto-enabled parallel processing for network path: $ArchivePath" -Level INFO
            if ($script:showProgress) {
                Write-Host "  → Auto-enabled parallel processing (8 threads) for network path" -ForegroundColor Green
            }
        }
    }

    # Log system and environment information
    $timezone = [System.TimeZoneInfo]::Local
    $localNow = Get-Date
    Write-Log "Script started at (local): $($localNow.ToString('yyyy-MM-dd HH:mm:ss.fff')) ($($timezone.DisplayName))" -Level INFO
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level DEBUG
    Write-Log "OS: $([System.Environment]::OSVersion)" -Level DEBUG
    Write-Log "Current user: $([System.Environment]::UserDomainName)\$([System.Environment]::UserName)" -Level DEBUG
    Write-Log "Working directory: $(Get-Location)" -Level DEBUG
    Write-Log "Script directory: $PSScriptRoot" -Level DEBUG
    Write-Log "Script configuration:" -Level INFO
    Write-Log "  Archive Path: $ArchivePath" -Level INFO
    if ($Execute -and $script:DeletionLogPath) {
        Write-Log "  Retention Actions Log: $($script:DeletionLogPath)" -Level INFO
    }
    Write-Log "  Script log file: $script:LogFile" -Level INFO
    Write-Log "  Retention Period: $RetentionDays days (cutoff date: $($cutoffDate.ToString('yyyy-MM-dd')))" -Level INFO
    Write-Log "  Include File Types: $($IncludeFileTypes -join ', ')" -Level INFO
    Write-Log "  Exclude File Types: $(if ($ExcludeFileTypes.Count -eq 0) { '(none)' } else { $ExcludeFileTypes -join ', ' })" -Level INFO
    Write-Log "  Batch Size: $BatchSize files" -Level INFO
    Write-Log "  Parallel Processing: $(if ($ParallelProcessing) { "Enabled ($ThreadCount threads)" } else { 'Disabled (sequential mode requested)' })" -Level INFO
    $progressFeatures = @()
    if ($ShowScanProgress) { $progressFeatures += 'scan' }
    if ($ShowDeleteProgress) { $progressFeatures += 'delete' }
    $progressMode = if ($QuietMode) { 'Quiet (no progress)' } elseif ($progressFeatures.Count -gt 0) { "Enhanced ($($progressFeatures -join ', ') progress)" } else { 'Standard' }
    Write-Log "  Progress Mode: $progressMode" -Level INFO
    Write-Log "  Smart Directory Cleanup: Enabled (tracks modified directories)" -Level INFO
    Write-Log "  Mode: $(if ($Execute) { 'EXECUTION' } else { 'DRY RUN - No files will be deleted' })" -Level INFO
    
    # Performance tip if sequential mode was explicitly requested for network path
    if ($Sequential -and $ArchivePath -like "\\*") {
        Write-Log "PERFORMANCE WARNING: Sequential mode requested for network path. Consider removing -Sequential for 4-8x faster deletion" -Level WARNING
        if ($script:showProgress) {
            Write-Host "`n  ⚠️  PERFORMANCE WARNING: Sequential mode will be slower on network paths!" -ForegroundColor Yellow
            Write-Host "     Remove -Sequential to enable parallel processing (default for network paths)" -ForegroundColor DarkYellow
        }
    }

    # Check if ArchivePath is a network path and needs credentials
    # Note: PowerShell may have already stripped one backslash, so we check for both patterns
    Write-Log "Checking if '$ArchivePath' is a network path (starts with \\ or single \ followed by IP)..." -Level DEBUG
    $isNetworkPath = ($ArchivePath -like "\\*" -or $ArchivePath -match '^\\\d+\.\d+\.\d+\.\d+\\')
    Write-Log "Is network path: $isNetworkPath, Has CredentialTarget: $($PSBoundParameters.ContainsKey('CredentialTarget'))" -Level DEBUG
    
    if ($isNetworkPath -and -not $PSBoundParameters.ContainsKey('CredentialTarget')) {
        Write-Log "Network path detected. Checking for saved credentials..." -Level INFO
        
        # Import credential helper module to check for saved credentials
        try {
            $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules/ShareCredentialHelper.psm1'
            Import-Module $modulePath -Force -ErrorAction Stop
            
            # Get all saved credentials and check if any match this path
            $savedCreds = Get-SavedCredentials
            # Need to normalize paths for comparison - add missing backslash if needed
            $normalizedPath = if ($ArchivePath -match '^\\\d+\.\d+\.\d+\.\d+\\') {
                "\\$ArchivePath"
            } else {
                $ArchivePath
            }
            $matchingCred = $savedCreds | Where-Object { $_.SharePath -eq $normalizedPath -or $_.SharePath -eq $ArchivePath } | Select-Object -First 1
            
            if ($matchingCred) {
                Write-Log "Found saved credential for '$ArchivePath' (Target: $($matchingCred.Target))" -Level INFO
                
                # Try to mount the network drive with the saved credential
                try {
                    $credentialInfo = Get-ShareCredential -Target $matchingCred.Target
                    
                    if ($credentialInfo) {
                        # Create a temporary PSDrive
                        $tempDriveName = "ArchiveMount"
                        New-PSDrive -Name $tempDriveName -PSProvider FileSystem -Root $credentialInfo.SharePath -Credential $credentialInfo.Credential -ErrorAction Stop | Out-Null
                        Write-Log "Successfully mounted network drive using saved credential '$($matchingCred.Target)'" -Level SUCCESS
                        
                        # Update ArchivePath to use the mounted drive
                        $ArchivePath = (Get-PSDrive $tempDriveName).Root
                        
                        # Mark that we mounted a drive for cleanup later
                        $script:tempDriveName = $tempDriveName
                    }
                } catch {
                    Write-Log "Failed to mount network drive with saved credential: $($_.Exception.Message)" -Level WARNING
                    Write-Log "Attempting to access path directly..." -Level INFO
                }
            } else {
                Write-Log "No saved credential found for network path '$ArchivePath'" -Level DEBUG
                Write-Log "To save credentials for this path, run: .\Save-Credential.ps1 -Target 'YourTargetName' -SharePath '$ArchivePath'" -Level INFO
            }
        } catch {
            Write-Log "Could not load credential helper module: $($_.Exception.Message)" -Level DEBUG
        }
    }

    # Before file enumeration, add robust path validation and error handling.
    if (-not (Test-Path $ArchivePath)) {
        $msg = "ERROR: Archive path '$ArchivePath' does not exist or is not accessible. This may be due to network issues, permissions, or the path being unavailable in this session."
        Write-Log $msg -Level FATAL
        Write-Host $msg -ForegroundColor Red
        Write-Log "Current user: $([System.Environment]::UserDomainName)\$([System.Environment]::UserName)" -Level ERROR
        Write-Log "Working directory: $(Get-Location)" -Level ERROR
        Write-Log "If this is a network path, ensure it is accessible and that the script is running as a user with appropriate permissions." -Level ERROR
        
        # Provide helpful suggestion for network paths
        if ($ArchivePath -like "\\*") {
            Write-Log "TIP: For network paths, either:" -Level ERROR
            Write-Log "  1. Use -CredentialTarget parameter with a saved credential" -Level ERROR
            Write-Log "  2. Save credentials first: .\Save-Credential.ps1 -Target 'NAS_CREDS' -SharePath '$ArchivePath'" -Level ERROR
            Write-Log "  3. Establish network connection first: net use '$ArchivePath' /user:username" -Level ERROR
        }
        
        exit 1
    }

    # Enhanced file processing with streaming for large datasets
    Write-Log "Scanning for files older than $RetentionDays days..." -Level INFO

    $scanStartTime = Get-Date
    $allFiles = @()  # Only populated in dry-run mode
    $totalFileCount = 0
    $totalSize = 0
    $oldestFile = $null
    $newestFile = $null
    $processedCount = 0
    $processedSize = 0
    $errorCount = 0
    $successCount = 0
    $modifiedDirectories = @{}  # Track directories with deleted files for smart cleanup
    
    # Determine processing mode
    $useStreamingMode = $Execute -and -not $ShowDeleteSummary
    $useParallelStreaming = $useStreamingMode -and $ParallelProcessing
    
    if ($useStreamingMode) {
        if ($useParallelStreaming) {
            Write-Log "Using PARALLEL streaming deletion mode with $ThreadCount threads for maximum network performance" -Level INFO
            Write-Log "Files will be processed in batches of $BatchSize as discovered" -Level INFO
        } else {
            Write-Log "Using streaming deletion mode for optimal performance on large datasets" -Level INFO
        }
        Write-Log "Progress updates: Every 1,000 files processed or every 30 seconds (whichever comes first)" -Level INFO
        if ($script:showProgress) {
            if ($useParallelStreaming) {
                Write-Host "  Parallel streaming mode: Files processed in batches with $ThreadCount threads" -ForegroundColor Cyan
            } else {
                Write-Host "  Streaming mode: Files will be processed as discovered (no pre-scan)" -ForegroundColor Cyan
            }
            Write-Host "  Progress updates: Every 1,000 files or 30 seconds" -ForegroundColor Gray
        }
    }
    
    try {
        if ($ShowScanProgress -and $script:showProgress) {
            Write-Host "  Using System.IO optimized enumeration for maximum performance..." -ForegroundColor Cyan
        }

        # Use System.IO.Directory.EnumerateFiles for 10-20x performance improvement
        $scannedCount = 0
        $matchedCount = 0
        $lastProgressLog = Get-Date
        $progressLogInterval = [TimeSpan]::FromSeconds(30)
        $progressFileInterval = 1000  # Log every 1000 files
        
        # Determine file patterns to search
        $patterns = if ($IncludeFileTypes -and $IncludeFileTypes.Count -gt 0) {
            $IncludeFileTypes | ForEach-Object { "*$_" }
        } else {
            @("*.*")
        }
        
        # For parallel streaming, create a batch collection
        if ($useParallelStreaming) {
            $streamingBatch = New-Object System.Collections.Generic.List[PSCustomObject]
            $batchStartTime = Get-Date
        }
        
        foreach ($pattern in $patterns) {
            if ($ShowScanProgress -and $script:showProgress) {
                Write-Host "    Scanning for pattern: $pattern" -ForegroundColor Cyan
            }
            
            # Use System.IO for streaming enumeration - dramatically faster than Get-ChildItem
            $enumerator = [System.IO.Directory]::EnumerateFiles($ArchivePath, $pattern, [System.IO.SearchOption]::AllDirectories)
            
            foreach ($filePath in $enumerator) {
                $scannedCount++
                
                # Show scanning progress
                if ($ShowScanProgress -and $script:showProgress -and ($scannedCount % 10000 -eq 0)) {
                    if ($useStreamingMode) {
                        Write-Host "    Processed $scannedCount files, deleted $successCount files..." -ForegroundColor Cyan
                    } else {
                        Write-Host "    Scanned $scannedCount files, found $matchedCount matching..." -ForegroundColor Cyan
                    }
                }
                
                try {
                    # Create FileInfo object for detailed information
                    $fileInfo = [System.IO.FileInfo]::new($filePath)
                    
                    # Apply date filter
                    if ($fileInfo.LastWriteTime -lt $cutoffDate) {
                        $matchedCount++
                        $totalFileCount++
                        $totalSize += $fileInfo.Length
                        
                        if ($useStreamingMode) {
                            # STREAMING MODE: Process file immediately or batch for parallel
                            if ($useParallelStreaming) {
                                # Add to batch for parallel processing
                                $fileObj = [PSCustomObject]@{
                                    FullName = $fileInfo.FullName
                                    Name = $fileInfo.Name
                                    DirectoryName = $fileInfo.DirectoryName
                                    LastWriteTime = $fileInfo.LastWriteTime
                                    CreationTime = $fileInfo.CreationTime
                                    Length = $fileInfo.Length
                                    Extension = $fileInfo.Extension
                                }
                                $streamingBatch.Add($fileObj)
                                
                                # Process batch when it reaches BatchSize
                                if ($streamingBatch.Count -ge $BatchSize) {
                                    Write-Log "Processing parallel streaming batch of $($streamingBatch.Count) files..." -Level DEBUG
                                    
                                    # Convert batch to array for processing
                                    $batchToProcess = $streamingBatch.ToArray()
                                    $streamingBatch.Clear()
                                    
                                    # Process batch in parallel
                                    $batchResult = Invoke-ParallelFileProcessing -Files $batchToProcess -Execute $true -ThreadCount $ThreadCount -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds -DeletionLogPath $script:DeletionLogPath
                                    
                                    # Write deleted files to retention log
                                    if ($script:DeletionLogWriter) {
                                        if ($batchResult.DeletedFiles -and $batchResult.DeletedFiles.Count -gt 0) {
                                            Write-Log "Writing $($batchResult.DeletedFiles.Count) deleted files to retention log" -Level DEBUG
                                            foreach ($deletedFile in $batchResult.DeletedFiles) {
                                                $script:DeletionLogWriter.WriteLine($deletedFile)
                                            }
                                            $script:DeletionLogWriter.Flush()
                                        } else {
                                            Write-Log "No deleted files returned from batch (DeletedFiles is null or empty)" -Level DEBUG
                                        }
                                    }
                                    
                                    # Aggregate results
                                    $successCount += $batchResult.SuccessCount
                                    $errorCount += $batchResult.ErrorCount
                                    $processedSize += $batchResult.ProcessedSize
                                    $processedCount += $batchToProcess.Count
                                    
                                    # Update script-level variables
                                    $script:totalFilesDeleted = $successCount
                                    $script:totalSpaceFreed = [math]::Round($processedSize / 1GB, 2)
                                    
                                    # Merge modified directories
                                    foreach ($dir in $batchResult.ModifiedDirectories.Keys) {
                                        $modifiedDirectories[$dir] = $true
                                    }
                                    
                                    # Progress reporting
                                    if ($ShowDeleteProgress -and $script:showProgress) {
                                        Write-Host "      Processed batch: $successCount total files deleted ($([math]::Round($processedSize / 1GB, 2)) GB)..." -ForegroundColor Green
                                    }
                                    
                                    # Periodic progress to main log
                                    $currentTime = Get-Date
                                    $timeSinceLastLog = $currentTime - $lastProgressLog
                                    if ($timeSinceLastLog -gt $progressLogInterval) {
                                        $elapsedTotal = $currentTime - $scanStartTime
                                        $rate = if ($elapsedTotal.TotalSeconds -gt 0) { 
                                            [math]::Round($successCount / $elapsedTotal.TotalSeconds, 1) 
                                        } else { 0 }
                                        $scanRate = if ($elapsedTotal.TotalSeconds -gt 0) { 
                                            [math]::Round($scannedCount / $elapsedTotal.TotalSeconds, 0) 
                                        } else { 0 }
                                        
                                        Write-Log "Parallel streaming progress: Scanned $scannedCount files, deleted $successCount files ($([math]::Round($processedSize / 1GB, 2)) GB freed)" -Level INFO
                                        Write-Log "  Deletion rate: $rate files/sec, Scan rate: $scanRate files/sec" -Level INFO
                                        Write-Log "  Running time: $([math]::Round($elapsedTotal.TotalMinutes, 1)) minutes" -Level INFO
                                        Write-Log "  Using $ThreadCount parallel threads" -Level INFO
                                        $lastProgressLog = $currentTime
                                    }
                                    
                                    if ($errorCount -gt 100) {
                                        Write-Log "Too many errors encountered. Stopping processing." -Level ERROR
                                        throw "Excessive errors during processing"
                                    }
                                }
                            } else {
                                # Sequential streaming (original code)
                                try {
                                    Invoke-WithRetry -Operation {
                                        [System.IO.File]::Delete($fileInfo.FullName)
                                    } -Description "Delete file: $($fileInfo.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
                                    
                                    # Track parent directory for smart cleanup
                                    $parentDir = $fileInfo.DirectoryName
                                    $modifiedDirectories[$parentDir] = $true
                                    
                                    # Log deletion
                                    Write-Log "Deleted file: $($fileInfo.FullName)" -Level $(if ($VerbosePreference -eq 'Continue') { 'INFO' } else { 'DEBUG' })
                                    if ($script:DeletionLogWriter) {
                                        try {
                                            $script:DeletionLogWriter.WriteLine($fileInfo.FullName)
                                            $script:DeletionLogWriter.Flush()
                                        } catch {
                                            Write-Log "Failed to write to deletion log: $($_.Exception.Message)" -Level WARNING
                                        }
                                    }
                                    
                                    $successCount++
                                    $processedCount++
                                    $processedSize += $fileInfo.Length
                                    
                                    # Show deletion progress
                                    if ($ShowDeleteProgress -and $script:showProgress -and ($successCount % 10 -eq 0)) {
                                        Write-Host "      Deleted $successCount files ($([math]::Round($processedSize / 1GB, 2)) GB)..." -ForegroundColor Green
                                    }
                                    
                                    # Periodic progress to main log (every 1000 files or 30 seconds)
                                    $currentTime = Get-Date
                                    $timeSinceLastLog = $currentTime - $lastProgressLog
                                    if (($successCount % $progressFileInterval -eq 0) -or ($timeSinceLastLog -gt $progressLogInterval)) {
                                        $elapsedTotal = $currentTime - $scanStartTime
                                        $rate = if ($elapsedTotal.TotalSeconds -gt 0) { 
                                            [math]::Round($successCount / $elapsedTotal.TotalSeconds, 1) 
                                        } else { 0 }
                                        $scanRate = if ($elapsedTotal.TotalSeconds -gt 0) { 
                                            [math]::Round($scannedCount / $elapsedTotal.TotalSeconds, 0) 
                                        } else { 0 }
                                        
                                        Write-Log "Streaming progress: Scanned $scannedCount files, deleted $successCount files ($([math]::Round($processedSize / 1GB, 2)) GB freed)" -Level INFO
                                        Write-Log "  Deletion rate: $rate files/sec, Scan rate: $scanRate files/sec" -Level INFO
                                        Write-Log "  Running time: $([math]::Round($elapsedTotal.TotalMinutes, 1)) minutes" -Level INFO
                                        $lastProgressLog = $currentTime
                                    }
                                }
                                catch {
                                    Write-Log "Error deleting file $($fileInfo.FullName): $($_.Exception.Message)" -Level ERROR
                                    $errorCount++
                                    if ($errorCount -gt 100) {
                                        Write-Log "Too many errors encountered. Stopping processing." -Level ERROR
                                        throw "Excessive errors during processing"
                                    }
                                }
                            }
                        }
                        else {
                            # PRE-SCAN MODE: Build array for dry-run or summary
                            $fileObj = [PSCustomObject]@{
                                FullName = $fileInfo.FullName
                                Name = $fileInfo.Name
                                DirectoryName = $fileInfo.DirectoryName
                                LastWriteTime = $fileInfo.LastWriteTime
                                CreationTime = $fileInfo.CreationTime
                                Length = $fileInfo.Length
                                Extension = $fileInfo.Extension
                            }
                            
                            $allFiles += $fileObj
                            
                            # Track parent directory for smart cleanup
                            $modifiedDirectories[$fileInfo.DirectoryName] = $true
                        }
                        
                        # Track oldest and newest for statistics
                        if ($null -eq $oldestFile -or $fileInfo.LastWriteTime -lt $oldestFile.LastWriteTime) {
                            $oldestFile = [PSCustomObject]@{
                                Name = $fileInfo.Name
                                LastWriteTime = $fileInfo.LastWriteTime
                            }
                        }
                        if ($null -eq $newestFile -or $fileInfo.LastWriteTime -gt $newestFile.LastWriteTime) {
                            $newestFile = [PSCustomObject]@{
                                Name = $fileInfo.Name
                                LastWriteTime = $fileInfo.LastWriteTime
                            }
                        }
                    }
                }
                catch {
                    Write-Log "Error processing file: $filePath - $($_.Exception.Message)" -Level WARNING
                    if ($useStreamingMode) {
                        $errorCount++
                    }
                }
            }
        }
        
        $scanDuration = [math]::Round(((Get-Date) - $scanStartTime).TotalSeconds, 1)
        if ($script:showProgress) {
            if ($useStreamingMode) {
                if ($useParallelStreaming) {
                    Write-Host "  Parallel streaming deletion completed: $scannedCount files scanned, $successCount deleted in $scanDuration seconds" -ForegroundColor Cyan
                    if ($successCount -gt 0) {
                        $deleteRate = if ($scanDuration -gt 0) { [math]::Round($successCount / $scanDuration, 0) } else { 0 }
                        Write-Host "  Deletion performance: $deleteRate files/second (using $ThreadCount threads)" -ForegroundColor Green
                        Write-Host "  Total space freed: $([math]::Round($processedSize / 1GB, 2)) GB" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  Streaming deletion completed: $scannedCount files scanned, $successCount deleted in $scanDuration seconds" -ForegroundColor Cyan
                    if ($successCount -gt 0) {
                        $deleteRate = if ($scanDuration -gt 0) { [math]::Round($successCount / $scanDuration, 0) } else { 0 }
                        Write-Host "  Deletion performance: $deleteRate files/second" -ForegroundColor Green
                        Write-Host "  Total space freed: $([math]::Round($processedSize / 1GB, 2)) GB" -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "  System.IO scan completed: $scannedCount total files scanned, $matchedCount matched criteria in $scanDuration seconds" -ForegroundColor Cyan
                $scanRate = if ($scanDuration -gt 0) { [math]::Round($scannedCount / $scanDuration, 0) } else { 0 }
                Write-Host "  Scan performance: $scanRate files/second" -ForegroundColor Green
            }
        }

    } catch {
        $errMsg = "CRITICAL: Unable to enumerate files in path: $ArchivePath. Error: $($_.Exception.Message)"
        Write-Log $errMsg -Level FATAL
        Write-Host $errMsg -ForegroundColor Red
        exit 2
    }
    
    # Process any remaining files in the parallel streaming batch
    if ($useParallelStreaming -and $streamingBatch -and $streamingBatch.Count -gt 0) {
        Write-Log "Processing final parallel streaming batch of $($streamingBatch.Count) files..." -Level DEBUG
        
        # Convert batch to array for processing
        $batchToProcess = $streamingBatch.ToArray()
        $streamingBatch.Clear()
        
        # Process batch in parallel
        $batchResult = Invoke-ParallelFileProcessing -Files $batchToProcess -Execute $true -ThreadCount $ThreadCount -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds -DeletionLogPath $script:DeletionLogPath
        
        # Write deleted files to retention log
        if ($script:DeletionLogWriter) {
            if ($batchResult.DeletedFiles -and $batchResult.DeletedFiles.Count -gt 0) {
                Write-Log "Writing $($batchResult.DeletedFiles.Count) deleted files to retention log" -Level DEBUG
                foreach ($deletedFile in $batchResult.DeletedFiles) {
                    $script:DeletionLogWriter.WriteLine($deletedFile)
                }
                $script:DeletionLogWriter.Flush()
            } else {
                Write-Log "No deleted files returned from final batch (DeletedFiles is null or empty)" -Level DEBUG
            }
        }
        
        # Aggregate results
        $successCount += $batchResult.SuccessCount
        $errorCount += $batchResult.ErrorCount
        $processedSize += $batchResult.ProcessedSize
        $processedCount += $batchToProcess.Count
        
        # Update script-level tracking variables
        $script:totalFilesDeleted = $successCount
        $script:totalSpaceFreed = [math]::Round($processedSize / 1GB, 2)
        
        # Merge modified directories
        foreach ($dir in $batchResult.ModifiedDirectories.Keys) {
            $modifiedDirectories[$dir] = $true
        }
        
        if ($ShowDeleteProgress -and $script:showProgress) {
            Write-Host "      Final batch processed: $successCount total files deleted ($([math]::Round($processedSize / 1GB, 2)) GB)" -ForegroundColor Green
        }
    }

    $totalSizeGB = [math]::Round($totalSize / 1GB, 2)
    
    if (-not $useStreamingMode) {
        # Pre-scan mode - files to be processed
        Write-Log "Found $totalFileCount files ($totalSizeGB GB) that would be processed (older than $RetentionDays days)" -Level INFO
    }

    if ($totalFileCount -gt 0 -and $oldestFile -and $newestFile) {
        Write-Log "  Oldest file: $($oldestFile.Name) (Last modified: $($oldestFile.LastWriteTime))" -Level INFO
        Write-Log "  Newest file: $($newestFile.Name) (Last modified: $($newestFile.LastWriteTime))" -Level INFO
    }

    # Initialize progress tracking variables
    $processingStartTime = Get-Date  # Always initialize for time calculations
    
    if (-not $useStreamingMode) {
        $script:lastProgressUpdate = Get-Date

        # Configure progress interval based on parameters
        if ($QuietMode -or $ProgressInterval -eq 0) {
            $script:progressUpdateInterval = [TimeSpan]::MaxValue  # Effectively disable progress updates
            $script:showProgress = $false
        } else {
            $script:progressUpdateInterval = [TimeSpan]::FromSeconds($ProgressInterval)
            $script:showProgress = $true
        }
    }
    
    # Skip batch processing if we already processed files in streaming mode
    if ($useStreamingMode) {
        Write-Log "Streaming deletion complete: Processed $totalFileCount files ($totalSizeGB GB) older than $RetentionDays days" -Level INFO
        Write-Log "  Successfully deleted: $successCount files" -Level INFO
        Write-Log "  Failed: $errorCount files" -Level INFO
        Write-Log "  Space freed: $([math]::Round($processedSize / 1GB, 2)) GB" -Level INFO
        
        # Close deletion log writer after streaming mode to allow summary to be written
        if ($script:DeletionLogWriter) {
            try {
                if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                    $script:DeletionLogWriter.Flush()
                    $script:DeletionLogWriter.Close()
                    $script:DeletionLogWriter.Dispose()
                    $script:DeletionLogWriter = $null
                    Write-Log "Closed deletion log writer after streaming completion" -Level DEBUG
                }
            } catch {
                Write-Log "Error closing deletion log writer after streaming: $($_.Exception.Message)" -Level WARNING
            }
        }
    } elseif (-not $Execute -and $allFiles.Count -gt 0) {
        # Dry-run mode - just show summary
        Write-Log " " -Level INFO
        Write-Log "DRY-RUN SUMMARY:" -Level INFO
        Write-Log "  Total files that would be deleted: $totalFileCount" -Level INFO
        Write-Log "  Total size that would be freed: $totalSizeGB GB" -Level INFO
        Write-Log "  Files are older than: $RetentionDays days (cutoff: $cutoffDateStr)" -Level INFO
        if ($script:showProgress) {
            Write-Host " " -ForegroundColor White
            Write-Host "  DRY-RUN COMPLETE: $totalFileCount files ($totalSizeGB GB) would be deleted" -ForegroundColor Cyan
            Write-Host "  Run with -Execute flag to actually delete these files" -ForegroundColor Yellow
        }
        # Set counts for summary
        $processedCount = $totalFileCount
        $successCount = 0
        $errorCount = 0
    } elseif ($ParallelProcessing -and $allFiles.Count -gt 0) {
        # Choose processing method based on ParallelProcessing flag
        Write-Log "Using parallel processing with $ThreadCount threads for maximum performance..." -Level INFO
        
        # Process files in parallel batches for optimal performance
        for ($i = 0; $i -lt $allFiles.Count; $i += $BatchSize) {
            $batchEnd = [Math]::Min($i + $BatchSize - 1, $allFiles.Count - 1)
            $currentBatch = $allFiles[$i..$batchEnd]
            $batchNumber = [Math]::Floor($i / $BatchSize) + 1
            $totalBatches = [Math]::Ceiling($allFiles.Count / $BatchSize)
            
            Write-Log "Processing parallel batch $batchNumber of $totalBatches ($($currentBatch.Count) files)..." -Level DEBUG
            
            # Use parallel processing for the batch
            $batchResult = Invoke-ParallelFileProcessing -Files $currentBatch -Execute $Execute -ThreadCount $ThreadCount -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds -DeletionLogPath $script:DeletionLogPath
            
            # Write deleted files to retention log
            if ($script:DeletionLogWriter) {
                if ($batchResult.DeletedFiles -and $batchResult.DeletedFiles.Count -gt 0) {
                    Write-Log "Writing $($batchResult.DeletedFiles.Count) deleted files to retention log from batch $batchNum" -Level DEBUG
                    foreach ($deletedFile in $batchResult.DeletedFiles) {
                        $script:DeletionLogWriter.WriteLine($deletedFile)
                    }
                    $script:DeletionLogWriter.Flush()
                } else {
                    Write-Log "No deleted files returned from batch $batchNum (DeletedFiles is null or empty)" -Level DEBUG
                }
            }
            
            # Aggregate results
            $successCount += $batchResult.SuccessCount
            $errorCount += $batchResult.ErrorCount
            $processedSize += $batchResult.ProcessedSize
            $processedCount += $currentBatch.Count
            
            # Merge modified directories
            foreach ($dir in $batchResult.ModifiedDirectories.Keys) {
                $modifiedDirectories[$dir] = $true
            }
            
            $script:processedCount = $processedCount
            $script:processedSize = $processedSize
            
            # Batch completion and progress reporting
            if ($script:showProgress) {
                $now = Get-Date
                $elapsedSeconds = [math]::Round(($now - $processingStartTime).TotalSeconds, 1)
                
                # Periodic detailed progress updates
                if (($now - $script:lastProgressUpdate) -gt $script:progressUpdateInterval) {
                    $percentComplete = [Math]::Round(($processedCount / $allFiles.Count) * 100, 1)
                    $rate = Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount
                    $eta = Get-EstimatedTimeRemaining -StartTime $processingStartTime -ProcessedCount $processedCount -TotalCount $allFiles.Count
                    Write-Log "Parallel Progress: $percentComplete% ($processedCount of $($allFiles.Count) files) - Batch $batchNumber/$totalBatches completed at $elapsedSeconds seconds" -Level INFO
                    $processedSizeGB = [math]::Round($processedSize / 1GB, 2)
                    Write-Log "  Processed: $processedSizeGB GB of $totalSizeGB GB" -Level INFO
                    Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
                    Write-Log "  Rate: $rate" -Level INFO
                    Write-Log "  Estimated time remaining: $eta" -Level INFO
                    $script:lastProgressUpdate = $now
                }
            }
            
            # Small delay between parallel batches
            if ($batchNumber -lt $totalBatches) {
                Start-Sleep -Milliseconds 100
            }
        }
    } elseif ($allFiles.Count -gt 0) {
        # Sequential processing with batching for compatibility
        Write-Log "Using sequential batch processing ($BatchSize files per batch)..." -Level INFO
        
        # Process files in batches to improve network efficiency
        for ($i = 0; $i -lt $allFiles.Count; $i += $BatchSize) {
            $batchEnd = [Math]::Min($i + $BatchSize - 1, $allFiles.Count - 1)
            $currentBatch = $allFiles[$i..$batchEnd]
            $batchNumber = [Math]::Floor($i / $BatchSize) + 1
            $totalBatches = [Math]::Ceiling($allFiles.Count / $BatchSize)
            
            Write-Log "Processing sequential batch $batchNumber of $totalBatches ($($currentBatch.Count) files)..." -Level DEBUG
            
            foreach ($file in $currentBatch) {
                try {
                    if ($Execute) {
                        Invoke-WithRetry -Operation {
                            [System.IO.File]::Delete($file.FullName)
                        } -Description "Delete file: $($file.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
                        # Track parent directory for smart cleanup
                        $parentDir = Split-Path -Path $file.FullName -Parent
                        $modifiedDirectories[$parentDir] = $true
                        # Log deletion at DEBUG unless -Verbose
                        Write-Log "Deleted file: $($file.FullName)" -Level $(if ($VerbosePreference -eq 'Continue') { 'INFO' } else { 'DEBUG' })
                        if ($script:DeletionLogWriter) {
                            try {
                                $script:DeletionLogWriter.WriteLine($file.FullName)
                                $script:DeletionLogWriter.Flush()
                            } catch {
                                Write-Log "Failed to write to deletion log: $($_.Exception.Message)" -Level WARNING
                            }
                        }
                    } else {
                        Write-Log "Would delete: $($file.FullName)" -Level DEBUG
                        # Track parent directory for smart cleanup in dry-run too
                        $parentDir = Split-Path -Path $file.FullName -Parent
                        $modifiedDirectories[$parentDir] = $true
                    }
                    $successCount++
                    $processedSize += $file.Length
                } catch {
                    Write-Log "Error processing file $($file.FullName): $($_.Exception.Message)" -Level ERROR
                    $errorCount++
                    if ($errorCount -gt 100) {
                        Write-Log "Too many errors encountered. Stopping processing." -Level ERROR
                        throw "Excessive errors during processing"
                    }
                }
                $processedCount++
                $script:processedCount = $processedCount
                $script:processedSize = $processedSize
                
                # Show real-time progress if requested (every 10 files within batch)
                if ($script:showProgress -and $ShowDeleteProgress -and ($processedCount % 10 -eq 0)) {
                    $percentComplete = [Math]::Round(($processedCount / $allFiles.Count) * 100, 1)
                    $processedSizeGB = [math]::Round($processedSize / 1GB, 2)
                    Write-Host "  Processed: $processedCount/$($allFiles.Count) files ($percentComplete%) - $processedSizeGB GB" -ForegroundColor Green
                }
            }
            
            # Batch completion and progress reporting
            if ($script:showProgress) {
                $now = Get-Date
                $elapsedSeconds = [math]::Round(($now - $processingStartTime).TotalSeconds, 1)
                
                # Periodic detailed progress updates (at batch boundaries or time intervals)
                if (($now - $script:lastProgressUpdate) -gt $script:progressUpdateInterval) {
                    $percentComplete = [Math]::Round(($processedCount / $allFiles.Count) * 100, 1)
                    $rate = Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount
                    $eta = Get-EstimatedTimeRemaining -StartTime $processingStartTime -ProcessedCount $processedCount -TotalCount $allFiles.Count
                    Write-Log "Sequential Progress: $percentComplete% ($processedCount of $($allFiles.Count) files) - Batch $batchNumber/$totalBatches completed at $elapsedSeconds seconds" -Level INFO
                    $processedSizeGB = [math]::Round($processedSize / 1GB, 2)
                    Write-Log "  Processed: $processedSizeGB GB of $totalSizeGB GB" -Level INFO
                    Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
                    Write-Log "  Rate: $rate" -Level INFO
                    Write-Log "  Estimated time remaining: $eta" -Level INFO
                    $script:lastProgressUpdate = $now
                }
            }
            
            # Small delay between batches to prevent overwhelming the system
            if ($batchNumber -lt $totalBatches) {
                Start-Sleep -Milliseconds 50
            }
        }
    }  # End of batch processing section
    
    # Calculate processing time
    $processingTime = $null
    if ($processingStartTime -is [DateTime]) {
        try {
            $processingTime = (Get-Date) - $processingStartTime
        } catch {
            Write-Log "Warning: Could not calculate processing time. processingStartTime type: $($processingStartTime.GetType().FullName), value: $processingStartTime" -Level WARNING
            $processingTime = $null
        }
    } else {
        Write-Log "Warning: processingStartTime is not a DateTime. Type: $($processingStartTime.GetType().FullName), value: $processingStartTime" -Level WARNING
    }
    $processingTimeStr = if ($processingTime -is [TimeSpan]) { '{0:hh\:mm\:ss}' -f $processingTime } else { 'Unknown' }
    # Processing complete summary
    if (-not $useStreamingMode -or $totalFileCount -gt 0) {
        Write-Log " " -Level INFO
        Write-Log "Processing Complete:" -Level INFO
        $displayProcessedCount = if ($useStreamingMode) { $successCount } else { $processedCount }
        Write-Log "  Total Files Processed: $displayProcessedCount of $totalFileCount" -Level INFO
        Write-Log "  Successfully Processed: $successCount" -Level INFO
        Write-Log "  Failed: $errorCount" -Level INFO
        $processedSizeGB = [math]::Round($processedSize / 1GB, 2)
        Write-Log "  Total Size Processed: $processedSizeGB GB of $totalSizeGB GB" -Level INFO
        
        # Use appropriate start time and count for rate calculation
        $startTimeForRate = if ($useStreamingMode) { $scanStartTime } else { $script:startTime }
        $countForRate = if ($useStreamingMode) { $successCount } else { $processedCount }
        Write-Log "  Processing Rate: $(Get-ProcessingRate -StartTime $startTimeForRate -ProcessedCount $countForRate)" -Level INFO
        $elapsedTime = (Get-Date) - $script:startTime
        $elapsedTimeStr = '{0:hh\:mm\:ss}' -f $elapsedTime
        Write-Log "  Elapsed Time: $elapsedTimeStr" -Level INFO
    }

    # After the main loop, log final progress if not in quiet mode and there were files
    if (-not $QuietMode -and $totalFileCount -gt 0) {
        $finalElapsedSeconds = [math]::Round(((Get-Date) - $scanStartTime).TotalSeconds, 1)
        $finalProcessedCount = if ($useStreamingMode) { $successCount } else { $processedCount }
        Write-Log "Progress: 100% ($finalProcessedCount of $totalFileCount files) at $finalElapsedSeconds seconds run-time" -Level INFO
        $processedSizeGB = [math]::Round($processedSize / 1GB, 2)
        Write-Log "  Processed: $processedSizeGB GB of $totalSizeGB GB" -Level INFO
        Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
        
        $finalStartTime = if ($useStreamingMode) { $scanStartTime } else { $processingStartTime }
        $finalCount = if ($useStreamingMode) { $successCount } else { $processedCount }
        Write-Log "  Rate: $(Get-ProcessingRate -StartTime $finalStartTime -ProcessedCount $finalCount)" -Level INFO
        Write-Log "  Estimated time remaining: 0 minutes" -Level INFO
    }
    
    # Close deletion log writer before directory cleanup to allow summary to be written
    if ($script:DeletionLogWriter -and -not $useStreamingMode) {
        try {
            if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                $script:DeletionLogWriter.Flush()
                $script:DeletionLogWriter.Close()
                $script:DeletionLogWriter.Dispose()
                $script:DeletionLogWriter = $null
                Write-Log "Closed deletion log writer before directory cleanup" -Level DEBUG
            }
        } catch {
            Write-Log "Error closing deletion log writer before cleanup: $($_.Exception.Message)" -Level WARNING
        }
    }

    # --- Smart Empty Directory Cleanup ---
    if ($SkipDirCleanup) {
        Write-Log "Skipping empty directory cleanup under $ArchivePath due to -SkipDirCleanup switch." -Level INFO
    } else {
        Write-Log "Starting smart empty directory cleanup..." -Level INFO
        $cleanupStartTime = Get-Date
        try {
            $removedCount = 0
            $checkedCount = 0
            
            if ($modifiedDirectories.Count -gt 0) {
                Write-Log "Using smart cleanup - focusing on $($modifiedDirectories.Count) directories where files were deleted" -Level INFO
                if ($ShowScanProgress -and $script:showProgress) {
                    Write-Host "  Smart directory cleanup (checking only modified directories)..." -ForegroundColor Cyan
                }
                
                # Get all directories from modified paths and their parents, sorted deepest first
                $directoriesToCheck = @()
                foreach ($modifiedDir in $modifiedDirectories.Keys) {
                    # Add the directory itself
                    if (Test-Path $modifiedDir -PathType Container) {
                        $directoriesToCheck += $modifiedDir
                    }
                    
                    # Add parent directories up to the archive root
                    $currentDir = $modifiedDir
                    while ($currentDir -ne $ArchivePath -and $currentDir -ne (Split-Path $currentDir -Parent)) {
                        $parentDir = Split-Path $currentDir -Parent
                        if ($parentDir -and $parentDir -ne $ArchivePath -and (Test-Path $parentDir -PathType Container)) {
                            $directoriesToCheck += $parentDir
                        }
                        $currentDir = $parentDir
                    }
                }
                
                # Remove duplicates and sort deepest first for efficient cleanup
                $directoriesToCheck = $directoriesToCheck | Sort-Object -Unique | Sort-Object Length -Descending
                
                foreach ($dirPath in $directoriesToCheck) {
                    $checkedCount++
                    
                    # Never remove the root archive path itself
                    if ($dirPath -eq (Resolve-Path $ArchivePath)) { continue }
                    
                    # Optimized empty check
                    try {
                        $isEmpty = @(Get-ChildItem -Path $dirPath -Force -ErrorAction Stop).Count -eq 0
                    } catch {
                        # Skip directories we can't access
                        continue
                    }
                    
                    if ($isEmpty) {
                        if ($Execute) {
                            try {
                                Remove-Item -Path $dirPath -Force -ErrorAction Stop
                                Write-Log "Removed empty directory: $dirPath" -Level DEBUG
                                $removedCount++
                                $script:totalDirsRemoved = $removedCount
                            } catch {
                                Write-Log "Failed to remove empty directory: $dirPath - $($_.Exception.Message)" -Level WARNING
                            }
                        } else {
                            Write-Log "Would remove empty directory: $dirPath" -Level DEBUG
                            $removedCount++
                            $script:totalDirsRemoved = $removedCount
                        }
                    }
                    
                    # Show progress for directory cleanup if requested
                    if ($ShowScanProgress -and $script:showProgress -and ($checkedCount % 50 -eq 0)) {
                        Write-Host "    Smart cleanup: checked $checkedCount directories, found $removedCount empty" -ForegroundColor Cyan
                    }
                }
            } else {
                Write-Log "No files were processed, skipping directory cleanup" -Level INFO
            }
            
            $cleanupDuration = [math]::Round(((Get-Date) - $cleanupStartTime).TotalSeconds, 1)
            
            if ($removedCount -gt 0) {
                $msg = if ($Execute) { "Smart cleanup removed $removedCount empty directories in $cleanupDuration seconds (checked $checkedCount total)" } else { "Smart cleanup would remove $removedCount empty directories (dry-run) - scan took $cleanupDuration seconds" }
                Write-Log $msg -Level INFO
            } else {
                Write-Log "Smart cleanup found no empty directories to remove (checked $checkedCount directories in $cleanupDuration seconds)" -Level INFO
            }
        } catch {
            Write-Log "Error during smart directory cleanup: $($_.Exception.Message)" -Level WARNING
        }
    }
    # --- End Empty Directory Cleanup ---

    # Pass summary data to completion function
    $totalFilesDeleted = if ($Execute) { $successCount } else { 0 }
    $totalDirsRemoved = if ($Execute -and -not $SkipDirCleanup) { $removedCount } else { 0 }
    $totalSpaceFreed = [math]::Round($processedSize / 1GB, 2)
    
    # Update script-level variables for finally block
    $script:totalFilesDeleted = $totalFilesDeleted
    $script:totalDirsRemoved = $totalDirsRemoved
    $script:totalSpaceFreed = $totalSpaceFreed
    
    # Close deletion log writer before completion to allow summary to be written
    if ($script:DeletionLogWriter) {
        try {
            if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                $script:DeletionLogWriter.Flush()
                $script:DeletionLogWriter.Close()
                $script:DeletionLogWriter.Dispose()
                $script:DeletionLogWriter = $null
            }
        } catch {
            Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    Complete-ScriptExecution -Success $true -FilesDeleted $totalFilesDeleted -DirectoriesRemoved $totalDirsRemoved -SpaceFreedGB $totalSpaceFreed
}
catch {
    $errorMsg = if ([string]::IsNullOrWhiteSpace($_.Exception.Message)) { "An unknown unhandled error occurred" } else { $_.Exception.Message }
    $fullErrorMsg = "Unhandled error: $errorMsg"
    Write-Log $fullErrorMsg -Level FATAL
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    # Log types and values of key variables if op_Subtraction error
    if ($errorMsg -like '*op_Subtraction*') {
        Write-Log "Diagnostic: processingStartTime type: $($processingStartTime?.GetType().FullName), value: $processingStartTime" -Level ERROR
        Write-Log "Diagnostic: scriptStartTime type: $($scriptStartTime?.GetType().FullName), value: $scriptStartTime" -Level ERROR
        Write-Log "Diagnostic: script:endTime type: $($script:endTime?.GetType().FullName), value: $script:endTime" -Level ERROR
    }
    
    # Close deletion log writer before completion to allow summary to be written
    if ($script:DeletionLogWriter) {
        try {
            if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                $script:DeletionLogWriter.Flush()
                $script:DeletionLogWriter.Close()
                $script:DeletionLogWriter.Dispose()
                $script:DeletionLogWriter = $null
            }
        } catch {
            Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    Complete-ScriptExecution -Success $false -Message $errorMsg -FilesDeleted 0 -DirectoriesRemoved 0 -SpaceFreedGB 0
    exit 1
}
finally {
    # Cleanup
    # Clean up temporary PSDrive if it was created
    if ($null -ne $tempDriveName -and (Get-PSDrive $tempDriveName -ErrorAction SilentlyContinue)) {
        Write-Log "Removing temporary PSDrive '$tempDriveName'..." -Level DEBUG
        Remove-PSDrive -Name $tempDriveName -Force -ErrorAction SilentlyContinue
    }

    # Release single-instance lock
    if ($script:LockFileStream) {
        try {
            $script:LockFileStream.Close()
            $script:LockFileStream.Dispose()
            Remove-Item -Path $script:LockFilePath -Force -ErrorAction SilentlyContinue
            Write-Log "Released single-instance lock." -Level DEBUG
        } catch {}
    }

    if (-not $script:completed) {
        # Close deletion log writer before completion to allow summary to be written
        if ($script:DeletionLogWriter) {
            try {
                if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                    $script:DeletionLogWriter.Flush()
                    $script:DeletionLogWriter.Close()
                    $script:DeletionLogWriter.Dispose()
                    $script:DeletionLogWriter = $null
                }
            } catch {
                Write-Log "Error closing deletion log writer: $($_.Exception.Message)" -Level WARNING
            }
        }
        # Use actual values from script execution
        $finalFilesDeleted = if ($null -ne $script:totalFilesDeleted) { $script:totalFilesDeleted } elseif ($null -ne $successCount) { $successCount } else { 0 }
        $finalDirsRemoved = if ($null -ne $script:totalDirsRemoved) { $script:totalDirsRemoved } elseif ($null -ne $removedCount) { $removedCount } else { 0 }
        $finalSpaceFreed = if ($null -ne $script:totalSpaceFreed) { $script:totalSpaceFreed } elseif ($null -ne $processedSize) { [math]::Round($processedSize / 1GB, 2) } else { 0 }
        
        # Determine success status - false if terminated or if we had an error
        $wasSuccessful = -not $script:terminated -and -not $Error[0]
        Complete-ScriptExecution -Success $wasSuccessful -FilesDeleted $finalFilesDeleted -DirectoriesRemoved $finalDirsRemoved -SpaceFreedGB $finalSpaceFreed
    }
}

# End of script
