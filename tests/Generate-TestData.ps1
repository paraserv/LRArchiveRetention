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
.PARAMETER RootPath
    The root directory where test data will be created. Defaults to D:\LogRhythmArchives\Test
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
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath 'D:\LogRhythmArchives\Test' -FolderCount 5000 -MinFiles 20 -MaxFiles 500 -MaxFileSizeMB 10
    # Attempts to create 5000 folders with 20-500 files each, but will auto-scale down if disk space is insufficient to leave 20% free.
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath 'D:\Test' -FolderCount 10000 -MinFiles 10 -MaxFiles 100 -MaxFileSizeMB 5
    # If disk space is insufficient, the script will reduce MaxFiles and/or FolderCount to fit, always leaving 20% free.
#>
param(
    [string]$RootPath = "D:\LogRhythmArchives\Test",
    [int]$FolderCount = 5000,
    [int]$MinFiles = 20,
    [int]$MaxFiles = 500,
    [int]$MaxFileSizeMB = 10,
    [int]$ThrottleLimit = [Environment]::ProcessorCount * 2  # Auto-detect optimal parallelism
)

# Require PowerShell 7+ for -Parallel
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "ERROR: This script requires PowerShell 7+ (Core) for parallel file generation." -ForegroundColor Red
    Write-Host "Please install PowerShell 7+ from https://github.com/PowerShell/PowerShell and run this script with 'pwsh'." -ForegroundColor Yellow
    exit 1
}

# Performance optimizations
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

Write-Host "Starting ULTRA-HIGH-PERFORMANCE folder and file generation..." -ForegroundColor Green
Write-Host "Target: $FolderCount folders with $MinFiles-$MaxFiles files each" -ForegroundColor Yellow
Write-Host "Parallelism: $ThrottleLimit threads" -ForegroundColor Cyan

# Create base directory if it doesn't exist
if (!(Test-Path $RootPath)) {
    [System.IO.Directory]::CreateDirectory($RootPath) | Out-Null
    Write-Host "Created base directory: $RootPath" -ForegroundColor Cyan
}

# Place a single .txt file in the root (using .NET for speed)
$testFilePath = Join-Path $RootPath 'testing_other_extensions.txt'
[System.IO.File]::WriteAllText($testFilePath, "This is a test file with a different extension.")

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

# Disk space check and estimation
$drive = [System.IO.DriveInfo]::new((Split-Path $RootPath -Qualifier))
$freeSpace = $drive.AvailableFreeSpace
$totalDisk = $drive.TotalSize
$minFreeFraction = 0.2  # Leave at least 20% free
$minFreeBytes = $totalDisk * $minFreeFraction

# Estimate total required space
$estimatedTotalFiles = $FolderCount * [math]::Round(($MinFiles + $MaxFiles) / 2)
$estimatedTotalBytes = $estimatedTotalFiles * ($MaxFileSizeMB * 1024 * 1024 / 2)  # Assume average file size is half of max

# Add a safety margin (e.g., require 10% extra for overhead)
$safetyMargin = 0.1
$requiredSpace = $estimatedTotalBytes * (1 + $safetyMargin)

Write-Host "\nDisk space check:" -ForegroundColor Yellow
Write-Host "  Total disk: $([math]::Round($totalDisk/1GB,2)) GB" -ForegroundColor White
Write-Host "  Available: $([math]::Round($freeSpace/1GB,2)) GB" -ForegroundColor White
Write-Host "  Minimum free required after test: $([math]::Round($minFreeBytes/1GB,2)) GB (20%)" -ForegroundColor White
Write-Host "  Estimated required: $([math]::Round($requiredSpace/1GB,2)) GB (including 10% safety margin)" -ForegroundColor White

