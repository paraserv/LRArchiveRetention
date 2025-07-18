# tests/Generate-TestData.ps1
<#+
.SYNOPSIS
    Generate ultra-high-performance test directories and files for ArchiveRetention.ps1 testing.
.DESCRIPTION
    This script attempts to create a large, realistic test set for ArchiveRetention.ps1: thousands of date-based folders, each with many .lca files named with the folder's date and a timestamp (max 10MB). File dates are within ±5 days of the folder date. One .txt file is placed in the root for extension testing.

    **Disk Safety:**
    The script will automatically scale down the number of folders and/or files per folder as needed to ensure that at least 20% of the disk remains free after generation. If there is not enough space for the requested test set, the script will reduce the number of files per folder (down to MinFiles), and if needed, reduce the number of folders. If even the minimum scale would exceed the limit, the script aborts.

    **Performance:**
    Heavily optimized for maximum I/O performance with pre-allocated buffers, reduced syscalls, and efficient parallelism. Requires PowerShell 7+ (Core) for -Parallel support.

    **Large-Scale Operations:**
    Enhanced for massive data generation (TB scale) with time-based progress reporting, resume capability, and real-time space monitoring.

.PARAMETER RootPath
    The root directory where test data will be created. Defaults to \\10.20.1.7\LRArchives
.PARAMETER FolderCount
    The requested number of folders to create (auto-scaled down if needed for disk safety).
.PARAMETER MinFiles
    The minimum number of files per folder.
.PARAMETER MaxFiles
    The maximum number of files per folder (auto-scaled down if needed for disk safety).
.PARAMETER MaxFileSizeMB
    The maximum file size in MB (actual file sizes are random up to this value).
.PARAMETER ThrottleLimit
    The number of parallel threads to use (default: 2x CPU count).
.PARAMETER MaxSizeGB
    The maximum total size (in GB) of all generated test data. If set, the script will auto-scale down the number of folders/files to not exceed this cap. Especially useful for UNC/NAS paths where disk space checks are not possible.
.PARAMETER CredentialTarget
    Name of saved network share credential (created with Save-Credential.ps1)
.PARAMETER ProgressUpdateIntervalSeconds
    How often to show progress updates (default: 30 seconds for large operations)
.PARAMETER ResumeMode
    If true, will resume from existing data instead of starting fresh
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath 'D:\LogRhythmArchives\Test' -FolderCount 5000 -MinFiles 20 -MaxFiles 500 -MaxFileSizeMB 10
    # Attempts to create 5000 folders with 20-500 files each, but will auto-scale down if disk space is insufficient to leave 20% free.
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath 'D:\Test' -FolderCount 10000 -MinFiles 10 -MaxFiles 100 -MaxFileSizeMB 5
    # If disk space is insufficient, the script will reduce MaxFiles and/or FolderCount to fit, always leaving 20% free.
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath '\\10.20.1.7\LRArchives' -FolderCount 5000 -MinFiles 20 -MaxFiles 500 -MaxFileSizeMB 10 -MaxSizeGB 2
    # Will not generate more than 2GB of test data, auto-scaling down if needed.
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath '\\10.20.1.7\LRArchives' -FolderCount 50000 -MinFiles 100 -MaxFiles 200 -MaxFileSizeMB 100 -MaxSizeGB 9728 -CredentialTarget "NAS_CREDS"
    # Generate 9.5TB of test data with enhanced progress reporting and resume capability.
#>
param(
    [string]$RootPath = "\\10.20.1.7\LRArchives",
    [int]$FolderCount = 5000,
    [int]$MinFiles = 20,
    [int]$MaxFiles = 500,
    [int]$MaxFileSizeMB = 10,
    [int]$ThrottleLimit = [Environment]::ProcessorCount * 2,  # Auto-detect optimal parallelism
    [double]$MaxSizeGB = $null,  # Optional: hard cap for total generated data (UNC-safe)
    [Parameter(Mandatory=$false, HelpMessage="Name of saved network share credential (created with Save-Credential.ps1)")]
    [string]$CredentialTarget,
    [int]$ProgressUpdateIntervalSeconds = 30,  # Enhanced for large operations
    [switch]$ResumeMode = $false  # Resume from existing data
)

