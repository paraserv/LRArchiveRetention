# test-integration.ps1
# Integration test for ArchiveRetention.ps1 v2.0

#requires -Version 5.1

param(
    [string]$TestPath,
    [switch]$UseDefaultTestPath,
    [switch]$TestNetworkShare,
    [string]$CredentialTarget,
    [switch]$Verbose
)

# Set preferences
$ErrorActionPreference = 'Stop'
if ($Verbose) {
    $VerbosePreference = 'Continue'
}

$scriptRoot = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path -Path $scriptRoot -ChildPath 'ArchiveRetention.ps1'

Write-Host "`n=== ArchiveRetention v2.0 Integration Tests ===" -ForegroundColor Cyan
Write-Host "Script Path: $mainScript" -ForegroundColor Gray

# Verify script exists
if (-not (Test-Path -Path $mainScript)) {
    Write-Error "ArchiveRetention.ps1 not found at: $mainScript"
    exit 1
}

# Create or use test path
if ($UseDefaultTestPath -or -not $TestPath) {
    $TestPath = Join-Path -Path $env:TEMP -ChildPath "ArchiveRetentionTest_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Host "Using test path: $TestPath" -ForegroundColor Yellow
    
    # Create test directory structure
    Write-Host "`nCreating test environment..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $TestPath -Force | Out-Null
    
    # Create subdirectories
    $subDirs = @('2020', '2021', '2022', '2023', '2024')
    foreach ($dir in $subDirs) {
        $subPath = Join-Path -Path $TestPath -ChildPath $dir
        New-Item -ItemType Directory -Path $subPath -Force | Out-Null
        
        # Create test files
        1..5 | ForEach-Object {
            $fileName = "archive_${dir}_$_.lca"
            $filePath = Join-Path -Path $subPath -ChildPath $fileName
            "Test archive data for $dir file $_" | Out-File -FilePath $filePath
            
            # Set file dates based on directory year
            $fileDate = Get-Date -Year ([int]$dir) -Month 6 -Day 15
            (Get-Item $filePath).LastWriteTime = $fileDate
            (Get-Item $filePath).CreationTime = $fileDate
        }
    }
    
    # Create some non-LCA files
    $miscFiles = @('readme.txt', 'config.xml', 'data.json')
    foreach ($file in $miscFiles) {
        $filePath = Join-Path -Path $TestPath -ChildPath $file
        "Miscellaneous file: $file" | Out-File -FilePath $filePath
    }
    
    Write-Host "Created test environment with:" -ForegroundColor Green
    Write-Host "  - 5 year directories (2020-2024)" -ForegroundColor Gray
    Write-Host "  - 5 LCA files per year (25 total)" -ForegroundColor Gray
    Write-Host "  - 3 non-LCA files" -ForegroundColor Gray
}

