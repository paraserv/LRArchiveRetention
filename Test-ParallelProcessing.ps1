# Test script to verify parallel processing performance with System.IO.File::Delete()

param(
    [string]$TestPath = "C:\LR\ParallelTest",
    [int]$FileCount = 1000,
    [int]$ThreadCount = 8,
    [switch]$UseNetworkPath
)

# If network path requested, create test folder on NAS
if ($UseNetworkPath) {
    $TestPath = "\\10.20.1.7\LRArchives\ParallelTest_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
    Write-Host "Using network path: $TestPath" -ForegroundColor Cyan
}

# Create test directory
if (!(Test-Path $TestPath)) {
    New-Item -ItemType Directory -Path $TestPath -Force | Out-Null
}

Write-Host "Creating $FileCount test files..." -ForegroundColor Yellow
$files = @()
for ($i = 1; $i -le $FileCount; $i++) {
    $fileName = Join-Path $TestPath "test_$i.txt"
    "Test content for file $i" | Set-Content $fileName
    $files += Get-Item $fileName
}

Write-Host "Created $FileCount files. Starting parallel deletion test..." -ForegroundColor Green

# Test 1: Sequential deletion with System.IO.File::Delete()
Write-Host "`nTest 1: Sequential deletion with System.IO.File::Delete()" -ForegroundColor Cyan
$sequentialStart = Get-Date
foreach ($file in $files) {
    try {
        [System.IO.File]::Delete($file.FullName)
    } catch {
        # File already deleted
    }
}
$sequentialTime = (Get-Date) - $sequentialStart
if ($sequentialTime.TotalSeconds -lt 0.001) { $sequentialTime = [TimeSpan]::FromMilliseconds(1) }
$sequentialRate = [math]::Round($FileCount / $sequentialTime.TotalSeconds, 2)
Write-Host "Sequential: $FileCount files in $([math]::Round($sequentialTime.TotalSeconds, 2)) seconds = $sequentialRate files/sec" -ForegroundColor Yellow

# Recreate files for parallel test
Write-Host "`nRecreating files for parallel test..." -ForegroundColor Gray
for ($i = 1; $i -le $FileCount; $i++) {
    $fileName = Join-Path $TestPath "test_$i.txt"
    "Test content for file $i" | Set-Content $fileName
}
$files = Get-ChildItem $TestPath -File

# Test 2: Parallel deletion with System.IO.File::Delete() (simulating the fixed code)
Write-Host "`nTest 2: Parallel deletion with System.IO.File::Delete() ($ThreadCount threads)" -ForegroundColor Cyan

# This is the exact parallel processing logic from ArchiveRetention.ps1
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
$runspacePool.Open()

$scriptBlock = {
    param($FileInfo)
    
    $result = @{
        FilePath = $FileInfo.FullName
        Success = $false
        Error = $null
    }
    
    try {
        [System.IO.File]::Delete($FileInfo.FullName)
        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

$jobs = @()
$parallelStart = Get-Date

foreach ($file in $files) {
    $powerShell = [powershell]::Create()
    $powerShell.RunspacePool = $runspacePool
    $powerShell.AddScript($scriptBlock).AddArgument($file) | Out-Null
    
    $job = @{
        PowerShell = $powerShell
        Handle = $powerShell.BeginInvoke()
    }
    $jobs += $job
}

# Wait for all jobs to complete
$completedJobs = 0
while ($completedJobs -lt $jobs.Count) {
    Start-Sleep -Milliseconds 10
    $completedJobs = @($jobs | Where-Object { $_.Handle.IsCompleted }).Count
}

# Collect results
$successCount = 0
foreach ($job in $jobs) {
    $result = $job.PowerShell.EndInvoke($job.Handle)
    if ($result.Success) { $successCount++ }
    $job.PowerShell.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()

$parallelTime = (Get-Date) - $parallelStart
if ($parallelTime.TotalSeconds -lt 0.001) { $parallelTime = [TimeSpan]::FromMilliseconds(1) }
$parallelRate = [math]::Round($FileCount / $parallelTime.TotalSeconds, 2)
Write-Host "Parallel: $FileCount files in $([math]::Round($parallelTime.TotalSeconds, 2)) seconds = $parallelRate files/sec" -ForegroundColor Yellow

# Show improvement
$improvement = [math]::Round($parallelRate / $sequentialRate, 2)
Write-Host "`nPerformance improvement: ${improvement}x faster with $ThreadCount threads" -ForegroundColor Green

# Cleanup
Remove-Item $TestPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nTest complete. Test directory cleaned up." -ForegroundColor Gray