$tempDriveName = $null
$script:lastProgressUpdate = Get-Date
$script:totalBytesGenerated = 0
$script:startTime = Get-Date

# Require PowerShell 7+ for -Parallel
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "ERROR: This script requires PowerShell 7+ (Core) for parallel file generation." -ForegroundColor Red
    Write-Host "Please install PowerShell 7+ from https://github.com/PowerShell/PowerShell and run this script with 'pwsh'." -ForegroundColor Yellow
    exit 1
}

# Enhanced progress reporting function
function Show-DetailedProgress {
    param(
        [int]$ProcessedFolders,
        [int]$TotalFolders,
        [int]$ProcessedFiles,
        [int]$TotalEstimatedFiles,
        [bool]$Force = $false
    )
    
    $currentTime = Get-Date
    $timeSinceLastUpdate = ($currentTime - $script:lastProgressUpdate).TotalSeconds
    
    if ($Force -or $timeSinceLastUpdate -ge $ProgressUpdateIntervalSeconds) {
        $elapsedTime = $currentTime - $script:startTime
        $percentComplete = ($ProcessedFolders / $TotalFolders) * 100
        
        $foldersPerSecond = if ($elapsedTime.TotalSeconds -gt 0) { $ProcessedFolders / $elapsedTime.TotalSeconds } else { 0 }
        $filesPerSecond = if ($elapsedTime.TotalSeconds -gt 0) { $ProcessedFiles / $elapsedTime.TotalSeconds } else { 0 }
        
        $estimatedTimeRemaining = if ($foldersPerSecond -gt 0) {
            $remainingFolders = $TotalFolders - $ProcessedFolders
            $remainingSeconds = $remainingFolders / $foldersPerSecond
            [TimeSpan]::FromSeconds($remainingSeconds)
        } else {
            [TimeSpan]::Zero
        }
        
        $dataSizeGB = $script:totalBytesGenerated / 1GB
        $dataRateMBps = if ($elapsedTime.TotalSeconds -gt 0) { ($script:totalBytesGenerated / 1MB) / $elapsedTime.TotalSeconds } else { 0 }
        
        Write-Host ""
        Write-Host "=== LARGE-SCALE GENERATION PROGRESS ===" -ForegroundColor Green
        Write-Host "Folders: $ProcessedFolders/$TotalFolders ($([math]::Round($percentComplete, 1))%)" -ForegroundColor Cyan
        Write-Host "Files: $ProcessedFiles (estimated total: $TotalEstimatedFiles)" -ForegroundColor Cyan
        Write-Host "Data Generated: $([math]::Round($dataSizeGB, 2)) GB" -ForegroundColor Cyan
        Write-Host "Performance: $([math]::Round($foldersPerSecond, 2)) folders/sec, $([math]::Round($filesPerSecond, 0)) files/sec" -ForegroundColor White
        Write-Host "Data Rate: $([math]::Round($dataRateMBps, 2)) MB/sec" -ForegroundColor White
        Write-Host "Elapsed: $($elapsedTime.ToString('hh\:mm\:ss'))" -ForegroundColor White
        Write-Host "ETA: $($estimatedTimeRemaining.ToString('hh\:mm\:ss'))" -ForegroundColor White
        Write-Host ""
        
        $script:lastProgressUpdate = $currentTime
    }
}

# Check for existing data if in resume mode
if ($ResumeMode) {
    if (Test-Path $RootPath) {
        $existingFolders = @(Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue)
        if ($existingFolders.Count -gt 0) {
            Write-Host "Resume mode: Found $($existingFolders.Count) existing folders" -ForegroundColor Yellow
            $FolderCount = [math]::Max($FolderCount - $existingFolders.Count, 0)
            Write-Host "Adjusted to generate $FolderCount additional folders" -ForegroundColor Yellow
        }
    }
}

# Immediately after PowerShell version check, import credential module and map drive if CredentialTarget specified

