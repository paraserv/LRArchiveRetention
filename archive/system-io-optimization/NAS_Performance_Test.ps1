# NAS Performance Test - Compare Get-ChildItem vs System.IO
param(
    [string]$LogFile = "C:\temp\nas_performance_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Ensure temp directory exists
if (!(Test-Path C:\temp)) { New-Item -ItemType Directory -Path C:\temp -Force | Out-Null }

# Start transcript
Start-Transcript -Path $LogFile

Write-Host "NAS Performance Comparison Test" -ForegroundColor Cyan
Write-Host "=" * 60
Write-Host "Start time: $(Get-Date)"
Write-Host "PID: $PID"
Write-Host ""

# Test parameters
$retentionDays = 365
$cutoff = (Get-Date).AddDays(-$retentionDays)

Write-Host "Test Configuration:" -ForegroundColor Yellow
Write-Host "  Retention: $retentionDays days"
Write-Host "  Cutoff date: $($cutoff.ToString('yyyy-MM-dd'))"
Write-Host "  Log file: $LogFile"
Write-Host ""

# Load credential module
try {
    Import-Module C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1 -Force
    Write-Host "Credential module loaded successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to load credential module: $_"
    Stop-Transcript
    exit 1
}

# Get NAS credentials
try {
    $creds = Get-SavedShareCredential -Target NAS_CREDS
    if (!$creds) {
        throw "No credentials found for NAS_CREDS"
    }
    Write-Host "Retrieved credentials for: $($creds.SharePath)" -ForegroundColor Green
} catch {
    Write-Error "Failed to get NAS credentials: $_"
    Stop-Transcript
    exit 1
}

# Map drive for testing
Write-Host "`nMapping network drive for testing..." -ForegroundColor Yellow
try {
    $testDrive = New-PSDrive -Name PERFTEST -PSProvider FileSystem -Root $creds.SharePath -Credential $creds.Credential -Scope Script
    $mappedPath = "PERFTEST:"
    Write-Host "Drive mapped successfully: $mappedPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to map drive: $_"
    Stop-Transcript
    exit 1
}

Write-Host "`n" + ("=" * 60)

# Test 1: Get-ChildItem (current method)
Write-Host "`nTEST 1: Get-ChildItem Method (Current Implementation)" -ForegroundColor Cyan
Write-Host "-" * 60

$gcTimer = [System.Diagnostics.Stopwatch]::StartNew()
$gcMemoryBefore = [GC]::GetTotalMemory($false)

try {
    Write-Host "Scanning for .lca files..."
    $gcFiles = @(Get-ChildItem -Path $mappedPath -Filter *.lca -Recurse | Where-Object { -not $_.PSIsDirectory })
    $gcTotalCount = $gcFiles.Count
    
    Write-Host "Filtering files older than $retentionDays days..."
    $gcOldFiles = @($gcFiles | Where-Object { $_.LastWriteTime -lt $cutoff })
    $gcOldCount = $gcOldFiles.Count
    $gcTotalSize = ($gcOldFiles | Measure-Object -Property Length -Sum).Sum
    
} catch {
    Write-Error "Get-ChildItem error: $_"
    $gcTotalCount = 0
    $gcOldCount = 0
    $gcTotalSize = 0
}

$gcTimer.Stop()
$gcMemoryAfter = [GC]::GetTotalMemory($false)
$gcMemoryUsed = ($gcMemoryAfter - $gcMemoryBefore) / 1MB

Write-Host "`nGet-ChildItem Results:" -ForegroundColor Yellow
Write-Host "  Total files found: $gcTotalCount"
Write-Host "  Files to delete: $gcOldCount"
Write-Host "  Total size: $('{0:N2}' -f ($gcTotalSize / 1GB)) GB"
Write-Host "  Execution time: $($gcTimer.Elapsed.TotalSeconds) seconds"
Write-Host "  Memory used: $('{0:N2}' -f $gcMemoryUsed) MB"
if ($gcTotalCount -gt 0) {
    Write-Host "  Scan rate: $('{0:N0}' -f ($gcTotalCount / $gcTimer.Elapsed.TotalSeconds)) files/sec"
}

# Force garbage collection before next test
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[GC]::Collect()

Write-Host "`n" + ("=" * 60)

# Test 2: System.IO.Directory.EnumerateFiles
Write-Host "`nTEST 2: System.IO.Directory.EnumerateFiles (Optimized)" -ForegroundColor Cyan
Write-Host "-" * 60

$sioTimer = [System.Diagnostics.Stopwatch]::StartNew()
$sioMemoryBefore = [GC]::GetTotalMemory($false)

$sioTotalCount = 0
$sioOldCount = 0
$sioTotalSize = 0
$sioErrors = 0

try {
    Write-Host "Enumerating .lca files using System.IO..."
    
    # Use UNC path for System.IO
    $enumPath = $creds.SharePath
    $files = [System.IO.Directory]::EnumerateFiles($enumPath, "*.lca", [System.IO.SearchOption]::AllDirectories)
    
    foreach ($filePath in $files) {
        $sioTotalCount++
        
        # Progress update every 5000 files
        if ($sioTotalCount % 5000 -eq 0) {
            Write-Host "  Progress: $sioTotalCount files enumerated..." -NoNewline
            Write-Host "`r" -NoNewline
        }
        
        try {
            $fileInfo = [System.IO.FileInfo]::new($filePath)
            if ($fileInfo.LastWriteTime -lt $cutoff) {
                $sioOldCount++
                $sioTotalSize += $fileInfo.Length
            }
        } catch {
            $sioErrors++
        }
    }
    
    # Clear progress line
    Write-Host (" " * 60) -NoNewline
    Write-Host "`r" -NoNewline
    
} catch {
    Write-Error "System.IO error: $_"
}

$sioTimer.Stop()
$sioMemoryAfter = [GC]::GetTotalMemory($false)
$sioMemoryUsed = ($sioMemoryAfter - $sioMemoryBefore) / 1MB

Write-Host "`nSystem.IO Results:" -ForegroundColor Yellow
Write-Host "  Total files found: $sioTotalCount"
Write-Host "  Files to delete: $sioOldCount"
Write-Host "  Total size: $('{0:N2}' -f ($sioTotalSize / 1GB)) GB"
Write-Host "  Execution time: $($sioTimer.Elapsed.TotalSeconds) seconds"
Write-Host "  Memory used: $('{0:N2}' -f $sioMemoryUsed) MB"
Write-Host "  Errors: $sioErrors"
if ($sioTotalCount -gt 0) {
    Write-Host "  Scan rate: $('{0:N0}' -f ($sioTotalCount / $sioTimer.Elapsed.TotalSeconds)) files/sec"
}

Write-Host "`n" + ("=" * 60)

# Comparison Summary
Write-Host "`nPERFORMANCE COMPARISON SUMMARY" -ForegroundColor Green
Write-Host "=" * 60

if ($gcTotalCount -eq $sioTotalCount) {
    Write-Host "File count validation: PASSED ($gcTotalCount files)" -ForegroundColor Green
} else {
    Write-Host "File count validation: MISMATCH (GC: $gcTotalCount, SIO: $sioTotalCount)" -ForegroundColor Red
}

if ($gcTimer.Elapsed.TotalSeconds -gt 0 -and $sioTimer.Elapsed.TotalSeconds -gt 0) {
    $speedup = $gcTimer.Elapsed.TotalSeconds / $sioTimer.Elapsed.TotalSeconds
    Write-Host "`nSpeed comparison:"
    Write-Host "  Get-ChildItem: $($gcTimer.Elapsed.TotalSeconds) seconds"
    Write-Host "  System.IO: $($sioTimer.Elapsed.TotalSeconds) seconds"
    Write-Host "  Speedup: $('{0:N1}' -f $speedup)x $(if ($speedup -gt 1) { 'faster' } else { 'slower' })" -ForegroundColor $(if ($speedup -gt 1) { 'Green' } else { 'Yellow' })
}

Write-Host "`nMemory comparison:"
Write-Host "  Get-ChildItem: $('{0:N2}' -f $gcMemoryUsed) MB"
Write-Host "  System.IO: $('{0:N2}' -f $sioMemoryUsed) MB"
Write-Host "  Memory saved: $('{0:N2}' -f ($gcMemoryUsed - $sioMemoryUsed)) MB"

# Cleanup
Write-Host "`nCleaning up..." -ForegroundColor Gray
try {
    Remove-PSDrive PERFTEST -Force
    Write-Host "Test drive unmapped successfully" -ForegroundColor Green
} catch {
    Write-Warning "Could not unmap test drive: $_"
}

Write-Host "`nTest completed at: $(Get-Date)"
Stop-Transcript