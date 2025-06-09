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
    [string]$LogPath = "$(Split-Path $MyInvocation.MyCommand.Path)\ArchiveRetention.log",

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
    [ValidateRange(1,10)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Delay in seconds between retries")]
    [ValidateRange(1,30)]
    [int]$RetryDelaySeconds = 5,

    [Parameter(Mandatory=$false,
        ParameterSetName='Execute',
        HelpMessage="Number of files to process in each batch")]
    [ValidateRange(100,10000)]
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

.PARAMETER LogPath
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
$script:LogFile = $LogPath
$script:LogLevel = 'INFO'  # Default log level
$script:LogWriter = $null

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
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [AllowEmptyString()]
        [string]$Message = " ",
        
        [Parameter(Position=1)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsoleOutput
    )
    
    # Ensure message is never null or empty
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "[Empty message]"
    } else {
        # Trim only non-empty messages to preserve intentional whitespace
        $Message = $Message.Trim()
    }
    
    # Skip if log level is below the minimum configured level
    $logLevels = @{ 
        'DEBUG' = 0
        'INFO' = 1
        'WARNING' = 2
        'ERROR' = 3
        'FATAL' = 4
    }
    
    $currentLevel = $script:LogLevel.ToUpper()
    if ($logLevels[$Level] -lt $logLevels[$currentLevel]) {
        return
    }
    
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $logMessage = "$timestamp [$Level] - $Message"
        
        # Write to console with appropriate color (unless suppressed)
        if (-not $NoConsoleOutput) {
            $params = @{
                Object = $logMessage
                NoNewline = $false
            }
            
            switch ($Level) {
                'FATAL'   { $params.ForegroundColor = 'DarkRed' }
                'ERROR'   { $params.ForegroundColor = 'Red' }
                'WARNING' { $params.ForegroundColor = 'Yellow' }
                'DEBUG'   { $params.ForegroundColor = 'Gray' }
                default   { $params.ForegroundColor = 'White' }
            }
            
            # Use write-host for color output, but only if host is interactive
            if ($host.UI.RawUI) {
                Write-Host @params
            } else {
                Write-Output $logMessage
            }
        }
        
        # Write to log file if writer is available
        if ($null -ne $script:LogWriter -and -not $script:LogWriter.BaseStream.IsClosed) {
            $retryCount = 0
            $maxRetries = 3
            $success = $false
            
            # Simple retry logic for file writes
            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    $script:LogWriter.WriteLine($logMessage)
                    $script:LogWriter.Flush()
                    $success = $true
                } catch [System.IO.IOException] {
                    $retryCount++
                    if ($retryCount -ge $maxRetries) {
                        throw
                    }
                    Start-Sleep -Milliseconds (100 * $retryCount)
                }
            }
        }
    } catch {
        # Last resort - write to error stream if logging fails
        Write-Error "Logging failed: $($_.Exception.Message)" -ErrorAction Continue
    }
}

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
                if (-not $script:LogWriter.BaseStream.IsClosed) {
                    $script:LogWriter.Flush()
                    $script:LogWriter.Close()
                }
            } catch {
                Write-Warning "Error closing existing log writer: $($_.Exception.Message)"
            } finally {
                if ($null -ne $script:LogWriter) {
                    $script:LogWriter.Dispose()
                    $script:LogWriter = $null
                }
            }
        }
        
        # Rotate logs if needed
        if (Test-Path -Path $script:LogFile) {
            Invoke-LogRotation -LogFile $script:LogFile -MaxLogSizeMB $MaxLogSizeMB -MaxLogFiles $MaxLogFiles
        }
        
        # Create new log file
        try {
            $script:LogWriter = [System.IO.StreamWriter]::new(
                $script:LogFile,
                $true,  # Append
                [System.Text.Encoding]::UTF8
            )
            
            # Write initial log entry
            Write-Log "=================================================================" -Level INFO
            Write-Log "Script started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
            Write-Log "Computer: $env:COMPUTERNAME" -Level INFO
            Write-Log "User: $env:USERDOMAIN\$env:USERNAME" -Level INFO
            Write-Log "Process ID: $PID" -Level INFO
            Write-Log "Command line: $($MyInvocation.Line.Trim())" -Level DEBUG
            Write-Log "Working directory: $PWD" -Level DEBUG
            Write-Log "Script directory: $PSScriptRoot" -Level DEBUG
            Write-Log "Log file: $script:LogFile" -Level INFO
            Write-Log "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY RUN' })" -Level INFO
            Write-Log "=================================================================" -Level INFO
        }
        catch {
            $errorMsg = "Failed to initialize log file '$script:LogFile': $($_.Exception.Message)"
            if ($null -ne $script:LogWriter) {
                $script:LogWriter.Dispose()
                $script:LogWriter = $null
            }
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
    if ($script:LogWriter) {
        try {
            if (-not $script:LogWriter.BaseStream.IsClosed) {
                $script:LogWriter.Flush()
                $script:LogWriter.Close()
            }
        }
        catch {
            Write-Error "Error closing log writer: $($_.Exception.Message)"
        }
        finally {
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
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

# Function to rotate logs
function Invoke-LogRotation {
    param (
        [string]$LogFile,
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 5
    )

    try {
        # Create log directory if it doesn't exist
        $logDir = Split-Path -Parent $LogFile
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            Write-Log "Created log directory: $logDir" -Level INFO
            return
        }

        # Skip if log file doesn't exist yet or is smaller than max size
        if (-not (Test-Path -Path $LogFile)) { return }
        
        $logFileInfo = Get-Item -Path $LogFile -ErrorAction Stop
        if (($logFileInfo.Length / 1MB) -lt $MaxLogSizeMB) { return }

        Write-Log "Rotating log file (Size: $([math]::Round($logFileInfo.Length / 1MB, 2)) MB)" -Level INFO

        # Get all rotated logs and sort by number (newest first)
        $logBaseName = Split-Path -Leaf $LogFile
        $logPattern = [System.Text.RegularExpressions.Regex]::Escape($logBaseName) + '(\.\d+)?$'
        
        $existingLogs = @(Get-ChildItem -Path $logDir -File | 
                         Where-Object { $_.Name -match $logPattern } |
                         Sort-Object -Property Name -Descending)

        # Remove oldest logs if we're over the limit (keep MaxLogFiles - 1 to make room for new one)
        for ($i = $MaxLogFiles - 1; $i -lt $existingLogs.Count; $i++) {
            $logToRemove = $existingLogs[$i].FullName
            try {
                Remove-Item -Path $logToRemove -Force -ErrorAction Stop
                Write-Log "Removed old log file: $logToRemove" -Level DEBUG
            } catch {
                Write-Log "Failed to remove old log file: $logToRemove - $($_.Exception.Message)" -Level WARNING
            }
        }

        # Rename existing logs (e.g., .1 to .2, .2 to .3, etc.)
        for ($i = [Math]::Min($existingLogs.Count, $MaxLogFiles - 2); $i -ge 0; $i--) {
            $currentLog = $existingLogs[$i].FullName
            $newNumber = $i + 1
            $newLog = "$LogFile.$newNumber"
            
            try {
                if (Test-Path -Path $currentLog) {
                    Move-Item -Path $currentLog -Destination $newLog -Force -ErrorAction Stop
                    Write-Log "Rotated log file: $currentLog -> $newLog" -Level DEBUG
                }
            } catch {
                Write-Log "Failed to rotate log file: $currentLog - $($_.Exception.Message)" -Level WARNING
            }
        }

        # Create new empty log file
        try {
            $null = New-Item -Path $LogFile -ItemType File -Force
            Write-Log "Created new log file: $LogFile" -Level DEBUG
        } catch {
            Write-Log "Failed to create new log file: $LogFile - $($_.Exception.Message)" -Level ERROR
            throw
        }
    } catch {
        Write-Log "Error during log rotation: $($_.Exception.Message)" -Level ERROR
        Write-Log $_.ScriptStackTrace -Level ERROR
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
        Initialize-Logging -MaxLogSizeMB 50 -MaxLogFiles 5
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
    Write-Log "  Retention Period: $RetentionDays days" -Level INFO
    Write-Log "  Include File Types: $($IncludeFileTypes -join ', ')" -Level INFO
    Write-Log "  Exclude File Types: $($ExcludeFileTypes -join ', ')" -Level INFO
    Write-Log "  Max Concurrency: $MaxConcurrency" -Level DEBUG
    Write-Log "  Max Retries: $MaxRetries" -Level DEBUG
    Write-Log "  Retry Delay: ${RetryDelaySeconds}s" -Level DEBUG
    Write-Log "  Batch Size: $BatchSize" -Level DEBUG
    Write-Log "  Use Cache: $UseCache" -Level DEBUG
    Write-Log "  Cache Validity: ${CacheValidityHours}h" -Level DEBUG
    
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
    
    # Set up a timer for periodic progress updates
    $script:progressTimer = [System.Timers.Timer]::new(5000)  # 5 second interval
    $script:progressTimer.AutoReset = $true
    $script:progressTimer.Enabled = $true
    
    # Register the progress update event
    Register-ObjectEvent -InputObject $script:progressTimer -EventName Elapsed -Action {
        try {
            if (-not $script:completed) {
                $elapsed = [DateTime]::UtcNow - $script:startTime
                $elapsedTime = "{0:hh\:mm\:ss}" -f ([DateTime]::Today.Add($elapsed))
                $progressParams = @{
                    Activity = $script:progressActivity
                    Status = "$($script:progressStatus) (Elapsed: $elapsedTime)"
                    PercentComplete = $script:progressPercent
                    CurrentOperation = "Processed $($script:processedCount) files ($([math]::Round($script:processedSize/1MB, 2)) MB)"
                    Id = $script:progressId
                }
                Write-Progress @progressParams
            }
        } catch {
            # Suppress any errors in the progress update
        }
    } | Out-Null
    
    # Start the timer
    $script:progressTimer.Start()
    
    # Phase 1: Discovery - Find all files matching criteria
    $script:progressStatus = "Discovering files..."
    Write-Log "=================================================================" -Level INFO
    Write-Log "PHASE 1: DISCOVERY" -Level INFO
    Write-Log "Finding all files matching the specified criteria" -Level INFO
    Write-Log "Using cache: $(if ($UseCache) { 'Yes' } else { 'No' })" -Level INFO
    Write-Log "Include file types: $($IncludeFileTypes -join ', ')" -Level DEBUG
    Write-Log "Exclude file types: $($ExcludeFileTypes -join ', ')" -Level DEBUG
    Write-Log "-----------------------------------------------------------------" -Level INFO
    $files = @()
    
    try {
        # Check cache first
        $cacheFile = Get-CacheFilePath -BasePath $ArchivePath
        $cacheValid = $UseCache -and (Test-CacheValidity -CacheFile $cacheFile -BasePath $ArchivePath -RetentionDays $RetentionDays -CacheValidityHours $CacheValidityHours)
        
        if ($cacheValid) {
            Write-Log "Loading files from cache..." -Level INFO
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $files = $cache.Files | ForEach-Object {
                [PSCustomObject]@{
                    FullName = $_.FullName
                    Name = $_.Name
                    Length = [long]$_.Length
                    LastWriteTime = [DateTime]$_.LastWriteTime
                }
            }
            Write-Log "Loaded $($files.Count) files from cache" -Level INFO
        }
        else {
            Write-Log "Scanning directory for files..." -Level INFO
            $fileItems = Get-FilesRecursively -Path $ArchivePath -CutoffDate $cutoffDate -IncludeFileTypes $IncludeFileTypes -ExcludeFileTypes $ExcludeFileTypes
            
            # Convert to consistent format
            $files = $fileItems | Select-Object @{
                Name='FullName'; Expression={$_.FullName}
            }, @{
                Name='Name'; Expression={$_.Name}
            }, @{
                Name='Length'; Expression={[long]$_.Length}
            }, @{
                Name='LastWriteTime'; Expression={$_.LastWriteTime}
            }
            
            # Save to cache if enabled
            if ($UseCache -and $files.Count -gt 0) {
                $cache = @{
                    Timestamp = (Get-Date).ToString('o')
                    BasePath = $ArchivePath
                    RetentionDays = $RetentionDays
                    Files = $files | Select-Object Name, FullName, Length, LastWriteTime
                }
                
                try {
                    $cache | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Force
                    Write-Log "Saved $($files.Count) files to cache" -Level INFO
                }
                catch {
                    Write-Log "Failed to save cache: $($_.Exception.Message)" -Level WARNING
                }
            }
        }
        
        if ($files.Count -eq 0) {
            Write-Log "No files found matching the retention criteria (older than $RetentionDays days)." -Level INFO
            Complete-ScriptExecution -Success $true -Message "No files to process"
            exit 0
        }

        $discoveryTime = (Get-Date) - $discoveryStartTime
        $totalSize = Get-TotalFileSize -Files $files
        Write-Log "Phase 1 Complete - Found $($files.Count) files ($(Format-FileSize $totalSize)) in $($discoveryTime.TotalMinutes.ToString('0.0')) minutes" -Level INFO
        
        # Show files that would be processed
        Write-Log " " -Level INFO
        if ($VerbosePreference -eq 'Continue') {
            Write-Log "All files to be processed:" -Level DEBUG
            $files | ForEach-Object {
                $age = Get-FileAge -LastWriteTime $_.LastWriteTime
                Write-Log "  $($_.FullName)" -Level DEBUG
                Write-Log "    Age: $age days, Size: $(Format-FileSize $_.Length), Last Modified: $($_.LastWriteTime)" -Level DEBUG
            }
        } else {
            Write-Log "Sample of files to be processed (showing first 10):" -Level INFO
            $files | Select-Object -First 10 | ForEach-Object {
                $age = Get-FileAge -LastWriteTime $_.LastWriteTime
                Write-Log "  $($_.FullName)" -Level INFO
                Write-Log "    Age: $age days, Size: $(Format-FileSize $_.Length), Last Modified: $($_.LastWriteTime)" -Level INFO
            }
            
            if ($files.Count -gt 10) {
                Write-Log "  ... and $($files.Count - 10) more files" -Level INFO
            }
        }
        Write-Log "" -Level INFO
        
        # Phase 2: Process files
        if ($files.Count -gt 0) {
            $script:progressStatus = "Processing files..."
            $processingStartTime = Get-Date
            
            Write-Log "=================================================================" -Level INFO
            Write-Log "PHASE 2: PROCESSING" -Level INFO
            Write-Log "Total files to process: $($files.Count)" -Level INFO
            Write-Log "Total size to process: $(Format-FileSize $totalSize)" -Level INFO
            Write-Log "-----------------------------------------------------------------" -Level INFO
            
            $processedCount = 0
            $processedSize = 0
            $errorCount = 0
            $successCount = 0
            
            # Process files in batches
            $currentBatch = @()
            $batchNumber = 0
            
            foreach ($file in $files) {
                $currentBatch += $file
                
                # Process batch when it reaches BatchSize or we're at the last file
                if ($currentBatch.Count -ge $BatchSize -or $file -eq $files[-1]) {
                    $batchNumber++
                    $batchStartTime = Get-Date
                    
                    Write-Log "Processing batch $batchNumber ($($currentBatch.Count) files)..." -Level DEBUG
                    
                    foreach ($batchFile in $currentBatch) {
                        try {
                            if ($Execute) {
                                # Actually delete the file
                                Invoke-WithRetry -Operation {
                                    Remove-Item -LiteralPath $batchFile.FullName -Force -ErrorAction Stop
                                } -Description "Delete file: $($batchFile.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
                                
                                Write-Log "Deleted: $($batchFile.FullName)" -Level DEBUG
                            } else {
                                # Dry run - just log what would be done
                                Write-Log "Would delete: $($batchFile.FullName)" -Level DEBUG
                            }
                            
                            $successCount++
                            $processedSize += $batchFile.Length
                        }
                        catch {
                            Write-Log "Error processing file $($batchFile.FullName): $($_.Exception.Message)" -Level ERROR
                            $errorCount++
                            
                            if ($errorCount -gt 100) {
                                Write-Log "Too many errors encountered. Stopping processing." -Level ERROR
                                throw "Excessive errors during processing"
                            }
                        }
                        
                        $processedCount++
                        $script:processedCount = $processedCount
                        $script:processedSize = $processedSize
                    }
                    
                    # Update progress
                    $percentComplete = [Math]::Round(($processedCount / $files.Count) * 100, 1)
                    $script:progressPercent = $percentComplete
                    
                    $now = Get-Date
                    if (($now - $script:lastProgressUpdate) -gt $script:progressUpdateInterval) {
                        $rate = Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount
                        $eta = Get-EstimatedTimeRemaining -StartTime $processingStartTime -ProcessedCount $processedCount -TotalCount $files.Count
                        
                        Write-Log "Progress: $percentComplete% ($processedCount of $($files.Count) files)" -Level INFO
                        Write-Log "  Processed: $(Format-FileSize $processedSize) of $(Format-FileSize $totalSize)" -Level INFO
                        Write-Log "  Success: $successCount, Errors: $errorCount" -Level INFO
                        Write-Log "  Rate: $rate" -Level INFO
                        Write-Log "  Estimated time remaining: $eta" -Level INFO
                        
                        $script:lastProgressUpdate = $now
                    }
                    
                    # Clear batch
                    $currentBatch = @()
                    
                    # Log batch completion
                    $batchTime = (Get-Date) - $batchStartTime
                    Write-Log "Batch $batchNumber completed in $($batchTime.TotalSeconds.ToString('0.0')) seconds" -Level DEBUG
                }
            }
            
            # Final summary for Phase 2
            $processingTime = (Get-Date) - $processingStartTime
            Write-Log " " -Level INFO
            Write-Log "Phase 2 Complete:" -Level INFO
            Write-Log "  Total Files Processed: $processedCount of $($files.Count)" -Level INFO
            Write-Log "  Successfully Processed: $successCount" -Level INFO
            Write-Log "  Failed: $errorCount" -Level INFO
            Write-Log "  Total Size Processed: $(Format-FileSize $processedSize) of $(Format-FileSize $totalSize)" -Level INFO
            Write-Log "  Processing Rate: $(Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount)" -Level INFO
            Write-Log "  Total Time: $(Get-ElapsedTime $processingStartTime)" -Level INFO
        }
    }
    catch {
        $errorMsg = if ([string]::IsNullOrWhiteSpace($_.Exception.Message)) { "An unknown error occurred" } else { $_.Exception.Message }
        Write-Log "Error during file processing: $errorMsg" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
        Complete-ScriptExecution -Success $false -Message $errorMsg
        exit 1
    }
    
    # Final summary
    $totalTime = (Get-Date) - $scriptStartTime
    $averageRate = if ($files.Count -gt 0 -and $totalTime.TotalSeconds -gt 0) {
        "$([math]::Round($files.Count / $totalTime.TotalSeconds, 1)) files/sec"
    } else {
        "N/A"
    }
    
    Write-Log "" -Level INFO
    Write-Log "=================================================================" -Level INFO
    Write-Log "FINAL SUMMARY" -Level INFO
    Write-Log "=================================================================" -Level INFO
    Write-Log "Mode: $mode" -Level INFO
    Write-Log "Total files processed: $($files.Count)" -Level INFO
    Write-Log "Total size: $(Format-FileSize $totalSize)" -Level INFO
    Write-Log "Total elapsed time: $($totalTime.TotalMinutes.ToString('0.0')) minutes" -Level INFO
    Write-Log "Average processing rate: $averageRate" -Level INFO
    Write-Log "Discovery time: $($discoveryTime.TotalMinutes.ToString('0.0')) minutes" -Level INFO
    if ($files.Count -gt 0) {
        Write-Log "Processing time: $(($totalTime - $discoveryTime).TotalMinutes.ToString('0.0')) minutes" -Level INFO
    }
    if (-not $Execute) {
        Write-Log "" -Level INFO
        Write-Log "*** This was a DRY RUN. No files were actually deleted. ***" -Level WARNING
        Write-Log "*** Use -Execute parameter to perform actual deletions. ***" -Level WARNING
    }
    
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