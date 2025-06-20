# ArchiveRetention.ps1
#requires -Version 5.1

<#
.SYNOPSIS
    Archive (delete) files older than a specified retention period.

.DESCRIPTION
    This script processes files in a specified directory (including subdirectories) 
    and deletes files that are older than the specified retention period.
    
    Version 2.0 - Refactored with modular architecture for better performance and maintainability.

.PARAMETER ArchivePath
    Path to archive directory that needs to be processed.

.PARAMETER RetentionDays
    Number of days to retain files. Files older than this will be processed. (1-3650)

.PARAMETER Execute
    Actually perform the operations (default: dry-run). Without this, script runs in dry-run mode.

.PARAMETER CredentialTarget
    The name of a credential previously saved with Save-Credential.ps1 for network share access.

.PARAMETER SkipDirCleanup
    If specified, skips the empty directory cleanup step after file processing.

.PARAMETER IncludeFileTypes
    File types to include (e.g., '.lca', '.txt'). Defaults to '.lca'.

.PARAMETER ExcludeFileTypes
    File types to exclude from processing.

.PARAMETER ParallelThreads
    Number of parallel threads for file enumeration (1-16). Default: 4

.PARAMETER ConfigFile
    Path to JSON configuration file with script settings.

.PARAMETER LogPath
    Path to log file. Defaults to script_logs folder.

.PARAMETER Verbose
    Enables verbose logging output.

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365
    Dry run showing what would be deleted

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -Execute
    Actually delete files older than 365 days

.EXAMPLE
    .\ArchiveRetention.ps1 -CredentialTarget "NAS_Archive" -RetentionDays 180 -Execute
    Use saved credentials to access network share

.NOTES
    Requires PowerShell 5.1 or later
    Version: 2.0.0
#>

[CmdletBinding(DefaultParameterSetName='LocalPath')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='LocalPath', Position=0)]
    [string]$ArchivePath,

    [Parameter(Mandatory=$true, ParameterSetName='NetworkShare')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', 
        Justification='CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays,

    [Parameter()]
    [switch]$Execute,

    [Parameter()]
    [switch]$SkipDirCleanup,

    [Parameter()]
    [string[]]$IncludeFileTypes = @('.lca'),

    [Parameter()]
    [string[]]$ExcludeFileTypes = @(),

    [Parameter()]
    [ValidateRange(1, 16)]
    [int]$ParallelThreads = 4,

    [Parameter()]
    [string]$ConfigFile,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [switch]$Help
)

# Script constants
$SCRIPT_VERSION = '2.0.0'
$SCRIPT_NAME = 'ArchiveRetention'

# Show help if requested
if ($Help -or $PSBoundParameters.Count -eq 0) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Set error action preference
$ErrorActionPreference = 'Stop'

# Import required modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
$requiredModules = @(
    'Configuration',
    'LoggingModule', 
    'LockManager',
    'ShareCredentialHelper',
    'FileOperations',
    'ProgressTracking'
)

foreach ($module in $requiredModules) {
    try {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath "$module.psm1") -Force
    }
    catch {
        Write-Error "Failed to import module '$module': $_"
        exit 1
    }
}

