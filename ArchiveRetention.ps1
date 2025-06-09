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
    [switch]$UseCache = $true,

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
    -UseCache        Enable caching (default: true)
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
    Array of file extensions to exclude. Default: 

.PARAMETER IncludeFileTypes
    Array of file extensions to include. If specified, only these types will be processed.

.PARAMETER MaxRetries
    Maximum number of retries for failed operations. Default: 3

.PARAMETER RetryDelaySeconds
    Delay between retries in seconds. Default: 5

.PARAMETER BatchSize
    Number of files to process in each batch. Default: 2000

.PARAMETER UseCache
    Enable caching of directory scanning results. Default: True

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

# Add required .NET types for better performance
if (-not ('FastFileScanner' -as [Type])) {
Add-Type -TypeDefinition @"
    using System;
    using System.IO;
    using System.Linq;
    using System.Collections.Generic;
    using System.Collections.Concurrent;
    using System.Threading;
    using System.Threading.Tasks;

    public class FastFileScanner
    {
        private static readonly ConcurrentDictionary<string, DateTime> _connectionPool = new ConcurrentDictionary<string, DateTime>();
        
        public class FileData
        {
            public string Path { get; set; }
            public long Size { get; set; }
            public DateTime LastWriteTime { get; set; }
            public DateTime CreationTime { get; set; }
            public bool IsDirectory { get; set; }
        }

        public static void EnsureUncConnection(string path)
        {
            if (!path.StartsWith("\\\\")) return;
            
            string uncRoot = Path.GetPathRoot(path);
            if (!_connectionPool.ContainsKey(uncRoot))
            {
                _connectionPool.TryAdd(uncRoot, DateTime.UtcNow);
            }
        }

        public static async Task<FileData[]> ScanDirectoryAsync(string path, string[] includeTypes, string[] excludeTypes, CancellationToken token)
        {
            var results = new ConcurrentBag<FileData>();
            EnsureUncConnection(path);

            try
            {
                await ScanDirectoryInternalAsync(path, results, includeTypes, excludeTypes, token);
                return results.ToArray();
            }
            catch (Exception)
            {
                throw;
            }
        }

        private static async Task ScanDirectoryInternalAsync(string path, ConcurrentBag<FileData> results, string[] includeTypes, string[] excludeTypes, CancellationToken token)
        {
            try
            {
                var dirInfo = new DirectoryInfo(path);
                
                foreach (var file in dirInfo.EnumerateFiles())
                {
                    if (token.IsCancellationRequested) break;
                    
                    if (ShouldProcessFile(file.Name, includeTypes, excludeTypes))
                    {
                        results.Add(new FileData
                        {
                            Path = file.FullName,
                            Size = file.Length,
                            LastWriteTime = file.LastWriteTime,
                            CreationTime = file.CreationTime,
                            IsDirectory = false
                        });
                    }
                }

                var subDirTasks = new List<Task>();
                foreach (var dir in dirInfo.EnumerateDirectories())
                {
                    if (token.IsCancellationRequested) break;
                    
                    results.Add(new FileData
                    {
                        Path = dir.FullName,
                        Size = 0,
                        LastWriteTime = dir.LastWriteTime,
                        CreationTime = dir.CreationTime,
                        IsDirectory = true
                    });

                    subDirTasks.Add(ScanDirectoryInternalAsync(dir.FullName, results, includeTypes, excludeTypes, token));
                }

                await Task.WhenAll(subDirTasks);
            }
            catch (UnauthorizedAccessException) { }
            catch (PathTooLongException) { }
            catch (DirectoryNotFoundException) { }
        }

        private static bool ShouldProcessFile(string fileName, string[] includeTypes, string[] excludeTypes)
        {
            string ext = Path.GetExtension(fileName).ToLower();
            
            if (includeTypes != null && includeTypes.Length > 0)
                return includeTypes.Any(x => string.Equals(x, ext, StringComparison.OrdinalIgnoreCase));
            
            if (excludeTypes != null && excludeTypes.Length > 0)
                return !excludeTypes.Any(x => string.Equals(x, ext, StringComparison.OrdinalIgnoreCase));
            
            return true;
        }
    }
"@
}

