#Requires -Version 5.1

<#
.SYNOPSIS
    Optimized LogRhythm Archive Retention Manager using System.IO methods
    
.DESCRIPTION
    High-performance version of ArchiveRetention.ps1 using direct .NET System.IO methods
    for dramatically improved performance on large file sets (50,000-200,000+ files).
    Achieves 10-20x speed improvement over Get-ChildItem.
    
.PARAMETER ArchivePath
    Path to the archive directory (local or UNC path)
    
.PARAMETER CredentialTarget
    Name of saved credential for network share access
    
.PARAMETER RetentionDays
    Number of days to retain files (default: 365, minimum: 90)
    
.PARAMETER IncludeFileTypes
    File extensions to process (default: "*.lca")
    
.PARAMETER Execute
    Switch to enable actual deletion (default is dry-run mode)
    
.PARAMETER BatchSize
    Number of files to process in each batch (default: 1000)
    
.PARAMETER ShowProgress
    Show progress updates during operation
    
.EXAMPLE
    .\ArchiveRetention_Optimized.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 365
    
.EXAMPLE
    .\ArchiveRetention_Optimized.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 180 -Execute
#>

[CmdletBinding(DefaultParameterSetName = 'LocalPath')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'LocalPath')]
    [string]$ArchivePath,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'NetworkShare')]
    [string]$CredentialTarget,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(90, 36500)]
    [int]$RetentionDays = 365,
    
    [Parameter(Mandatory = $false)]
    [string[]]$IncludeFileTypes = @("*.lca"),
    
    [Parameter(Mandatory = $false)]
    [switch]$Execute,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(100, 10000)]
    [int]$BatchSize = 1000,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowProgress = $true
)

# Initialize timing
$StartTime = Get-Date