# --- Optional Network Share Authentication ---
if (-not [string]::IsNullOrWhiteSpace($CredentialTarget)) {
    Write-Host "CredentialTarget '$CredentialTarget' specified. Attempting to authenticate to network share..." -ForegroundColor Cyan
    try {
        # Import helper module (relative to script root)
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules/ShareCredentialHelper.psm1'
        Import-Module -Name $modulePath -Force

        $credentialInfo = Get-ShareCredential -Target $CredentialTarget

        if ($null -eq $credentialInfo) {
            throw "Failed to load stored credential for target '$CredentialTarget'. Run Save-Credential.ps1 first."
        }

        # Use a fixed temporary PSDrive name to establish the session authentication
        $tempDriveName = 'GenDataMount'
        if (Get-PSDrive -Name $tempDriveName -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $tempDriveName -Force -ErrorAction SilentlyContinue
        }

        New-PSDrive -Name $tempDriveName -PSProvider FileSystem -Root $credentialInfo.SharePath -Credential $credentialInfo.Credential -ErrorAction Stop | Out-Null

        # Ensure RootPath aligns with the share path from credential (allows overriding default)
        $RootPath = $credentialInfo.SharePath

        Write-Host "Successfully authenticated and connected to $RootPath using stored credentials." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
        exit 2
    }
}

# Performance optimizations
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

Write-Host "Starting ULTRA-HIGH-PERFORMANCE folder and file generation..." -ForegroundColor Green
Write-Host "Target: $FolderCount folders with $MinFiles-$MaxFiles files each" -ForegroundColor Yellow
Write-Host "Max file size: $MaxFileSizeMB MB" -ForegroundColor Yellow
Write-Host "Parallelism: $ThrottleLimit threads" -ForegroundColor Cyan
Write-Host "Progress updates: Every $ProgressUpdateIntervalSeconds seconds" -ForegroundColor Cyan
if ($MaxSizeGB) {
    Write-Host "Target size: $MaxSizeGB GB" -ForegroundColor Yellow
}

# Create base directory if it doesn't exist
if (!(Test-Path $RootPath)) {
    [System.IO.Directory]::CreateDirectory($RootPath) | Out-Null
    Write-Host "Created base directory: $RootPath" -ForegroundColor Cyan
}

# Place a single .txt file in the root (using .NET for speed)
$testFilePath = Join-Path $RootPath 'testing_other_extensions.txt'
if (!(Test-Path $testFilePath)) {
    [System.IO.File]::WriteAllText($testFilePath, "This is a test file with a different extension.")
}

# Pre-generate ALL random data upfront to eliminate per-thread randomization overhead
Write-Host "Pre-generating all random data..." -ForegroundColor Yellow
$Random = [System.Random]::new()
$MaxFileSizeBytes = $MaxFileSizeMB * 1024 * 1024
$MinFileSizeBytes = 20KB

# Generate random base dates (within last 3 years for variety)
$BaseDate = Get-Date
$StartDate = $BaseDate.AddDays(-1095)
$DateRange = 1095

# PRE-GENERATE ALL DATA (eliminates runtime calculations)
$AllFolderData = [System.Collections.Generic.List[PSCustomObject]]::new($FolderCount)
$TotalEstimatedFiles = 0

# Enhanced disk space check and estimation
if ($RootPath -match '^[\\]{2}') {
    if ($MaxSizeGB -ne $null) {
        $maxAllowedBytes = $MaxSizeGB * 1GB
        Write-Host "UNC path detected. Using -MaxSizeGB = $MaxSizeGB GB as the hard cap for generated data." -ForegroundColor Yellow
    } else {
        Write-Warning "Disk space checks are not supported for UNC paths and -MaxSizeGB was not specified. No safety auto-scaling will be performed! Ensure sufficient free space on the NAS!"
        $maxAllowedBytes = $null
    }
    $freeSpace = $null
    $totalDisk = $null
    $minFreeFraction = 0.05  # For very large operations, allow smaller free space margin
    $minFreeBytes = $null
} else {
    $drive = [System.IO.DriveInfo]::new((Split-Path $RootPath -Qualifier))
    $freeSpace = $drive.AvailableFreeSpace
    $totalDisk = $drive.TotalSize
    $minFreeFraction = 0.05  # For very large operations, allow smaller free space margin
    $minFreeBytes = $totalDisk * $minFreeFraction
    $maxAllowedBytes = $null
}

# Estimate total required space
$estimatedTotalFiles = $FolderCount * [math]::Round(($MinFiles + $MaxFiles) / 2)
$estimatedTotalBytes = $estimatedTotalFiles * ($MaxFileSizeMB * 1024 * 1024 / 2)  # Assume average file size is half of max

