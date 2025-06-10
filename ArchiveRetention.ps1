# TODO: Fix file deletion logic - Currently, files are not being deleted when -Execute flag is used
# Issue: The script identifies files correctly but doesn't perform the actual deletions
# Next steps:
# 1. Locate where file processing and deletion should occur (likely in batch processing section)
# 2. Verify -Execute flag is properly checked before deletion
# 3. Add detailed logging around deletion operations
# 4. Test with small set of files before full run

# Script Parameters
[CmdletBinding(DefaultParameterSetName='Help')]
param (
    [Parameter(Mandatory=$true,
        Position=0,
        ParameterSetName='Execute',
        HelpMessage="Path to archive directory that needs to be processed")]
    [ValidateScript({
        if(-Not (Test-Path $_) ){
            throw "Archive path does not exist: $_"
        }
        return $true
    })]
    [string]$ArchivePath,
    
    [Parameter(Mandatory=$true,
        Position=1,
        ParameterSetName='Execute',
        HelpMessage="Number of days to retain files. Files older than this will be processed")]
    [ValidateRange(1,3650)]
    [int]$RetentionDays,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Add -Execute to actually delete/move files. Without this, script runs in dry-run mode")]
    [switch]$Execute,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Path to log file")]
    [string]$LogPath,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Maximum number of concurrent operations for parallel processing")]
    [ValidateRange(1,32)]
    [int]$MaxConcurrency = 8,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="File extensions to exclude (e.g., '.tmp', '.log')")]
    [string[]]$ExcludeFileTypes = @(),
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="File extensions to include. If specified, only these types will be processed")]
    [string[]]$IncludeFileTypes = @('.lca'),
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Maximum number of retries for failed operations")]
    [ValidateRange(0,10)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Delay in seconds between retry attempts")]
    [ValidateRange(1,300)]
    [int]$RetryDelaySeconds = 5,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Number of files to process in each batch")]
    [ValidateRange(100,5000)]
    [int]$BatchSize = 2000,

    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Enable caching of directory scanning results")]
    [switch]$UseCache,

    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Number of hours that the cache remains valid")]
    [ValidateRange(1,72)]
    [int]$CacheValidityHours = 12,

    [Parameter(ParameterSetName='Help')]
    [switch]$Help
)

# Show help if no parameters are provided or -Help is used
if ($PSCmdlet.ParameterSetName -eq 'Help') {
    $scriptName = $MyInvocation.MyCommand.Name
    Write-Host @"
Archive Retention Script
-----------------------
This script processes files older than a specified retention period.

USAGE:
    ./$scriptName -ArchivePath <path> -RetentionDays <days> [options]

REQUIRED PARAMETERS:
    -ArchivePath     Path to archive directory
    -RetentionDays   Number of days to retain files (1-3650)

COMMON OPTIONS:
    -Execute         Actually perform the operations (default: dry-run)
    -IncludeFileTypes Files to include (default: .lca)
    -ExcludeFileTypes Files to exclude (default: none)
    -UseCache        Enable caching (default: false)
    -MaxConcurrency  Max parallel operations (default: 8)

EXAMPLES:
    ./$scriptName -ArchivePath "\\server\share" -RetentionDays 90
    ./$scriptName -ArchivePath "D:\Logs" -RetentionDays 30 -Execute
    ./$scriptName -Help

For detailed help, use:
    Get-Help ./$scriptName -Detailed
"@
    exit
}

# Display help if no parameters are provided
if ($MyInvocation.BoundParameters.Count -eq 0) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit
}

<#
.SYNOPSIS
    Archives or deletes files older than specified retention period.

.DESCRIPTION
    This script processes files in a specified directory (including subdirectories) and either
    deletes or archives files that are older than the specified retention period.
    
    The script includes features like:
    - Parallel processing for better performance
    - Caching of directory scans
    - File type filtering
    - Detailed logging
    - Dry-run mode
    - Retry mechanism for network operations

.PARAMETER ArchivePath
    The root path to process files from. Can be a local path or UNC path.

.PARAMETER RetentionDays
    Number of days to retain files. Files older than this will be processed.

.PARAMETER Execute
    Switch to enable actual file operations. Without this, script runs in dry-run mode.

.PARAMETER LogFile
    Path to the log file. Defaults to script directory.

.PARAMETER MaxConcurrency
    Maximum number of concurrent operations. Default: 8

.PARAMETER ExcludeFileTypes
    Array of file extensions to exclude. Default: none

.PARAMETER IncludeFileTypes
    Array of file extensions to include. If specified, only these types will be processed.

.PARAMETER MaxRetries
    Maximum number of retries for failed operations. Default: 3

