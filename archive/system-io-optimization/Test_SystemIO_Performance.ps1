#Requires -Version 5.1

<#
.SYNOPSIS
    Performance comparison test between Get-ChildItem and System.IO enumeration
    
.DESCRIPTION
    Tests both enumeration methods on the same directory to compare performance.
    Provides detailed metrics including files/second, memory usage, and timing.
    
.PARAMETER TestPath
    Path to test (defaults to NAS path)
    
.PARAMETER MaxFiles
    Maximum number of files to process (for quick tests)
    
.PARAMETER TestBoth
    Test both methods for comparison (default: true)
#>

param(
    [string]$TestPath = "\\10.20.1.7\LRArchives",
    [int]$MaxFiles = 50000,
    [switch]$TestBoth = $true
)

# Import credential helper for NAS access
$modulePath = "C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1"
Import-Module $modulePath -Force

Write-Host "`n=== System.IO vs Get-ChildItem Performance Test ===" -ForegroundColor Cyan
Write-Host "Test Path: $TestPath" -ForegroundColor Yellow
Write-Host "Max Files: $MaxFiles" -ForegroundColor Yellow
Write-Host ""

# Function to test Get-ChildItem performance
function Test-GetChildItem {
    param([string]$Path, [int]$MaxFiles)
    
    Write-Host "`n--- Testing Get-ChildItem ---" -ForegroundColor Green
    $startMem = [System.GC]::GetTotalMemory($true) / 1MB
    $startTime = Get-Date
    $fileCount = 0
    
    try {
        Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction Stop | 
            ForEach-Object {
                $fileCount++
                if ($fileCount -ge $MaxFiles) { break }
                if ($fileCount % 10000 -eq 0) {
                    Write-Host "  Processed $fileCount files..." -ForegroundColor Gray
                }
            }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    
    $endTime = Get-Date
    $endMem = [System.GC]::GetTotalMemory($false) / 1MB
    $duration = ($endTime - $startTime).TotalSeconds
    
    return @{
        Method = "Get-ChildItem"
        FileCount = $fileCount
        Duration = [math]::Round($duration, 2)
        FilesPerSecond = [math]::Round($fileCount / $duration, 0)
        MemoryUsedMB = [math]::Round($endMem - $startMem, 2)
    }
}

# Function to test System.IO performance
function Test-SystemIO {
    param([string]$Path, [int]$MaxFiles)
    
    Write-Host "`n--- Testing System.IO.Directory.EnumerateFiles ---" -ForegroundColor Green
    $startMem = [System.GC]::GetTotalMemory($true) / 1MB
    $startTime = Get-Date
    $fileCount = 0
    
    try {
        $enumerator = [System.IO.Directory]::EnumerateFiles($Path, "*.*", [System.IO.SearchOption]::AllDirectories)
        
        foreach ($filePath in $enumerator) {
            $fileCount++
            if ($fileCount -ge $MaxFiles) { break }
            if ($fileCount % 10000 -eq 0) {
                Write-Host "  Processed $fileCount files..." -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    
    $endTime = Get-Date
    $endMem = [System.GC]::GetTotalMemory($false) / 1MB
    $duration = ($endTime - $startTime).TotalSeconds
    
    return @{
        Method = "System.IO"
        FileCount = $fileCount
        Duration = [math]::Round($duration, 2)
        FilesPerSecond = [math]::Round($fileCount / $duration, 0)
        MemoryUsedMB = [math]::Round($endMem - $startMem, 2)
    }
}

# Handle network path authentication
if ($TestPath.StartsWith("\\")) {
    Write-Host "Network path detected. Attempting to use NAS_CREDS..." -ForegroundColor Yellow
    
    try {
        $credential = Get-SavedShareCredential -Target "NAS_CREDS"
        if ($credential) {
            Write-Host "Found saved credentials for NAS_CREDS" -ForegroundColor Green
            
            # Map temporary drive for better System.IO compatibility
            $tempDrive = Get-AvailableDriveLetter
            Write-Host "Mapping temporary drive $tempDrive to $TestPath..." -ForegroundColor Yellow
            
            $null = New-PSDrive -Name $tempDrive -PSProvider FileSystem -Root $TestPath -Credential $credential -Persist
            $TestPath = "${tempDrive}:\"
            Write-Host "Using mapped drive: $TestPath" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Warning: Could not establish network authentication: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Run tests
$results = @()

if ($TestBoth) {
    # Test Get-ChildItem
    $gcResult = Test-GetChildItem -Path $TestPath -MaxFiles $MaxFiles
    if ($gcResult) { $results += $gcResult }
    
    # Force garbage collection between tests
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Start-Sleep -Seconds 2
    
    # Test System.IO
    $sioResult = Test-SystemIO -Path $TestPath -MaxFiles $MaxFiles
    if ($sioResult) { $results += $sioResult }
} else {
    # Test only System.IO
    $sioResult = Test-SystemIO -Path $TestPath -MaxFiles $MaxFiles
    if ($sioResult) { $results += $sioResult }
}

# Display results
if ($results.Count -gt 0) {
    Write-Host "`n=== Performance Results ===" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    
    if ($results.Count -eq 2) {
        # Calculate improvement
        $gcResult = $results | Where-Object { $_.Method -eq "Get-ChildItem" }
        $sioResult = $results | Where-Object { $_.Method -eq "System.IO" }
        
        if ($gcResult -and $sioResult) {
            $speedImprovement = [math]::Round($sioResult.FilesPerSecond / $gcResult.FilesPerSecond, 1)
            $memoryReduction = [math]::Round((1 - ($sioResult.MemoryUsedMB / $gcResult.MemoryUsedMB)) * 100, 0)
            
            Write-Host "`n=== Performance Improvement ===" -ForegroundColor Green
            Write-Host "Speed Improvement: ${speedImprovement}x faster" -ForegroundColor Yellow
            Write-Host "Memory Reduction: ${memoryReduction}%" -ForegroundColor Yellow
            Write-Host "System.IO processed $($sioResult.FilesPerSecond) files/second vs $($gcResult.FilesPerSecond) files/second" -ForegroundColor White
        }
    }
}

# Cleanup
if ($tempDrive) {
    Write-Host "`nCleaning up temporary drive mapping..." -ForegroundColor Gray
    Remove-PSDrive -Name $tempDrive -Force -ErrorAction SilentlyContinue
}

Write-Host "`nTest completed!" -ForegroundColor Green

# Helper function to get available drive letter
function Get-AvailableDriveLetter {
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $letters = 65..90 | ForEach-Object { [char]$_ }
    $available = $letters | Where-Object { $_ -notin $usedLetters }
    return $available[0]
}