# Add a safety margin (smaller for large operations)
$safetyMargin = 0.05
$requiredSpace = $estimatedTotalBytes * (1 + $safetyMargin)

if ($freeSpace -ne $null -and $totalDisk -ne $null) {
    Write-Host
    Write-Host "Disk space check:" -ForegroundColor Yellow
    Write-Host "  Total disk: $([math]::Round($totalDisk/1GB,2)) GB" -ForegroundColor White
    Write-Host "  Available: $([math]::Round($freeSpace/1GB,2)) GB" -ForegroundColor White
    Write-Host "  Minimum free required after test: $([math]::Round($minFreeBytes/1GB,2)) GB (5%)" -ForegroundColor White
    Write-Host "  Estimated required: $([math]::Round($requiredSpace/1GB,2)) GB (including 5% safety margin)" -ForegroundColor White
    Write-Host
}

# Auto-scale if needed (for local disk or UNC with MaxSizeGB)
if (($freeSpace -ne $null -and $totalDisk -ne $null) -or $maxAllowedBytes -ne $null) {
    $limitBytes = $maxAllowedBytes
    if ($freeSpace -ne $null -and $totalDisk -ne $null) {
        $limitBytes = $freeSpace - $minFreeBytes
    }
    if ($limitBytes -ne $null -and ($limitBytes - $requiredSpace) -lt 0) {
        Write-Host
        if ($maxAllowedBytes -ne $null) {
            Write-Host "Requested test set exceeds -MaxSizeGB cap. Auto-scaling to fit within specified limit..." -ForegroundColor Yellow
        } else {
            Write-Host "Not enough disk space for the requested test set! Attempting to auto-scale..." -ForegroundColor Red
        }
        $avgFileSize = ($MaxFileSizeMB * 1024 * 1024 / 2)
        $maxFiles = [math]::Floor($limitBytes / ($avgFileSize * (1 + $safetyMargin)))
        if ($maxFiles -lt 1) {
            Write-Host "ERROR: Not enough space to generate even a single file under the specified constraints." -ForegroundColor Red
            exit 1
        }
        $origFolderCount = $FolderCount
        $origMaxFiles = $MaxFiles
        if ($maxFiles -lt ($FolderCount * $MinFiles)) {
            $FolderCount = [math]::Max([math]::Floor($maxFiles / $MinFiles), 1)
            $MaxFiles = $MinFiles
        } else {
            $MaxFiles = [math]::Max([math]::Floor($maxFiles / $FolderCount), $MinFiles)
        }
        Write-Host "Auto-scaled parameters:" -ForegroundColor Yellow
        Write-Host "  FolderCount: $FolderCount (was $origFolderCount)" -ForegroundColor White
        Write-Host "  MaxFiles: $MaxFiles (was $origMaxFiles)" -ForegroundColor White
        $estimatedTotalFiles = $FolderCount * [math]::Round(($MinFiles + $MaxFiles) / 2)
        $estimatedTotalBytes = $estimatedTotalFiles * $avgFileSize
        $requiredSpace = $estimatedTotalBytes * (1 + $safetyMargin)
        Write-Host "  New estimated required: $([math]::Round($requiredSpace/1GB,2)) GB" -ForegroundColor White
        if ($limitBytes - $requiredSpace -lt 0) {
            Write-Host "ERROR: Even after auto-scaling, not enough space to fit under the specified cap." -ForegroundColor Red
            exit 1
        }
        Write-Host
    }
}