# Initialize logging
function Initialize-Logging {
    try {
        # Create log directory if it doesn't exist
        $logDir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # Close existing writer if it exists
        if ($script:LogWriter) {
            try {
                $script:LogWriter.Flush()
                $script:LogWriter.Close()
                $script:LogWriter.Dispose()
            }
            catch { }
        }
        
        # Initialize StreamWriter with ASCII encoding
        $script:LogWriter = New-Object System.IO.StreamWriter($script:LogFile, $true, [System.Text.Encoding]::ASCII)
        Write-Log "Script started. Mode: $(if ($Execute) { 'Execute' } else { 'Dry Run' })"
    }
    catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
        Write-Error "Stack trace: $($_.ScriptStackTrace)"
        throw
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

# Disable confirmation prompts
$ConfirmPreference = 'None'

# Script Logging Configuration
$script:LogFile = $LogPath
$script:LogWriter = $null

# Function to write log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "DEBUG"   { if ($VerbosePreference -eq 'Continue') { Write-Host $logMessage -ForegroundColor Gray } }
        default   { Write-Host $logMessage }
    }
    
    # Write to log file if writer exists and is open
    if ($script:LogWriter -and -not $script:LogWriter.BaseStream.IsClosed) {
        try {
            $script:LogWriter.WriteLine($logMessage)
            $script:LogWriter.Flush()
        }
        catch {
            Write-Error "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

# Log levels
enum LogLevel {
    INFO
    WARNING
    ERROR
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
function Rotate-Logs {
    param (
        [string]$LogFile
    )

    # Create log directory if it doesn't exist
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Write-Host "Created log directory: $logDir"
        return
    }

    # Check if log file exists and needs rotation
    if (Test-Path $LogFile) {
        $logFileInfo = Get-Item $LogFile
        $logSizeMB = $logFileInfo.Length / 1MB

        if ($logSizeMB -ge 10) {
            # Remove oldest log if we're at max files
            $existingLogs = @(Get-ChildItem -Path $logDir -Filter "$(Split-Path $LogFile -Leaf).*" | 
                             Where-Object { $_.Name -match '.*\.\d+($|\.gz$)' } |
                             Sort-Object -Property Name -Descending)

            # Remove oldest logs if we're over the limit
            while ($existingLogs.Count -ge 5) {
                $oldestLog = $existingLogs[-1]
                Remove-Item $oldestLog.FullName -Force
                $existingLogs = $existingLogs[0..($existingLogs.Count-2)]
            }

            # Shift existing logs
            for ($i = $existingLogs.Count; $i -ge 1; $i--) {
                $currentLog = $existingLogs[$existingLogs.Count - $i]
                $baseName = Split-Path $LogFile -Leaf
                $newNumber = [int](($currentLog.Name -split '\.')[-1] -replace '\.gz$','') + 1
                $newName = Join-Path $logDir "$baseName.$newNumber"
                
                if ($true) {
                    $newName = "$newName.gz"
                }
                
                Move-Item $currentLog.FullName $newName -Force
            }

            # Rotate current log
            $newLog = "$LogFile.1"
            if ($true) {
                # Compress the log file
                try {
                    $gzipStream = [System.IO.Compression.FileStream]::new(
                        "$newLog.gz",
                        [System.IO.FileMode]::Create
                    )
                    $gzipArchive = [System.IO.Compression.GZipStream]::new(
                        $gzipStream, 
                        [System.IO.Compression.CompressionMode]::Compress
                    )
                    $fileStream = [System.IO.File]::OpenRead($LogFile)
                    $fileStream.CopyTo($gzipArchive)
                }
                finally {
                    if ($null -ne $fileStream) { $fileStream.Dispose() }
                    if ($null -ne $gzipArchive) { $gzipArchive.Dispose() }
                    if ($null -ne $gzipStream) { $gzipStream.Dispose() }
                }
            }
            else {
                Move-Item $LogFile $newLog -Force
            }

            # Create new empty log file
            New-Item -ItemType File -Path $LogFile -Force | Out-Null
        }
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

# Function to create a file info object
function New-FileInfo {
    param (
        [System.IO.FileInfo]$File
    )
    
    return [PSCustomObject]@{
        PSTypeName = 'FileInfo'
        Name = $File.Name
        FullName = $File.FullName
        Length = [long]$File.Length
        LastWriteTime = $File.LastWriteTime
    }
}

# Function to safely enumerate files in a directory
function Get-FilesRecursively {
    param (
        [string]$Path,
        [datetime]$CutoffDate
    )

    try {
        Write-Log "Starting optimized directory enumeration for: $Path"
        $startTime = Get-Date
        
        # Create cancellation token source
        $cts = New-Object System.Threading.CancellationTokenSource
        
        # Convert file type arrays for the scanner
        $includeTypes = if ($IncludeFileTypes) { 
            $IncludeFileTypes | ForEach-Object { if (!$_.StartsWith('.')) { ".$_" } else { $_ } }
        } else { @() }
        
        $excludeTypes = if ($ExcludeFileTypes) {
            $ExcludeFileTypes | ForEach-Object { if (!$_.StartsWith('.')) { ".$_" } else { $_ } }
        } else { @() }

        # Use the FastFileScanner to get all files and directories
        $scanTask = [FastFileScanner]::ScanDirectoryAsync($Path, $includeTypes, $excludeTypes, $cts.Token)
        $allItems = $scanTask.GetAwaiter().GetResult()
        
        # Filter and process results
        $files = $allItems | Where-Object { 
            -not $_.IsDirectory -and $_.LastWriteTime -lt $CutoffDate
        } | Select-Object @{
            Name='FullName'; Expression={$_.Path}
        }, @{
            Name='Length'; Expression={$_.Size}
        }, @{
            Name='LastWriteTime'; Expression={$_.LastWriteTime}
        }

        $elapsedTime = (Get-Date) - $startTime
        Write-Log "Directory enumeration completed in $($elapsedTime.TotalSeconds) seconds"
        Write-Log "Found $($files.Count) files older than cutoff date"
        
        return $files
    }
    catch {
        Write-Log "Error during optimized directory scan: $($_.Exception.Message)" -Level ERROR
        Write-Log $_.ScriptStackTrace -Level ERROR
        return @()
    }
    finally {
        if ($cts) { $cts.Dispose() }
    }
}

# Function to test UNC path access
function Test-UNCPath {
    param (
        [string]$Path
    )
    
    try {
        if ($Path -match '^\\\\\w+\\.*') {
            # Create a DirectoryInfo object to test access
            $dirInfo = New-Object System.IO.DirectoryInfo($Path)
            
            # Try to access the directory
            $null = $dirInfo.GetDirectories()
            return $true
        }
        return $false
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
    $pathHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($BasePath)
    ) | ForEach-Object { $_.ToString("x2") }
    
    $cacheDir = Join-Path $env:TEMP "ArchiveRetention"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    
    return Join-Path $cacheDir "cache_$($pathHash).json"
}

# Function to check if cache is valid
function Test-CacheValidity {
    param (
        [string]$CacheFile,
        [string]$BasePath,
        [int]$RetentionDays
    )
    
    if (-not (Test-Path $CacheFile)) { return $false }
    
    try {
        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
        $cacheAge = (Get-Date) - [DateTime]$cache.Timestamp
        
        # Cache is valid if:
        # 1. It's less than 4 hours old
        # 2. The base path matches
        # 3. The retention days match
        # 4. The directory structure hasn't changed
        if ($cacheAge.TotalHours -le 4 -and 
            $cache.BasePath -eq $BasePath -and 
            $cache.RetentionDays -eq $RetentionDays) {
            
            # Quick check if directory structure changed
            $dirCount = (Get-ChildItem -Path $BasePath -Directory -Recurse -ErrorAction SilentlyContinue).Count
            if ([int]$cache.DirectoryCount -eq $dirCount) {
                return $true
            }
        }
    }
    catch {
        Write-Log "Cache validation error: $($_.Exception.Message)" -Level WARNING
    }
    
    return $false
}

# Function to map directory structure
function Get-DirectoryMap {
    param (
        [string]$BasePath
    )
    
    try {
        Write-Log "Mapping directory structure..."
        $startTime = Get-Date
        $dirMap = @{
            Directories = New-Object System.Collections.Generic.List[string]
            TotalDirs = 0
            EstimatedFiles = 0
            DirectorySizes = @{}
        }
        
        # Use .NET for faster enumeration
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($BasePath)
        $lastUpdate = Get-Date
        $updateInterval = [TimeSpan]::FromSeconds(5)
        
        while ($stack.Count -gt 0) {
            $currentDir = $stack.Pop()
            $dirMap.Directories.Add($currentDir)
            $dirMap.TotalDirs++
            
            try {
                $di = New-Object System.IO.DirectoryInfo($currentDir)
                
                # Get quick file count and size estimate
                $files = $di.GetFiles()
                $dirMap.EstimatedFiles += $files.Count
                $dirMap.DirectorySizes[$currentDir] = ($files | Measure-Object -Property Length -Sum).Sum
                
                # Add subdirectories to stack
                foreach ($subDir in $di.GetDirectories()) {
                    $stack.Push($subDir.FullName)
                }
                
                # Show progress periodically
                $now = Get-Date
                if (($now - $lastUpdate) -gt $updateInterval) {
                    Write-Log "  Mapped $($dirMap.TotalDirs) directories, estimated $($dirMap.EstimatedFiles) files..."
                    $lastUpdate = $now
                }
            }
            catch {
                Write-Log "Warning: Cannot access directory $currentDir : $($_.Exception.Message)" -Level WARNING
                continue
            }
        }
        
        $duration = (Get-Date) - $startTime
        Write-Log "Directory mapping completed in $($duration.TotalSeconds.ToString('0.0')) seconds."
        Write-Log "Found $($dirMap.TotalDirs) directories containing approximately $($dirMap.EstimatedFiles) files."
        
        return $dirMap
    }
    catch {
        Write-Log "Error during directory mapping: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Function to check if file matches filters
function Test-FileTypeFilter {
    param (
        [string]$FileName,
        [string[]]$IncludeFileTypes,
        [string[]]$ExcludeFileTypes
    )
    
    $extension = [System.IO.Path]::GetExtension($FileName).ToLower()
    
    # If include types specified, file must match one
    if ($IncludeFileTypes -and $IncludeFileTypes.Count -gt 0) {
        return $IncludeFileTypes.Contains($extension)
    }
    
    # If exclude types specified, file must not match any
    if ($ExcludeFileTypes -and $ExcludeFileTypes.Count -gt 0) {
        return -not $ExcludeFileTypes.Contains($extension)
    }
    
    # If no filters specified, include all files
    return $true
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

try {
    # Initialize logging
    Initialize-Logging
    
    $scriptStartTime = Get-Date
    $mode = if ($Execute) { "Execution" } else { "Dry Run" }
    
    # Normalize the archive path
    $ArchivePath = Get-NormalizedPath -Path $ArchivePath
    Write-Log "Archive Path: $ArchivePath"
    Write-Log "Retention Period: $RetentionDays days"
    
    # Enhanced path validation for both local and UNC paths
    if ($ArchivePath -match '^\\\\\w+\\.*') {
        Write-Log "Validating UNC path access..."
        if (-not (Test-UNCPath -Path $ArchivePath)) {
            Write-Log "Cannot access UNC path. Please verify:" -Level ERROR
            Write-Log "1. Network connectivity to the remote system" -Level ERROR
            Write-Log "2. Share exists on the remote system" -Level ERROR
            Write-Log "3. You have appropriate permissions" -Level ERROR
            exit 1
        }
        Write-Log "UNC path validation successful"
    }
    elseif (-not (Test-Path -LiteralPath $ArchivePath)) {
        Write-Log "Archive path does not exist: $ArchivePath" -Level ERROR
        exit 1
    }
    
    Write-Log "Discovering files older than $RetentionDays days..."
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    Write-Log "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))"
    
    # Initialize counters
    $processedSize = 0
    $processedCount = 0
    $totalSize = 0
    $totalFiles = 0
    $lastProgressUpdate = Get-Date
    $progressUpdateInterval = [TimeSpan]::FromSeconds(30)
    $discoveryStartTime = Get-Date
    
    # First pass to get total size (with progress updates)
    Write-Log "Phase 1: Calculating total size of files to process..."
    $files = @()
    
    try {
        $cacheFile = Get-CacheFilePath -BasePath $ArchivePath
        if (Test-CacheValidity -CacheFile $cacheFile -BasePath $ArchivePath -RetentionDays $RetentionDays) {
            Write-Log "Using cached directory map..."
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $files = $cache.Files
        }
        else {
            Write-Log "No valid cache found. Mapping directory structure..."
            $dirMap = Get-DirectoryMap -BasePath $ArchivePath
            
            # Save cache for future runs
            $cache = @{
                Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                BasePath = $ArchivePath
                RetentionDays = $RetentionDays
                DirectoryCount = $dirMap.TotalDirs
                Files = @()
            }
            
            Write-Log "Enumerating files in mapped directories..."
            foreach ($dir in $dirMap.Directories) {
                try {
                    $filesInDir = Get-ChildItem -Path $dir -File -Recurse -ErrorAction SilentlyContinue
                    foreach ($file in $filesInDir) {
                        if ($file.LastWriteTime -and $file.LastWriteTime -is [DateTime] -and $file.LastWriteTime -lt $cutoffDate) {
                            $cache.Files += [PSCustomObject]@{
                                Name = $file.Name
                                FullName = $file.FullName
                                Length = [long]$file.Length
                                LastWriteTime = $file.LastWriteTime
                            }
                        }
                    }
                }
                catch {
                    Write-Log "Warning: Error enumerating files in directory $dir : $($_.Exception.Message)" -Level WARNING
                }
            }
            
            # Save cache to file
            $cacheJson = $cache | ConvertTo-Json -Depth 100
            Set-Content -Path $cacheFile -Value $cacheJson -Encoding UTF8 -Force
        }
        
        if ($files.Count -eq 0) {
            Write-Log "No files found matching the retention criteria (older than $RetentionDays days)."
            exit 0
        }

        $discoveryTime = (Get-Date) - $discoveryStartTime
        Write-Log "Phase 1 Complete - Found $($files.Count) files ($(Format-FileSize ($files | Measure-Object -Property Length -Sum).Sum)) in $($discoveryTime.TotalMinutes.ToString('0.0')) minutes"
        
        # Show files that would be processed
        Write-Log ""
        if ($VerbosePreference -eq 'Continue' -or $Execute) {
            Write-Log "All files to be processed:"
            $files | ForEach-Object {
                $age = Get-FileAge -LastWriteTime $_.LastWriteTime
                Write-Log "  $($_.FullName)" -Level $(if ($VerbosePreference -eq 'Continue') { "DEBUG" } else { "INFO" })
                Write-Log "    Age: $age days, Size: $(Format-FileSize $_.Length), Last Modified: $($_.LastWriteTime)" -Level $(if ($VerbosePreference -eq 'Continue') { "DEBUG" } else { "INFO" })
            }
        } else {
            Write-Log "Sample of files to be processed (showing first 10):"
            $files | Select-Object -First 10 | ForEach-Object {
                $age = Get-FileAge -LastWriteTime $_.LastWriteTime
                Write-Log "  $($_.FullName)"
                Write-Log "    Age: $age days, Size: $(Format-FileSize $_.Length), Last Modified: $($_.LastWriteTime)"
            }
            
            if ($files.Count -gt 10) {
                Write-Log "  ... and $($files.Count - 10) more files"
            }
        }
        Write-Log ""
        
        # Process files with enhanced progress tracking
        if ($files.Count -gt 0) {
            $lastProgressUpdate = Get-Date
            $processingStartTime = Get-Date
            $progressUpdateInterval = [TimeSpan]::FromSeconds(30)  
            $batchSize = 1000  
            $currentBatch = @()
            
            Write-Log ""
            Write-Log "Phase 2: Processing files..."
            Write-Log "Total files to process: $($files.Count)"
            
            $processedCount = 0
            $processedSize = 0
            $totalSize = Get-TotalFileSize -Files $files
            $errorCount = 0
            
            try {
                # Filter files based on include/exclude patterns
                if ($IncludeFileTypes -or $ExcludeFileTypes) {
                    $originalCount = $files.Count
                    $files = $files | Where-Object { 
                        Test-FileTypeFilter -FileName $_.FullName -IncludeFileTypes $IncludeFileTypes -ExcludeFileTypes $ExcludeFileTypes 
                    }
                    Write-Log "Filtered files based on type criteria: $($files.Count) of $originalCount files remain"
                }
                
                # Process files in batches
                foreach ($file in $files) {
                    try {
                        $currentBatch += $file
                        
                        if ($currentBatch.Count -ge $batchSize -or $file -eq $files[-1]) {
                            if ($Execute) {
                                foreach ($batchFile in $currentBatch) {
                                    Invoke-WithRetry -Operation {
                                        Remove-Item -LiteralPath $batchFile.FullName -Force
                                    } -Description "Delete file: $($batchFile.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
                                }
                            }
                            
                            $processedCount += $currentBatch.Count
                            $processedSize += ($currentBatch | Measure-Object -Property Length -Sum).Sum
                            $currentBatch = @()
                            
                            # Update progress
                            $now = Get-Date
                            if (($now - $lastProgressUpdate) -gt $progressUpdateInterval) {
                                $percentComplete = [Math]::Round(($processedCount / $files.Count) * 100, 1)
                                $rate = [Math]::Round($processedCount / ((Get-Date) - $processingStartTime).TotalSeconds, 1)
                                $remainingCount = $files.Count - $processedCount
                                $estimatedSecondsRemaining = $remainingCount / $rate
                                
                                Write-Log "Progress: $percentComplete% ($processedCount of $($files.Count) files)"
                                Write-Log "  Processed: $(Format-FileSize $processedSize) of $(Format-FileSize $totalSize)"
                                Write-Log "  Rate: $rate files/sec"
                                Write-Log "  Estimated time remaining: $([TimeSpan]::FromSeconds($estimatedSecondsRemaining).ToString('hh\:mm\:ss'))"
                                $lastProgressUpdate = $now
                            }
                        }
                    }
                    catch {
                        Write-Log "Error processing file $($file.FullName): $($_.Exception.Message)" -Level ERROR
                        $errorCount++
                        if ($errorCount -gt 100) {
                            Write-Log "Too many errors encountered. Stopping processing." -Level ERROR
                            throw "Excessive errors during processing"
                        }
                    }
                }
            }
            catch {
                Write-Log "Error during file processing: $($_.Exception.Message)" -Level ERROR
                Write-Log $_.ScriptStackTrace -Level ERROR
            }
            finally {
                # Final progress update
                Write-Log ""
                Write-Log "Phase 2 Complete:"
                Write-Log "  Total Files Processed: $processedCount of $($files.Count)"
                Write-Log "  Total Size Processed: $(Format-FileSize $processedSize) of $(Format-FileSize $totalSize)"
                Write-Log "  Processing Rate: $(Get-ProcessingRate -StartTime $processingStartTime -ProcessedCount $processedCount)"
                Write-Log "  Total Time: $(Get-ElapsedTime $processingStartTime)"
                if ($errorCount -gt 0) {
                    Write-Log "  Total Errors: $errorCount"
                }
            }
        }
    }
    catch {
        Write-Log "Error during file discovery: $($_.Exception.Message)" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
        exit 1
    }
    
    # Final summary with performance metrics
    $totalTime = (Get-Date) - $scriptStartTime
    $averageRate = Get-ProcessingRate -StartTime $scriptStartTime -ProcessedCount $files.Count
    $totalSize = Get-TotalFileSize -Files $files

    Write-Log ""
    Write-Log "Final Summary:"
    Write-Log "Total files processed: $($files.Count)"
    Write-Log "Total size processed: $(Format-FileSize $totalSize)"
    Write-Log "Total elapsed time: $($totalTime.TotalMinutes.ToString('0.0')) minutes"
    Write-Log "Average processing rate: $averageRate"
    Write-Log "Discovery time: $($discoveryTime.TotalMinutes.ToString('0.0')) minutes"
    Write-Log "Processing time: $(($totalTime - $discoveryTime).TotalMinutes.ToString('0.0')) minutes"
    if (-not $Execute) {
        Write-Log "This was a dry run. Use -Execute to perform actual deletions."
    }
}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    # Cleanup at script end
    try {
        Write-Log "Script completed."
        
        # Close log writer
        Close-Logging
    }
    catch {
        Write-Error "Error during cleanup: $($_.Exception.Message)"
    }
    finally {
        # Ensure writer is disposed even if there's an error
        Close-Logging
    }
}