# Auto-scale if needed
if (($freeSpace - $requiredSpace) -lt $minFreeBytes) {
    Write-Host "\nWARNING: Not enough disk space for the requested test set! Attempting to auto-scale..." -ForegroundColor Red
    # Calculate max allowed bytes for test data
    $maxAllowedBytes = $freeSpace - $minFreeBytes
    if ($maxAllowedBytes -le 0) {
        Write-Host "ERROR: Not enough disk space to generate any test data while leaving 20% free." -ForegroundColor Red
        exit 1
    }
    # Estimate new total files
    $avgFileSize = ($MaxFileSizeMB * 1024 * 1024 / 2)
    $maxFiles = [math]::Floor($maxAllowedBytes / ($avgFileSize * (1 + $safetyMargin)))
    if ($maxFiles -lt 1) {
        Write-Host "ERROR: Not enough disk space to generate even a single file." -ForegroundColor Red
        exit 1
    }
    # Adjust FolderCount and/or MaxFiles to fit
    $origFolderCount = $FolderCount
    $origMaxFiles = $MaxFiles
    if ($maxFiles -lt ($FolderCount * $MinFiles)) {
        # Not enough for MinFiles per folder, reduce FolderCount
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
    if (($freeSpace - $requiredSpace) -lt $minFreeBytes) {
        Write-Host "ERROR: Even after auto-scaling, not enough disk space to leave 20% free." -ForegroundColor Red
        exit 1
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
$BatchSize = 200  # Larger batches = less overhead
$ProcessedFolders = 0
$StartTime = Get-Date

# Convert to array for better indexing performance
$FolderArray = $AllFolderData.ToArray()

Write-Host "Starting parallel processing with optimized I/O..." -ForegroundColor Green

for ($batchStart = 0; $batchStart -lt $FolderArray.Length; $batchStart += $BatchSize) {
    $batchEnd = [Math]::Min($batchStart + $BatchSize - 1, $FolderArray.Length - 1)
    $batchIndices = $batchStart..$batchEnd
    
    # Process batch with maximum parallelism
    $batchIndices | ForEach-Object -Parallel {
        $folderIndex = $_
        $folder = ($using:FolderArray)[$folderIndex]
        $RootPath = $using:RootPath
        $BufferPatterns = $using:BufferPatterns
        
        # Create folder using .NET (faster than New-Item)
        $FolderPath = [System.IO.Path]::Combine($RootPath, $folder.Name)
        [System.IO.Directory]::CreateDirectory($FolderPath) | Out-Null
        
        # Ultra-fast file creation with minimal syscalls
        foreach ($fileData in $folder.Files) {
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
            }
            finally {
                $FileStream.Dispose()
            }
            
            # Set timestamps using .NET (faster than Get-Item)
            [System.IO.File]::SetCreationTime($FilePath, $fileData.Date)
            [System.IO.File]::SetLastWriteTime($FilePath, $fileData.Date)
        }
    } -ThrottleLimit $ThrottleLimit
    
    # Progress reporting (less frequent for better performance)
    $ProcessedFolders += ($batchEnd - $batchStart + 1)
    $ElapsedTime = (Get-Date) - $StartTime
    
    if ($ProcessedFolders % 500 -eq 0 -or $ProcessedFolders -eq $FolderArray.Length) {
        $FoldersPerSecond = [Math]::Round($ProcessedFolders / $ElapsedTime.TotalSeconds, 2)
        $EstimatedTotal = if ($ProcessedFolders -eq $FolderArray.Length) { 
            $ElapsedTime.TotalMinutes 
        } else { 
            [Math]::Round(($FolderArray.Length / $ProcessedFolders) * $ElapsedTime.TotalMinutes, 1) 
        }
        Write-Host "Processed $ProcessedFolders/$($FolderArray.Length) folders ($FoldersPerSecond/sec, ${EstimatedTotal}min total)" -ForegroundColor Cyan
    }
}

# Final statistics
$EndTime = Get-Date
$TotalTime = $EndTime - $StartTime

Write-Host "`n=== ULTRA-HIGH-PERFORMANCE GENERATION COMPLETE ===" -ForegroundColor Green
Write-Host "Created: $FolderCount folders" -ForegroundColor White
Write-Host "Created: $TotalEstimatedFiles files" -ForegroundColor White
Write-Host "Total time: $($TotalTime.ToString('mm\:ss\.ff'))" -ForegroundColor White
Write-Host "Average: $([Math]::Round($FolderCount / $TotalTime.TotalSeconds, 2)) folders/second" -ForegroundColor White
Write-Host "File rate: $([Math]::Round($TotalEstimatedFiles / $TotalTime.TotalSeconds, 0)) files/second" -ForegroundColor White
Write-Host "Location: $RootPath" -ForegroundColor Yellow

# Quick verification (using .NET for speed)
Write-Host "`nQuick verification:" -ForegroundColor Yellow
$actualFolders = [System.IO.Directory]::GetDirectories($RootPath).Length
$sampleFolder = [System.IO.Directory]::GetDirectories($RootPath) | Select-Object -First 1
$sampleFiles = if ($sampleFolder) { [System.IO.Directory]::GetFiles($sampleFolder).Length } else { 0 }
Write-Host "  Actual folders created: $actualFolders" -ForegroundColor Gray
Write-Host "  Sample folder files: $sampleFiles" -ForegroundColor Gray