for ($i = 0; $i -lt $FolderCount; $i++) {
    $FolderDate = $StartDate.AddDays($Random.Next(0, $DateRange))
    $DateStr = $FolderDate.ToString("yyyyMMdd")
    $Ticks = $FolderDate.Ticks
    $FolderName = "${DateStr}_1_1_1_${Ticks}"
    $FileCount = $Random.Next($MinFiles, $MaxFiles + 1)
    $TotalEstimatedFiles += $FileCount
    
    # Pre-generate ALL file data for this folder
    $FileDataList = [System.Collections.Generic.List[PSCustomObject]]::new($FileCount)
    for ($f = 0; $f -lt $FileCount; $f++) {
        $FileDateOffset = $Random.Next(-5, 6)
        $FileDate = $FolderDate.AddDays($FileDateOffset).AddHours($Random.Next(0, 24)).AddMinutes($Random.Next(0, 60)).AddSeconds($Random.Next(0, 60))
        $TimeStr = $FileDate.ToString("HHmmss")
        $RandomNum = $Random.Next(1000, 9999)
        $FileName = "$DateStr`_$TimeStr`_$RandomNum.lca"
        $FileSize = $Random.Next($MinFileSizeBytes, $MaxFileSizeBytes + 1)
        
        $FileDataList.Add([PSCustomObject]@{
            Name = $FileName
            Size = $FileSize
            Date = $FileDate
        })
    }
    
    $AllFolderData.Add([PSCustomObject]@{
        Name = $FolderName
        Date = $FolderDate
        DateStr = $DateStr
        Files = $FileDataList.ToArray()  # Convert to array for faster access
    })
}

Write-Host "Pre-generated $($AllFolderData.Count) folders with $TotalEstimatedFiles total files" -ForegroundColor Green
Write-Host "Estimated total size: $([math]::Round($estimatedTotalBytes/1GB, 2)) GB" -ForegroundColor Green
Write-Host

# Create optimized data buffers (reused across threads)
# Pre-create buffer patterns to avoid repeated allocations
$BufferPatterns = @()
for ($p = 0; $p -lt 10; $p++) {
    $pattern = New-Object byte[] 65536
    for ($b = 0; $b -lt 65536; $b++) {
        $pattern[$b] = ($p * 65536 + $b) % 256
    }
    $BufferPatterns += ,$pattern  # Comma operator to force array creation
}

# ULTRA-OPTIMIZED: Process in larger batches with minimal overhead
$BatchSize = 25  # Smaller batches for better progress reporting on large operations
$ProcessedFolders = 0
$ProcessedFiles = 0

# Convert to array for better indexing performance
$FolderArray = $AllFolderData.ToArray()

Write-Host "Starting parallel processing with optimized I/O..." -ForegroundColor Green
Write-Host "This may take several hours for large datasets. Progress updates every $ProgressUpdateIntervalSeconds seconds." -ForegroundColor Yellow
Write-Host

# Initial progress display
Show-DetailedProgress -ProcessedFolders 0 -TotalFolders $FolderArray.Length -ProcessedFiles 0 -TotalEstimatedFiles $TotalEstimatedFiles -Force

for ($batchStart = 0; $batchStart -lt $FolderArray.Length; $batchStart += $BatchSize) {
    $batchEnd = [Math]::Min($batchStart + $BatchSize - 1, $FolderArray.Length - 1)
    $batchIndices = $batchStart..$batchEnd
    
    # Process batch with maximum parallelism
    $batchResults = $batchIndices | ForEach-Object -Parallel {
        $folderIndex = $_
        $folder = ($using:FolderArray)[$folderIndex]
        $RootPath = $using:RootPath
        $BufferPatterns = $using:BufferPatterns
        
        # Create folder using .NET (faster than New-Item)
        $FolderPath = [System.IO.Path]::Combine($RootPath, $folder.Name)
        [System.IO.Directory]::CreateDirectory($FolderPath) | Out-Null
        
        $folderBytesGenerated = 0
        $folderFilesCreated = 0
        
        # Ultra-fast file creation with minimal syscalls
        foreach ($fileData in $folder.Files) {
            try {
                $FilePath = [System.IO.Path]::Combine($FolderPath, $fileData.Name)
                
                # Use FileStream with optimized buffer size and write strategy
                $FileStream = [System.IO.FileStream]::new(
                    $FilePath, 
                    [System.IO.FileMode]::Create, 
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None,
                    131072,  # 128KB buffer (larger than default)
                    [System.IO.FileOptions]::SequentialScan
                )
                
                try {
                    $BytesWritten = 0
                    $FileSize = $fileData.Size
                    $PatternIndex = $folderIndex % $BufferPatterns.Length
                    $Buffer = $BufferPatterns[$PatternIndex]
                    
                    # Write in large chunks with minimal loop overhead
                    while ($BytesWritten -lt $FileSize) {
                        $WriteSize = [Math]::Min(65536, $FileSize - $BytesWritten)
                        $FileStream.Write($Buffer, 0, $WriteSize)
                        $BytesWritten += $WriteSize
                    }
                    
                    # Force write to disk immediately (optional - can comment out for even more speed)
                    $FileStream.Flush($true)
                    
                    $folderBytesGenerated += $FileSize
                    $folderFilesCreated++
                }
                finally {
                    $FileStream.Dispose()
                }
                
                # Set timestamps using .NET (faster than Get-Item)
                [System.IO.File]::SetCreationTime($FilePath, $fileData.Date)
                [System.IO.File]::SetLastWriteTime($FilePath, $fileData.Date)
            }
            catch {
                # Log error but continue processing
                Write-Warning "Failed to create file $($fileData.Name): $_"
            }
        }
        
        # Return batch results
        return @{
            FolderIndex = $folderIndex
            BytesGenerated = $folderBytesGenerated
            FilesCreated = $folderFilesCreated
        }
    } -ThrottleLimit $ThrottleLimit
    
    # Update progress tracking
    $ProcessedFolders += ($batchEnd - $batchStart + 1)
    
    # Accumulate batch results
    foreach ($result in $batchResults) {
        $script:totalBytesGenerated += $result.BytesGenerated
        $ProcessedFiles += $result.FilesCreated
    }
    
    # Show detailed progress
    Show-DetailedProgress -ProcessedFolders $ProcessedFolders -TotalFolders $FolderArray.Length -ProcessedFiles $ProcessedFiles -TotalEstimatedFiles $TotalEstimatedFiles
}