.PARAMETER RetryDelaySeconds
    Delay between retries in seconds. Default: 5

.PARAMETER BatchSize
    Number of files to process in each batch. Default: 2000

.PARAMETER UseCache
    Enable caching of directory scanning results. Default: False

.PARAMETER CacheValidityHours
    Number of hours that the cache remains valid. Default: 12

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "\\server\share" -RetentionDays 90
    Performs a dry run on network share, processing files older than 90 days

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "D:\Logs" -RetentionDays 30 -Execute
    Actually deletes files older than 30 days in D:\Logs

.EXAMPLE
    .\ArchiveRetention.ps1 -ArchivePath "E:\Data" -RetentionDays 180 -IncludeFileTypes @('.txt','.csv')
    Dry run processing only .txt and .csv files older than 180 days

.NOTES
    Requires PowerShell 5.1 or later
    Author: System Administrator
    Last Modified: 2025-01-22
#>

# Set script preferences
$ConfirmPreference = 'None'  # Disable confirmation prompts
$ErrorActionPreference = 'Stop'  # Make errors terminating by default

# Set up logging
if ([string]::IsNullOrEmpty($LogPath)) {
    $script:LogFile = Join-Path -Path $PSScriptRoot -ChildPath "ArchiveRetention.log"
} else {
    $script:LogFile = $LogPath
}