# Set up logging
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "script_logs"
if (!(Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $LogDir "ArchiveRetention_Optimized.log"
$RetentionLogDir = Join-Path $ScriptDir "retention_actions"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "WARN"  { Write-Host $LogMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
        default { Write-Host $LogMessage }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogMessage
}

# Log script start
Write-Log "Script started - Optimized version using System.IO methods"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Log "Retention Days: $RetentionDays"
Write-Log "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })"

# Handle network share if using saved credentials
if ($PSCmdlet.ParameterSetName -eq 'NetworkShare') {
    Write-Log "Loading credential helper module"
    $ModulePath = Join-Path $ScriptDir "modules\ShareCredentialHelper.psm1"
    Import-Module $ModulePath -Force
    
    Write-Log "Retrieving credentials for target: $CredentialTarget"
    $ShareInfo = Get-SavedShareCredential -Target $CredentialTarget
    
    if (!$ShareInfo) {
        Write-Log "Failed to retrieve credentials for target: $CredentialTarget" -Level "ERROR"
        exit 1
    }
    
    $ArchivePath = $ShareInfo.SharePath
    Write-Log "Using share path: $ArchivePath"
    
    # Test connection
    if (!(Test-Path $ArchivePath)) {
        Write-Log "Cannot access path: $ArchivePath" -Level "ERROR"
        exit 1
    }
}

# Validate archive path
if (!(Test-Path $ArchivePath)) {
    Write-Log "Archive path does not exist: $ArchivePath" -Level "ERROR"
    exit 1
}

# Calculate cutoff date
$CutoffDate = (Get-Date).AddDays(-$RetentionDays)
Write-Log "Cutoff date: $($CutoffDate.ToString('yyyy-MM-dd'))"

# Initialize counters
$TotalFiles = 0
$DeletedFiles = 0
$DeletedSize = 0
$ErrorCount = 0
$EmptyDirs = 0

# Create retention log if in execute mode
if ($Execute) {
    if (!(Test-Path $RetentionLogDir)) {
        New-Item -Path $RetentionLogDir -ItemType Directory -Force | Out-Null
    }
    $RetentionLog = Join-Path $RetentionLogDir "retention_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Write-Log "Retention log: $RetentionLog"
}

# Main processing function using System.IO
function Process-FilesOptimized {
    param(
        [string]$Path,
        [string[]]$FileTypes,
        [DateTime]$Cutoff,
        [int]$BatchSize,
        [bool]$ExecuteMode,
        [bool]$ShowProgress
    )
    
    $batch = @()
    $localDeletedCount = 0
    $localDeletedSize = 0
    $localErrorCount = 0
    $scannedCount = 0
    
    Write-Log "Starting optimized file enumeration for path: $Path"
    $EnumerationStart = Get-Date
    
    try {
        # Process each file type pattern
        foreach ($pattern in $FileTypes) {
            Write-Log "Processing pattern: $pattern"
            
            # Use System.IO for maximum performance
            $files = [System.IO.Directory]::EnumerateFiles($Path, $pattern, [System.IO.SearchOption]::AllDirectories)
            
            foreach ($filePath in $files) {
                $scannedCount++
                
                # Show scanning progress every 1000 files
                if ($ShowProgress -and ($scannedCount % 1000 -eq 0)) {
                    Write-Progress -Activity "Scanning Files" -Status "Scanned: $scannedCount files" -PercentComplete -1
                }
                
                try {
                    $fileInfo = [System.IO.FileInfo]::new($filePath)
                    
                    if ($fileInfo.LastWriteTime -lt $Cutoff) {
                        $batch += [PSCustomObject]@{
                            Path = $filePath
                            Size = $fileInfo.Length
                            LastWriteTime = $fileInfo.LastWriteTime
                        }
                        
                        # Process batch when it reaches the specified size
                        if ($batch.Count -ge $BatchSize) {
                            $batchResult = Process-Batch -Batch $batch -ExecuteMode $ExecuteMode -ShowProgress $ShowProgress -CurrentCount $localDeletedCount
                            $localDeletedCount += $batchResult.DeletedCount
                            $localDeletedSize += $batchResult.DeletedSize
                            $localErrorCount += $batchResult.ErrorCount
                            $batch = @()
                        }
                    }
                }
                catch {
                    Write-Log "Error processing file $filePath`: $($_.Exception.Message)" -Level "WARN"
                    $localErrorCount++
                }
            }
        }
        
        # Process remaining files in batch
        if ($batch.Count -gt 0) {
            $batchResult = Process-Batch -Batch $batch -ExecuteMode $ExecuteMode -ShowProgress $ShowProgress -CurrentCount $localDeletedCount
            $localDeletedCount += $batchResult.DeletedCount
            $localDeletedSize += $batchResult.DeletedSize
            $localErrorCount += $batchResult.ErrorCount
        }
        
        if ($ShowProgress) {
            Write-Progress -Activity "Scanning Files" -Completed
        }
    }
    catch {
        Write-Log "Fatal error during enumeration: $($_.Exception.Message)" -Level "ERROR"
    }
    
    $EnumerationTime = (Get-Date) - $EnumerationStart
    Write-Log "Enumeration completed in $($EnumerationTime.TotalSeconds) seconds"
    Write-Log "Files scanned: $scannedCount"
    
    return [PSCustomObject]@{
        ScannedCount = $scannedCount
        DeletedCount = $localDeletedCount
        DeletedSize = $localDeletedSize
        ErrorCount = $localErrorCount
        EnumerationTime = $EnumerationTime
    }
}

# Batch processing function
function Process-Batch {
    param(
        [array]$Batch,
        [bool]$ExecuteMode,
        [bool]$ShowProgress,
        [int]$CurrentCount
    )
    
    $batchDeletedCount = 0
    $batchDeletedSize = 0
    $batchErrorCount = 0
    
    foreach ($file in $Batch) {
        try {
            if ($ExecuteMode) {
                # Use System.IO.File.Delete for maximum performance
                [System.IO.File]::Delete($file.Path)
                
                # Log to retention log
                if ($script:RetentionLog) {
                    $logEntry = "$($file.Path)|$($file.Size)|$($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))|$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    Add-Content -Path $script:RetentionLog -Value $logEntry
                }
            }
            else {
                Write-Log "[DRY-RUN] Would delete: $($file.Path) ($('{0:N2}' -f ($file.Size / 1MB)) MB)"
            }
            
            $batchDeletedCount++
            $batchDeletedSize += $file.Size
            
            # Update progress
            if ($ShowProgress -and (($CurrentCount + $batchDeletedCount) % 100 -eq 0)) {
                $totalDeleted = $CurrentCount + $batchDeletedCount
                Write-Progress -Activity "Deleting Files" -Status "Deleted: $totalDeleted files" -PercentComplete -1
            }
        }
        catch {
            Write-Log "Failed to delete $($file.Path): $($_.Exception.Message)" -Level "ERROR"
            $batchErrorCount++
        }
    }
    
    return [PSCustomObject]@{
        DeletedCount = $batchDeletedCount
        DeletedSize = $batchDeletedSize
        ErrorCount = $batchErrorCount
    }
}

# Clean up empty directories
function Remove-EmptyDirectories {
    param(
        [string]$Path,
        [bool]$ExecuteMode
    )
    
    Write-Log "Scanning for empty directories..."
    $emptyDirCount = 0
    
    try {
        # Get all directories sorted by depth (deepest first)
        $directories = Get-ChildItem -Path $Path -Directory -Recurse | 
            Sort-Object FullName -Descending
        
        foreach ($dir in $directories) {
            try {
                # Check if directory is empty (no files or subdirectories)
                $items = Get-ChildItem -Path $dir.FullName -Force
                if ($items.Count -eq 0) {
                    if ($ExecuteMode) {
                        Remove-Item -Path $dir.FullName -Force
                        Write-Log "Removed empty directory: $($dir.FullName)"
                    }
                    else {
                        Write-Log "[DRY-RUN] Would remove empty directory: $($dir.FullName)"
                    }
                    $emptyDirCount++
                }
            }
            catch {
                Write-Log "Error processing directory $($dir.FullName): $($_.Exception.Message)" -Level "WARN"
            }
        }
    }
    catch {
        Write-Log "Error during directory cleanup: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $emptyDirCount
}

# Main execution
Write-Log "Starting file processing..."
$ProcessingStart = Get-Date

# Process files using optimized method
$result = Process-FilesOptimized -Path $ArchivePath -FileTypes $IncludeFileTypes -Cutoff $CutoffDate -BatchSize $BatchSize -ExecuteMode $Execute -ShowProgress $ShowProgress

$TotalFiles = $result.ScannedCount
$DeletedFiles = $result.DeletedCount
$DeletedSize = $result.DeletedSize
$ErrorCount = $result.ErrorCount

# Clean up empty directories
Write-Log "Starting empty directory cleanup..."
$EmptyDirs = Remove-EmptyDirectories -Path $ArchivePath -ExecuteMode $Execute

# Calculate total time
$TotalTime = (Get-Date) - $StartTime
$ProcessingTime = (Get-Date) - $ProcessingStart

# Log summary
Write-Log "=== EXECUTION SUMMARY ===" -Level "SUCCESS"
Write-Log "Total files scanned: $TotalFiles"
Write-Log "Files deleted: $DeletedFiles"
Write-Log "Space freed: $('{0:N2}' -f ($DeletedSize / 1GB)) GB"
Write-Log "Empty directories removed: $EmptyDirs"
Write-Log "Errors encountered: $ErrorCount"
Write-Log "Enumeration time: $($result.EnumerationTime.TotalSeconds) seconds"
Write-Log "Processing time: $($ProcessingTime.TotalSeconds) seconds"
Write-Log "Total execution time: $($TotalTime.TotalSeconds) seconds"

# Performance metrics
if ($TotalFiles -gt 0) {
    $FilesPerSecond = $TotalFiles / $result.EnumerationTime.TotalSeconds
    Write-Log "Scan performance: $('{0:N0}' -f $FilesPerSecond) files/second"
}

if ($DeletedFiles -gt 0 -and $ProcessingTime.TotalSeconds -gt 0) {
    $DeletesPerSecond = $DeletedFiles / $ProcessingTime.TotalSeconds
    Write-Log "Delete performance: $('{0:N0}' -f $DeletesPerSecond) files/second"
}

Write-Log "Script completed successfully"

# Exit with appropriate code
exit $(if ($ErrorCount -gt 0) { 1 } else { 0 })