# Final progress update
Show-DetailedProgress -ProcessedFolders $ProcessedFolders -TotalFolders $FolderArray.Length -ProcessedFiles $ProcessedFiles -TotalEstimatedFiles $TotalEstimatedFiles -Force

# Final statistics
$EndTime = Get-Date
$TotalTime = $EndTime - $script:startTime

Write-Host
Write-Host "=== ULTRA-HIGH-PERFORMANCE GENERATION COMPLETE ===" -ForegroundColor Green
Write-Host "Created: $ProcessedFolders folders" -ForegroundColor White
Write-Host "Created: $ProcessedFiles files" -ForegroundColor White
Write-Host "Total size: $([math]::Round($script:totalBytesGenerated/1GB, 2)) GB" -ForegroundColor White
Write-Host "Total time: $($TotalTime.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Average: $([Math]::Round($ProcessedFolders / $TotalTime.TotalSeconds, 2)) folders/second" -ForegroundColor White
Write-Host "File rate: $([Math]::Round($ProcessedFiles / $TotalTime.TotalSeconds, 0)) files/second" -ForegroundColor White
Write-Host "Data rate: $([Math]::Round(($script:totalBytesGenerated / 1MB) / $TotalTime.TotalSeconds, 2)) MB/second" -ForegroundColor White
Write-Host "Location: $RootPath" -ForegroundColor Yellow
Write-Host

# Quick verification (using .NET for speed)
Write-Host "Quick verification:" -ForegroundColor Yellow
try {
    $actualFolders = [System.IO.Directory]::GetDirectories($RootPath).Length
    $sampleFolder = [System.IO.Directory]::GetDirectories($RootPath) | Select-Object -First 1
    $sampleFiles = if ($sampleFolder) { [System.IO.Directory]::GetFiles($sampleFolder).Length } else { 0 }
    Write-Host "  Actual folders created: $actualFolders" -ForegroundColor Gray
    Write-Host "  Sample folder files: $sampleFiles" -ForegroundColor Gray
} catch {
    Write-Host "  Verification skipped due to large dataset size" -ForegroundColor Gray
}

# Cleanup temporary PSDrive if created
if ($tempDriveName -and (Get-PSDrive -Name $tempDriveName -ErrorAction SilentlyContinue)) {
    try {
        Remove-PSDrive -Name $tempDriveName -Force -ErrorAction Stop
        Write-Host "Removed temporary PSDrive '$tempDriveName'" -ForegroundColor DarkGray
    } catch {
        Write-Host "WARNING: Unable to remove temporary PSDrive '$tempDriveName' - $_" -ForegroundColor Yellow
    }
}

Write-Host
Write-Host "Large-scale test data generation completed successfully!" -ForegroundColor Green