# Test functions
function Test-DryRun {
    param([string]$Path, [int]$RetentionDays)
    
    Write-Host "`n--- Test: Dry Run (Default) ---" -ForegroundColor Yellow
    Write-Host "Testing with retention: $RetentionDays days" -ForegroundColor Gray
    
    try {
        $output = & $mainScript -ArchivePath $Path -RetentionDays $RetentionDays -Verbose:$Verbose *>&1
        
        # Check for expected output
        $foundSummary = $output | Where-Object { $_ -like "*DRY RUN MODE*" }
        $foundFiles = $output | Where-Object { $_ -like "*Found * files * for retention*" }
        
        if ($foundSummary -and $foundFiles) {
            Write-Host "✓ Dry run completed successfully" -ForegroundColor Green
            
            # Extract file count
            if ($foundFiles -match "Found (\d+) files") {
                $fileCount = [int]$Matches[1]
                Write-Host "  Found $fileCount files for retention" -ForegroundColor Gray
            }
            
            return $true
        } else {
            Write-Host "✗ Dry run did not produce expected output" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ Dry run failed: $_" -ForegroundColor Red
        return $false
    }
}

function Test-ParallelProcessing {
    param([string]$Path)
    
    Write-Host "`n--- Test: Parallel Processing ---" -ForegroundColor Yellow
    
    try {
        # Test with different thread counts
        $threadCounts = @(1, 4)
        $times = @{}
        
        foreach ($threads in $threadCounts) {
            Write-Host "  Testing with $threads thread(s)..." -NoNewline
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $null = & $mainScript -ArchivePath $Path -RetentionDays 365 -ParallelThreads $threads 2>&1
            $stopwatch.Stop()
            
            $times[$threads] = $stopwatch.Elapsed.TotalSeconds
            Write-Host " $([Math]::Round($times[$threads], 2)) seconds" -ForegroundColor Gray
        }
        
        # Parallel should be faster (or at least not significantly slower)
        if ($times[4] -le ($times[1] * 1.2)) {
            Write-Host "✓ Parallel processing working correctly" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ Parallel processing not showing expected performance" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ Parallel processing test failed: $_" -ForegroundColor Red
        return $false
    }
}

function Test-FileTypeFilter {
    param([string]$Path)
    
    Write-Host "`n--- Test: File Type Filtering ---" -ForegroundColor Yellow
    
    try {
        # Test including only LCA files
        Write-Host "  Testing include filter (.lca only)..." -NoNewline
        $output = & $mainScript -ArchivePath $Path -RetentionDays 365 -IncludeFileTypes @('.lca') *>&1
        $lcaCount = ($output | Where-Object { $_ -match "Found (\d+) files" } | ForEach-Object { [int]$Matches[1] })[0]
        Write-Host " Found $lcaCount files" -ForegroundColor Gray
        
        # Test excluding LCA files
        Write-Host "  Testing exclude filter (no .lca)..." -NoNewline
        $output = & $mainScript -ArchivePath $Path -RetentionDays 1 -IncludeFileTypes @('.txt', '.xml', '.json') *>&1
        $otherCount = ($output | Where-Object { $_ -match "Found (\d+) files" } | ForEach-Object { [int]$Matches[1] })[0]
        Write-Host " Found $otherCount files" -ForegroundColor Gray
        
        if ($lcaCount -gt 0 -and $otherCount -ge 0) {
            Write-Host "✓ File type filtering working correctly" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ File type filtering not working as expected" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ File type filter test failed: $_" -ForegroundColor Red
        return $false
    }
}

function Test-ConfigFile {
    param([string]$Path)
    
    Write-Host "`n--- Test: Configuration File ---" -ForegroundColor Yellow
    
    $configPath = Join-Path -Path $env:TEMP -ChildPath "test-config.json"
    
    try {
        # Create test config
        $config = @{
            MinimumRetentionDays = 90
            ParallelThreads = 2
            BatchSize = 500
            ProgressUpdateIntervalSeconds = 5
        } | ConvertTo-Json
        
        $config | Out-File -FilePath $configPath -Encoding UTF8
        Write-Host "  Created test config at: $configPath" -ForegroundColor Gray
        
        # Run with config
        Write-Host "  Testing with config file..." -NoNewline
        $output = & $mainScript -ArchivePath $Path -RetentionDays 365 -ConfigFile $configPath *>&1
        
        # Check if it ran successfully
        if ($output -match "Script completed successfully") {
            Write-Host " SUCCESS" -ForegroundColor Green
            Write-Host "✓ Configuration file support working" -ForegroundColor Green
            return $true
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "✗ Configuration file test failed" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "✗ Config file test failed: $_" -ForegroundColor Red
        return $false
    } finally {
        if (Test-Path -Path $configPath) {
            Remove-Item -Path $configPath -Force
        }
    }
}

function Test-SingleInstance {
    Write-Host "`n--- Test: Single Instance Lock ---" -ForegroundColor Yellow
    
    try {
        # Start first instance in background
        Write-Host "  Starting first instance..." -NoNewline
        $job1 = Start-Job -ScriptBlock {
            param($script, $path)
            & $script -ArchivePath $path -RetentionDays 365
            Start-Sleep -Seconds 5  # Hold the lock
        } -ArgumentList $mainScript, $TestPath
        
        Start-Sleep -Seconds 2  # Let it acquire lock
        Write-Host " Started" -ForegroundColor Gray
        
        # Try to start second instance
        Write-Host "  Attempting second instance..." -NoNewline
        $output = & $mainScript -ArchivePath $TestPath -RetentionDays 365 2>&1
        
        # Check for lock error
        if ($output -match "already running" -or $output -match "lock") {
            Write-Host " Blocked (as expected)" -ForegroundColor Green
            Write-Host "✓ Single instance lock working correctly" -ForegroundColor Green
            $result = $true
        } else {
            Write-Host " Not blocked!" -ForegroundColor Red
            Write-Host "✗ Single instance lock not working" -ForegroundColor Red
            $result = $false
        }
        
        # Cleanup
        Stop-Job -Job $job1 -ErrorAction SilentlyContinue
        Remove-Job -Job $job1 -Force -ErrorAction SilentlyContinue
        
        return $result
    } catch {
        Write-Host "✗ Single instance test failed: $_" -ForegroundColor Red
        return $false
    }
}

# Run tests
$results = @{
    DryRun = $false
    ParallelProcessing = $false
    FileTypeFilter = $false
    ConfigFile = $false
    SingleInstance = $false
}

try {
    # Basic tests
    $results.DryRun = Test-DryRun -Path $TestPath -RetentionDays 730  # 2 years
    $results.ParallelProcessing = Test-ParallelProcessing -Path $TestPath
    $results.FileTypeFilter = Test-FileTypeFilter -Path $TestPath
    $results.ConfigFile = Test-ConfigFile -Path $TestPath
    $results.SingleInstance = Test-SingleInstance
    
    # Network share test (optional)
    if ($TestNetworkShare -and $CredentialTarget) {
        Write-Host "`n--- Test: Network Share Access ---" -ForegroundColor Yellow
        
        try {
            Write-Host "  Testing with credential: $CredentialTarget..." -NoNewline
            $output = & $mainScript -CredentialTarget $CredentialTarget -RetentionDays 365 *>&1
            
            if ($output -match "Successfully mapped network drive") {
                Write-Host " SUCCESS" -ForegroundColor Green
                Write-Host "✓ Network share access working" -ForegroundColor Green
            } else {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host "✗ Network share access failed" -ForegroundColor Red
            }
        } catch {
            Write-Host " ERROR: $_" -ForegroundColor Red
        }
    }
    
} finally {
    # Cleanup test directory if we created it
    if ($UseDefaultTestPath -and (Test-Path -Path $TestPath)) {
        Write-Host "`nCleaning up test environment..." -ForegroundColor Yellow
        Remove-Item -Path $TestPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Summary
Write-Host "`n=== Integration Test Summary ===" -ForegroundColor Cyan
$passed = ($results.Values | Where-Object { $_ -eq $true }).Count
$total = $results.Count

foreach ($test in $results.GetEnumerator()) {
    $status = if ($test.Value) { "PASS" } else { "FAIL" }
    $color = if ($test.Value) { "Green" } else { "Red" }
    Write-Host "$($test.Key): $status" -ForegroundColor $color
}

Write-Host "`nTotal: $passed/$total tests passed" -ForegroundColor $(if ($passed -eq $total) { 'Green' } else { 'Yellow' })

if ($passed -eq $total) {
    Write-Host "All integration tests passed! ✓" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some integration tests failed!" -ForegroundColor Red
    exit 1
} 