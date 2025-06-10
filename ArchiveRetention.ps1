# Script Parameters
[CmdletBinding(DefaultParameterSetName='Help')]
param (
    [Parameter(Mandatory=$true,
        Position=0,
        ParameterSetName='Execute',
        HelpMessage="Path to archive directory that needs to be processed")]
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
        HelpMessage="Maximum number of retries for failed operations")]
    [ValidateRange(0,10)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Delay in seconds between retry attempts")]
    [ValidateRange(1,300)]
    [int]$RetryDelaySeconds = 5,
    
    [Parameter(ParameterSetName='Help')]
    [switch]$Help
)

# Script version (single source of truth)
$SCRIPT_VERSION = '1.0.12'

# Show help if no parameters are provided or -Help is used
if ($PSCmdlet.ParameterSetName -eq 'Help') {
    $scriptName = $MyInvocation.MyCommand.Name
    Write-Host @"
Archive Retention Script v$SCRIPT_VERSION
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
    -MaxRetries      Maximum number of retries for failed operations. Default: 3
    -RetryDelaySeconds Delay between retries in seconds. Default: 5

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

.PARAMETER MaxRetries
    Maximum number of retries for failed operations. Default: 3

.PARAMETER RetryDelaySeconds
    Delay between retries in seconds. Default: 5

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

# Set script start time for accurate timing in summary (local time only)
$script:startTime = Get-Date

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
            }
            $lines = Get-Content -Path $script:DeletionLogPath
            if ($lines.Count -le 7) {  # Only header present
                Add-Content -Path $script:DeletionLogPath -Value "# No files were deleted or processed during this run."
            }
        } catch {}
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
    $defaultSuccessMsg = "Script completed successfully"
    try {
        # Mark script as completed
        $script:completed = $true
        $script:endTime = Get-Date
        
        # Calculate elapsed time
        $scriptCompleted = $script:endTime
        $tz = [System.TimeZoneInfo]::Local
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
        if ($Success) {
            $localTime = $scriptCompleted.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $statusLine = "SCRIPT COMPLETED SUCCESSFULLY (local: $localTime, elapsed: $elapsedTimeStr)"
            Write-Log $statusLine -Level INFO
            if (![string]::IsNullOrEmpty($Message) -and $Message -ne $defaultSuccessMsg -and $Message -ne 'No additional information provided') {
                Write-Log $Message -Level INFO
            }
        } else {
            Write-Log "Script completed at (local): $($scriptCompleted.ToString('yyyy-MM-dd HH:mm:ss.fff')) ($($tz.DisplayName))" -Level ERROR
            Write-Log "=================================================================" -Level ERROR
            Write-Log "SCRIPT FAILED" -Level ERROR
            Write-Log "Execution time: $elapsedTimeStr" -Level ERROR
            Write-Log "Error: $Message" -Level ERROR
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
    Write-Log "  Mode: $(if ($Execute) { 'EXECUTION' } else { 'DRY RUN - No files will be deleted' })" -Level INFO
    
    # Before file enumeration, add robust path validation and error handling.
    if (-not (Test-Path $ArchivePath)) {
        $msg = "ERROR: Archive path '$ArchivePath' does not exist or is not accessible. This may be due to network issues, permissions, or the path being unavailable in this session."
        Write-Log $msg -Level FATAL
        Write-Host $msg -ForegroundColor Red
        Write-Log "Current user: $([System.Environment]::UserDomainName)\$([System.Environment]::UserName)" -Level ERROR
        Write-Log "Working directory: $(Get-Location)" -Level ERROR
        Write-Log "If this is a network path, ensure it is accessible and that the script is running as a user with appropriate permissions." -Level ERROR
        exit 1
    }
    
    # Count files that would be processed
    Write-Log "Scanning for files older than $RetentionDays days..." -Level INFO
    try {
        $allFiles = Get-ChildItem -Path $ArchivePath -Recurse -File -Force -ErrorAction Stop
    } catch {
        Write-Log "Error enumerating files in path: $ArchivePath" -Level WARNING
        Write-Log "Exception: $($_.Exception.Message)" -Level WARNING
        Write-Log "StackTrace: $($_.ScriptStackTrace)" -Level WARNING
        $allFiles = @()
    }
    $allFiles = $allFiles | Where-Object { $_ -ne $null }
    
    $totalSizeMB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Log "Found $($allFiles.Count) files ($totalSizeMB MB) that would be processed (older than $RetentionDays days)" -Level INFO
    
    if ($allFiles.Count -gt 0) {
        $oldestFile = $allFiles | Sort-Object LastWriteTime | Select-Object -First 1
        $newestFile = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Log "  Oldest file: $($oldestFile.Name) (Last modified: $($oldestFile.LastWriteTime))" -Level INFO
        Write-Log "  Newest file: $($newestFile.Name) (Last modified: $($newestFile.LastWriteTime))" -Level INFO
    }

    # Initialize progress tracking variables
    $script:lastProgressUpdate = Get-Date
    $script:progressUpdateInterval = [TimeSpan]::FromSeconds(30)
    $processedCount = 0
    $processedSize = 0
    $errorCount = 0
    $successCount = 0
    $processingStartTime = Get-Date
    foreach ($file in $allFiles) {
        try {
            if ($Execute) {
                Invoke-WithRetry -Operation {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                } -Description "Delete file: $($file.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
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
        $now = Get-Date
        $elapsedSeconds = [math]::Round(($now - $processingStartTime).TotalSeconds, 1)
        if (($now - $script:lastProgressUpdate) -gt $script:progressUpdateInterval) {
            $percentComplete = [Math]::Round(($processedCount / $allFiles.Count) * 100, 1)
            $rate = Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount
            $eta = Get-EstimatedTimeRemaining -StartTime $processingStartTime -ProcessedCount $processedCount -TotalCount $allFiles.Count
            Write-Log "Progress: $percentComplete% ($processedCount of $($allFiles.Count) files) at $elapsedSeconds seconds run-time" -Level INFO
            Write-Log "  Processed: $([math]::Round($processedSize/1MB,2)) MB of $totalSizeMB MB" -Level INFO
            Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
            Write-Log "  Rate: $rate" -Level INFO
            Write-Log "  Estimated time remaining: $eta" -Level INFO
            $script:lastProgressUpdate = $now
        }
    }
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
    Write-Log " " -Level INFO
    Write-Log "Processing Complete:" -Level INFO
    Write-Log "  Total Files Processed: $processedCount of $($allFiles.Count)" -Level INFO
    Write-Log "  Successfully Processed: $successCount" -Level INFO
    Write-Log "  Failed: $errorCount" -Level INFO
    Write-Log "  Total Size Processed: $([math]::Round($processedSize/1MB,2)) MB of $totalSizeMB MB" -Level INFO
    Write-Log "  Processing Rate: $(Get-ProcessingRate -StartTime $script:startTime -ProcessedCount $processedCount)" -Level INFO
    Write-Log "  Elapsed Time: $elapsedTimeStr" -Level INFO

    # After the main loop, always log a final progress update at 100% with total elapsed time
    $finalElapsedSeconds = [math]::Round(((Get-Date) - $processingStartTime).TotalSeconds, 1)
    Write-Log "Progress: 100% ($processedCount of $($allFiles.Count) files) at $finalElapsedSeconds seconds run-time" -Level INFO
    Write-Log "  Processed: $([math]::Round($processedSize/1MB,2)) MB of $totalSizeMB MB" -Level INFO
    Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
    Write-Log "  Rate: $(Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount)" -Level INFO
    Write-Log "  Estimated time remaining: 0 minutes" -Level INFO

    # --- Empty Directory Cleanup ---
    try {
        $emptyDirs = Get-ChildItem -Path $ArchivePath -Recurse -Directory | Sort-Object FullName -Descending
        $removedCount = 0
        foreach ($dir in $emptyDirs) {
            # Never remove the root archive path itself
            if ($dir.FullName -eq (Resolve-Path $ArchivePath)) { continue }
            $children = Get-ChildItem -Path $dir.FullName -Force
            if ($children.Count -eq 0) {
                if ($Execute) {
                    try {
                        Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
                        Write-Log "Removed empty directory: $($dir.FullName)" -Level DEBUG
                        $removedCount++
                    } catch {
                        Write-Log "Failed to remove empty directory: $($dir.FullName) - $($_.Exception.Message)" -Level WARNING
                    }
                } else {
                    Write-Log "Would remove empty directory: $($dir.FullName)" -Level DEBUG
                    $removedCount++
                }
            }
        }
        if ($removedCount -gt 0) {
            $msg = if ($Execute) { "Removed $removedCount empty directories under $ArchivePath" } else { "Would remove $removedCount empty directories under $ArchivePath (dry-run)" }
            Write-Log $msg -Level INFO
        } else {
            Write-Log "No empty directories found to remove under $ArchivePath" -Level INFO
        }
    } catch {
        Write-Log "Error during empty directory cleanup: $($_.Exception.Message)" -Level WARNING
    }
    # --- End Empty Directory Cleanup ---

    Complete-ScriptExecution -Success $true
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