$script:MaxLogSizeMB = 10
$script:MaxLogFiles = 5

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
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [AllowEmptyString()]
        [string]$Message = " ",
        
        [Parameter(Position=1)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL', 'VERBOSE')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsoleOutput
    )
    
    # Handle empty, null, or whitespace-only messages
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "[Empty message]"
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
            'VERBOSE' { if ($VerbosePreference -eq 'Continue') { Write-Host $logMessage -ForegroundColor Gray } }
            default   { Write-Host $logMessage }
        }
    }
    
    # Write to log file if path is set
    if (-not [string]::IsNullOrEmpty($script:LogFile)) {
        try {
            # Check if log rotation is needed (every 100 log entries to reduce overhead)
            if ($script:LogEntryCount -ne -1) {
                $script:LogEntryCount++
                if ($script:LogEntryCount -ge 100) {
                    $script:LogEntryCount = 0
                    Invoke-LogRotation -LogFile $script:LogFile -MaxLogSizeMB 10 -MaxLogFiles 5
                }
            }
            
            # Append to log file
            Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
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
        $script:DeletionLogWriter = [System.IO.StreamWriter]::new($script:DeletionLogPath, $false, [System.Text.Encoding]::UTF8)
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

# Function to write log messages
# (Implementation is at the beginning of the script)

# Initialize logging
function Initialize-Logging {
    [CmdletBinding()]
    param(
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 5
    )
    
    try {
        # Ensure log directory exists
        $logDir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            Write-Log "Created log directory: $logDir" -Level INFO
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
        
        # Create or clear the log file
        try {
            # Create the log file with initial content
            @(
                "=================================================================",
                                "Script started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
                "Computer: $env:COMPUTERNAME",
                "User: $env:USERDOMAIN\$env:USERNAME",
                "Process ID: $PID",
                "Command line: $($MyInvocation.Line.Trim())",
                "Working directory: $PWD",
                "Script directory: $PSScriptRoot",
                "Log file: $script:LogFile",
                "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY RUN' })",
                "Maximum log size: $MaxLogSizeMB MB",
                "Maximum log files to keep: $MaxLogFiles",
                "================================================================="
            ) | Out-File -FilePath $script:LogFile -Encoding UTF8 -Force
            
            Write-Host "Logging initialized. Log file: $($script:LogFile)" -ForegroundColor Green
            
            # Initialize log entry counter
            $script:LogEntryCount = 0
            
        } catch {
            $errorMsg = "Failed to initialize log file '$($script:LogFile)': $($_.Exception.Message)"
            Write-Host "ERROR: $errorMsg" -ForegroundColor Red
            throw $errorMsg
        }
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
    if ($script:DeletionLogWriter) {
        try {
            if (-not $script:DeletionLogWriter.BaseStream.IsClosed) {
                $script:DeletionLogWriter.Flush()
                $script:DeletionLogWriter.Close()
            }
        }
        catch {
            Write-Error "Error closing deletion log writer: $($_.Exception.Message)"
        }
        finally {
            $script:DeletionLogWriter.Dispose()
            $script:DeletionLogWriter = $null
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
        [int]$MaxLogFiles = 5,
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
                
                # Create rotated log directory if it doesn't exist
                $rotatedLogsDir = Join-Path -Path $logDir -ChildPath "rotated_logs"
                if (-not (Test-Path -Path $rotatedLogsDir)) {
                    New-Item -ItemType Directory -Path $rotatedLogsDir -Force | Out-Null
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
        $allFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        
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
                Write-Log ("  {0} | {1} | {2} days old | {3:N2} MB" -f 
                    $_.Name,
                    $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
                    $age,
                    ($_.Length/1MB)) -Level INFO
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

# Function to clean up script resources and finalize execution
function Complete-ScriptExecution {
    [CmdletBinding()]
    param(
        [bool]$Success = $false,
        [string]$Message = $null
    )
    
    # Ensure Message is never null or empty
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "No additional information provided"
    }
    
    try {
        # Mark script as completed
        $script:completed = $true
        $script:endTime = [DateTime]::UtcNow
        
        # Calculate elapsed time
        if ($null -ne $script:startTime) {
            $elapsed = $script:endTime - $script:startTime
            $elapsedTime = $elapsed.ToString('hh\:mm\:ss\.fff')
        } else {
            $elapsedTime = "Unknown"
        }
        
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
        if ($Success) {
            Write-Log "=================================================================" -Level INFO
            Write-Log "SCRIPT COMPLETED SUCCESSFULLY" -Level INFO
            Write-Log "Execution time: $elapsedTime" -Level INFO
            if (![string]::IsNullOrEmpty($Message)) {
                Write-Log $Message -Level INFO
            }
            Write-Log "=================================================================" -Level INFO
        } else {
            Write-Log "=================================================================" -Level ERROR
            Write-Log "SCRIPT FAILED" -Level ERROR
            Write-Log "Execution time: $elapsedTime" -Level ERROR
            Write-Log "Error: $Message" -Level ERROR
            Write-Log "=================================================================" -Level ERROR
        }
        
        # Close the log writer
        Close-Logging
        
        # Return appropriate exit code
        if ($Success) {
            return 0
        } else {
            return 1
        }
    }
    catch {
        try {
            Write-Error "Error during script completion: $($_.Exception.Message)" -ErrorAction Continue
            Write-Error $_.ScriptStackTrace -ErrorAction Continue
        } catch {}
        return 1
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

# Main script execution
try {
    # Initialize logging with timestamp and rotation
    try {
        # Set max log size to 10MB and keep 5 rotated logs
        Initialize-Logging -MaxLogSizeMB 10 -MaxLogFiles 5
        
        # Set up log rotation for retention logs if in execute mode
        if ($Execute -and $script:DeletionLogPath) {
            $script:RetentionLogRotationParams = @{
                LogFile = $script:DeletionLogPath
                MaxLogSizeMB = 50
                MaxLogFiles = 7
                IsRetentionLog = $true
            }
            
            # Ensure the log rotation function is called for retention logs
            Invoke-LogRotation @script:RetentionLogRotationParams
        }
        
        Write-Log "=================================================================" -Level INFO
        Write-Log "Starting Archive Retention Script" -Level INFO
        Write-Log "Version: 1.0.0" -Level INFO
        Write-Log "=================================================================" -Level INFO
    }
    catch {
        Write-Error "Failed to initialize logging: $($_.Exception.Message)"
        exit 1
    }
    
    $scriptStartTime = Get-Date
    $mode = if ($Execute) { "EXECUTION" } else { "DRY RUN" }
    
    # Define cutoff date
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    
    # Log system and environment information
    $timezone = [System.TimeZoneInfo]::Local
    Write-Log "Script started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')" -Level INFO
    Write-Log "Script mode: $mode" -Level INFO
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level DEBUG
    Write-Log "OS: $([System.Environment]::OSVersion)" -Level DEBUG
    Write-Log "Current user: $([System.Environment]::UserDomainName)\$([System.Environment]::UserName)" -Level DEBUG
    Write-Log "Working directory: $(Get-Location)" -Level DEBUG
    Write-Log "Script directory: $PSScriptRoot" -Level DEBUG
    Write-Log "Log file: $script:LogFile" -Level INFO
    Write-Log "Script arguments: $($PSBoundParameters | ConvertTo-Json -Compress)" -Level DEBUG
    Write-Log "Time zone: $($timezone.DisplayName) (UTC$($timezone.BaseUtcOffset.Hours):$($timezone.BaseUtcOffset.Minutes))" -Level INFO
    Write-Log "Current local time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')" -Level DEBUG
    Write-Log "Current UTC time: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff'))" -Level DEBUG
    Write-Log "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
    
    # Validate and normalize the archive path
    try {
        Write-Log "Validating archive path: $ArchivePath" -Level INFO
        $ArchivePath = Get-NormalizedPath -Path $ArchivePath
        
        if (-not (Test-Path -Path $ArchivePath -PathType Container)) {
            throw "The specified path does not exist or is not a directory"
        }
        
        $archiveInfo = Get-Item -LiteralPath $ArchivePath -Force -ErrorAction Stop
        Write-Log "Archive path validated successfully" -Level INFO
        Write-Log "Archive location: $($archiveInfo.FullName)" -Level INFO
        Write-Log "Retention period: $RetentionDays days" -Level INFO
        
        # Check if path is a UNC path
        if ($ArchivePath -match '^\\\\') {
            Write-Log "Detected UNC path. Verifying network connectivity..." -Level DEBUG
            if (-not (Test-UNCPath -Path $ArchivePath)) {
                throw "Cannot access UNC path. Please verify network connectivity and permissions."
            }
            Write-Log "UNC path is accessible" -Level DEBUG
        }
    }
    catch {
        $errorMsg = "Failed to validate archive path '$ArchivePath': $($_.Exception.Message)"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
    
    # Log script configuration
    Write-Log "Script configuration:" -Level INFO
    Write-Log "  Archive Path: $ArchivePath" -Level INFO
    Write-Log "  Retention Period: $RetentionDays days (cutoff date: $($cutoffDate.ToString('yyyy-MM-dd')))" -Level INFO
    Write-Log "  Include File Types: $($IncludeFileTypes -join ', ')" -Level INFO
    Write-Log "  Exclude File Types: $($ExcludeFileTypes -join ', ')" -Level INFO
    Write-Log "  Mode: $(if ($Execute) { 'EXECUTION' } else { 'DRY RUN - No files will be deleted' })" -Level INFO
    Write-Log "  Max Concurrency: $MaxConcurrency" -Level DEBUG
    Write-Log "  Max Retries: $MaxRetries" -Level DEBUG
    Write-Log "  Retry Delay: ${RetryDelaySeconds}s" -Level DEBUG
    Write-Log "  Batch Size: $BatchSize" -Level DEBUG
    Write-Log "  Use Cache: $UseCache" -Level DEBUG
    Write-Log "  Cache Validity: ${CacheValidityHours}h" -Level DEBUG
    
    # Count files that would be processed
    Write-Log "Scanning for files older than $RetentionDays days..." -Level INFO
    $allFiles = Get-ChildItem -Path $ArchivePath -Recurse -File -Force -ErrorAction SilentlyContinue | 
               Where-Object { $_.LastWriteTime -lt $cutoffDate -and 
                              ($IncludeFileTypes.Count -eq 0 -or $IncludeFileTypes -contains $_.Extension) -and
                              ($ExcludeFileTypes.Count -eq 0 -or $ExcludeFileTypes -notcontains $_.Extension) }
    
    $totalSizeMB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Log "Found $($allFiles.Count) files ($totalSizeMB MB) that would be processed (older than $RetentionDays days)" -Level INFO
    
    if ($allFiles.Count -gt 0) {
        $oldestFile = $allFiles | Sort-Object LastWriteTime | Select-Object -First 1
        $newestFile = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Log "  Oldest file: $($oldestFile.Name) (Last modified: $($oldestFile.LastWriteTime))" -Level INFO
        Write-Log "  Newest file: $($newestFile.Name) (Last modified: $($newestFile.LastWriteTime))" -Level INFO
    }
    
    # Initialize counters and timers
    $script:processedSize = 0
    $script:processedCount = 0
    $script:totalSize = 0
    $script:totalFiles = 0
    $script:lastProgressUpdate = Get-Date
    $script:progressUpdateInterval = [TimeSpan]::FromSeconds(30)
    $script:discoveryStartTime = Get-Date
    
    # Set up progress tracking
    $script:progressActivity = "Processing Archive Retention"
    $script:progressStatus = "Starting..."
    $script:progressId = 1
    $script:progressPercent = 0
    
    # Register script completion handler
    $script:completed = $false
    $script:startTime = [DateTime]::UtcNow
    $script:endTime = $null
    
    Complete-ScriptExecution -Success $true -Message "Script completed successfully"
}
catch {
    $errorMsg = if ([string]::IsNullOrWhiteSpace($_.Exception.Message)) { "An unknown unhandled error occurred" } else { $_.Exception.Message }
    $fullErrorMsg = "Unhandled error: $errorMsg"
    Write-Log $fullErrorMsg -Level FATAL
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    Complete-ScriptExecution -Success $false -Message $errorMsg
    exit 1
}
finally {
    # Cleanup
    if (-not $script:completed) {
        Complete-ScriptExecution -Success $true
    }
}

# End of script