# Main script execution
try {
    # Create single-instance lock
    $lockResult = New-ScriptLock -ScriptName $SCRIPT_NAME
    if (-not $lockResult.Success) {
        Write-Host "ERROR: $($lockResult.Message)" -ForegroundColor Red
        if ($lockResult.ExistingLock) {
            Write-Host "Existing lock details:" -ForegroundColor Yellow
            Write-Host "  Process ID: $($lockResult.ExistingLock.ProcessId)" -ForegroundColor Yellow
            Write-Host "  User: $($lockResult.ExistingLock.UserName)" -ForegroundColor Yellow
            Write-Host "  Lock Time: $($lockResult.ExistingLock.LockTime)" -ForegroundColor Yellow
        }
        exit 9
    }
    
    # Register cleanup handler
    Register-LockCleanup
    
    # Build runtime configuration
    $config = New-RuntimeConfiguration -Parameters $PSBoundParameters -ConfigFile $ConfigFile
    
    # Initialize logging
    $logDir = if ($LogPath) { 
        Split-Path -Path $LogPath -Parent 
    } else { 
        Join-Path -Path $PSScriptRoot -ChildPath 'script_logs' 
    }
    
    Initialize-LoggingModule -LogDirectory $logDir `
                            -MaxLogSizeMB $config.MaxLogSizeMB `
                            -MaxLogFiles $config.MaxLogFiles `
                            -DefaultLevel $(if ($VerbosePreference -eq 'Continue') { 'DEBUG' } else { 'INFO' })
    
    # Create main log stream
    $logFileName = if ($LogPath) { 
        Split-Path -Path $LogPath -Leaf 
    } else { 
        "$SCRIPT_NAME.log" 
    }
    
    New-LogStream -Name 'Main' -FileName $logFileName -Header @"
# Archive Retention Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Version: $SCRIPT_VERSION
# PowerShell: $($PSVersionTable.PSVersion)
# User: $env:USERDOMAIN\$env:USERNAME
# Machine: $env:COMPUTERNAME
"@
    
    # Create deletion log if in execute mode
    if ($Execute) {
        $retentionLogsDir = Join-Path -Path $logDir -ChildPath 'retention_actions'
        if (-not (Test-Path -Path $retentionLogsDir)) {
            New-Item -ItemType Directory -Path $retentionLogsDir -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $deletionLogName = "retention_${timestamp}.log"
        
        New-LogStream -Name 'Deletion' -FileName (Join-Path -Path 'retention_actions' -ChildPath $deletionLogName) -Header @"
# Retention Action Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Archive Path: $($config.ArchivePath ?? 'TBD')
# Retention Days: $($config.RetentionDays)
# Mode: $($PSCmdlet.ParameterSetName)
"@
    }
    
    Write-Log "Starting Archive Retention Script v$SCRIPT_VERSION" -Level INFO
    Write-Log "Configuration:" -Level INFO
    Write-Log "  Retention Days: $($config.RetentionDays)" -Level INFO
    Write-Log "  Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY RUN' })" -Level INFO
    Write-Log "  Parallel Threads: $($config.ParallelThreads)" -Level INFO
    
    # Handle network share if credential target specified
    $tempDriveName = $null
    if ($CredentialTarget) {
        Write-Log "Using credential target: $CredentialTarget" -Level INFO
        
        $credInfo = Get-ShareCredential -Target $CredentialTarget
        if (-not $credInfo) {
            throw "Failed to retrieve credential for target '$CredentialTarget'"
        }
        
        # Map network drive
        $tempDriveName = "ArchiveMount"
        try {
            New-PSDrive -Name $tempDriveName `
                       -PSProvider FileSystem `
                       -Root $credInfo.SharePath `
                       -Credential $credInfo.Credential `
                       -ErrorAction Stop | Out-Null
            
            $ArchivePath = "${tempDriveName}:"
            $config.ArchivePath = $ArchivePath
            Write-Log "Successfully mapped network drive to: $($credInfo.SharePath)" -Level INFO
        }
        catch {
            throw "Failed to map network drive: $_"
        }
    }
    else {
        # Normalize local path
        $config.ArchivePath = Get-NormalizedPath -Path $ArchivePath
    }
    
    # Validate configuration
    $validation = Test-Configuration -Config $config
    if (-not $validation.IsValid) {
        foreach ($error in $validation.Errors) {
            Write-Log "Configuration Error: $error" -Level ERROR
        }
        throw "Invalid configuration"
    }
    
    Write-Log "  Archive Path: $($config.ArchivePath)" -Level INFO
    Write-Log "  Include Types: $($config.IncludeFileTypes -join ', ')" -Level INFO
    if ($config.ExcludeFileTypes.Count -gt 0) {
        Write-Log "  Exclude Types: $($config.ExcludeFileTypes -join ', ')" -Level INFO
    }
    
    # Initialize progress tracking
    Initialize-ProgressTracking -UpdateInterval ([TimeSpan]::FromSeconds($config.ProgressUpdateIntervalSeconds))
    
    # Phase 1: File Discovery
    Write-Log "Phase 1: Starting file discovery..." -Level INFO
    New-ProgressActivity -Name 'Discovery' -Activity 'Discovering files for retention' -Status 'Initializing...'
    
    $fileTypeFilter = Get-FileTypeFilter -IncludeTypes $config.IncludeFileTypes `
                                        -ExcludeTypes $config.ExcludeFileTypes
    
    # Progress callback for file discovery
    $discoveryProgress = {
        param($Progress)
        Update-ProgressActivity -Name 'Discovery' `
                               -Status $Progress.Status `
                               -CurrentOperation $Progress.CurrentOperation `
                               -Force
    }
    
    $filesToProcess = Get-FilesForRetention -Path $config.ArchivePath `
                                           -CutoffDate $config.CutoffDate `
                                           -FileTypeFilter $fileTypeFilter `
                                           -ParallelThreads $config.ParallelThreads `
                                           -ProgressCallback $discoveryProgress
    
    Complete-ProgressActivity -Name 'Discovery' -FinalStatus "Found $($filesToProcess.Count) files"
    
    # Calculate total size
    $totalSize = ($filesToProcess | Measure-Object -Property Length -Sum).Sum
    $totalSizeFormatted = Format-ByteSize -Bytes $totalSize
    
    Write-Log "Discovery complete: Found $($filesToProcess.Count) files ($totalSizeFormatted) for retention" -Level INFO
    
    if ($filesToProcess.Count -gt 0) {
        # Show sample of files
        Write-Log "Sample of files to process:" -Level INFO
        $filesToProcess | Select-Object -First 5 | ForEach-Object {
            $age = [Math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 1)
            Write-Log "  $($_.Name) - $age days old - $(Format-ByteSize -Bytes $_.Length)" -Level INFO
        }
        if ($filesToProcess.Count -gt 5) {
            Write-Log "  ... and $($filesToProcess.Count - 5) more files" -Level INFO
        }
        
        # Phase 2: File Deletion (if Execute mode)
        if ($Execute) {
            Write-Log "Phase 2: Starting file deletion..." -Level INFO
            New-ProgressActivity -Name 'Deletion' `
                               -Activity 'Deleting files' `
                               -TotalItems $filesToProcess.Count `
                               -Status 'Starting deletion...'
            
            # Progress callback for deletion
            $deletionProgress = {
                param($Progress)
                Update-ProgressActivity -Name 'Deletion' `
                                       -ProcessedItems $Progress.ProcessedCount `
                                       -SuccessCount $Progress.SuccessCount `
                                       -ErrorCount $Progress.FailedCount `
                                       -Status $Progress.Status `
                                       -CurrentOperation $Progress.CurrentOperation `
                                       -Metrics @{ 
                                           ProcessedSize = Format-ByteSize -Bytes $Progress.ProcessedSize 
                                       }
            }
            
            # Deletion callback to log deleted files
            $deletionCallback = {
                param($File)
                Write-Log $File.FullName -StreamNames @('Deletion') -NoConsoleOutput -NoTimestamp
                Write-Log "Deleted: $($File.FullName)" -Level VERBOSE
            }
            
            $deleteResult = Remove-FilesWithRetry -Files $filesToProcess `
                                                 -MaxRetries $config.MaxRetries `
                                                 -RetryDelaySeconds $config.RetryDelaySeconds `
                                                 -BatchSize $config.BatchSize `
                                                 -ProgressCallback $deletionProgress `
                                                 -DeletionCallback $deletionCallback
            
            Complete-ProgressActivity -Name 'Deletion' `
                                    -FinalStatus "Processed $($deleteResult.ProcessedCount) files"
            
            Write-Log "Deletion complete:" -Level INFO
            Write-Log "  Total Files: $($deleteResult.TotalFiles)" -Level INFO
            Write-Log "  Successfully Deleted: $($deleteResult.SuccessCount)" -Level INFO
            Write-Log "  Failed: $($deleteResult.FailedCount)" -Level INFO
            
            if ($deleteResult.FailedCount -gt 0) {
                Write-Log "Failed deletions:" -Level WARNING
                $deleteResult.Errors | Select-Object -First 10 | ForEach-Object {
                    Write-Log "  $($_.File): $($_.Error)" -Level WARNING
                }
                if ($deleteResult.Errors.Count -gt 10) {
                    Write-Log "  ... and $($deleteResult.Errors.Count - 10) more errors" -Level WARNING
                }
            }
            
            # Phase 3: Empty Directory Cleanup
            if (-not $SkipDirCleanup) {
                Write-Log "Phase 3: Cleaning up empty directories..." -Level INFO
                
                $cleanupResult = Remove-EmptyDirectories -Path $config.ArchivePath -WhatIf:(-not $Execute)
                
                if ($cleanupResult.RemovedCount -gt 0) {
                    Write-Log "Removed $($cleanupResult.RemovedCount) empty directories" -Level INFO
                }
                else {
                    Write-Log "No empty directories found" -Level INFO
                }
                
                if ($cleanupResult.Errors.Count -gt 0) {
                    Write-Log "Directory cleanup errors:" -Level WARNING
                    $cleanupResult.Errors | Select-Object -First 5 | ForEach-Object {
                        Write-Log "  $($_.Directory): $($_.Error)" -Level WARNING
                    }
                }
            }
        }
        else {
            Write-Log "DRY RUN MODE - No files were deleted" -Level WARNING
            Write-Log "Run with -Execute parameter to actually delete files" -Level WARNING
        }
    }
    else {
        Write-Log "No files found matching retention criteria" -Level INFO
    }
    
    # Generate final report
    Write-ProgressReport -Title "Final Summary" -IncludeMetrics
    
    # Log completion
    $elapsed = (Get-Date) - $config.StartTime
    Write-Log "Script completed successfully in $(Format-TimeSpan -TimeSpan $elapsed)" -Level INFO
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level FATAL
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    exit 1
}
finally {
    # Cleanup
    if ($tempDriveName -and (Get-PSDrive -Name $tempDriveName -ErrorAction SilentlyContinue)) {
        Write-Log "Removing temporary drive mapping..." -Level DEBUG
        Remove-PSDrive -Name $tempDriveName -Force -ErrorAction SilentlyContinue
    }
    
    # Close all log streams
    Close-AllLogStreams
    
    # Remove script lock
    Remove-ScriptLock
}

# End of script