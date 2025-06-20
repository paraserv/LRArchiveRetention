# test-v2-modules.ps1
# Test script for v2.0 modular refactor

#requires -Version 5.1

param(
    [switch]$SkipFileOperations,
    [switch]$Verbose
)

# Set preferences
$ErrorActionPreference = 'Stop'
if ($Verbose) {
    $VerbosePreference = 'Continue'
}

# Script location
$scriptRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path -Path $scriptRoot -ChildPath 'modules'

Write-Host "`n=== ArchiveRetention v2.0 Module Tests ===" -ForegroundColor Cyan
Write-Host "Script Root: $scriptRoot" -ForegroundColor Gray
Write-Host "Module Path: $modulePath" -ForegroundColor Gray

# Test results tracking
$testResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
}

function Test-Module {
    param(
        [string]$ModuleName,
        [scriptblock]$TestBlock
    )
    
    Write-Host "`n--- Testing $ModuleName ---" -ForegroundColor Yellow
    
    try {
        # Import module
        $moduleFile = Join-Path -Path $modulePath -ChildPath "$ModuleName.psm1"
        if (-not (Test-Path -Path $moduleFile)) {
            throw "Module file not found: $moduleFile"
        }
        
        Import-Module -Name $moduleFile -Force -DisableNameChecking
        Write-Host "✓ Module imported successfully" -ForegroundColor Green
        
        # Run tests
        & $TestBlock
        
        # Clean up
        Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Host "✗ Module test failed: $_" -ForegroundColor Red
        $script:testResults.Failed++
    }
}

# Test 1: Configuration Module
Test-Module -ModuleName 'Configuration' -TestBlock {
    Write-Host "  Testing Get-DefaultConfiguration..." -NoNewline
    $config = Get-DefaultConfiguration
    if ($config.MinimumRetentionDays -eq 90) {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host "  Testing New-RuntimeConfiguration..." -NoNewline
    $params = @{
        RetentionDays = 180
        ArchivePath = 'C:\Test'
        Execute = $true
    }
    $runtime = New-RuntimeConfiguration -Parameters $params
    if ($runtime.RetentionDays -eq 180 -and $runtime.ArchivePath -eq 'C:\Test') {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host "  Testing file type filters..." -NoNewline
    $filter = Get-FileTypeFilter -IncludeTypes @('lca', '.txt') -ExcludeTypes @('log')
    if ($filter.Include -contains '.lca' -and $filter.Include -contains '.txt') {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
}

# Test 2: Logging Module
Test-Module -ModuleName 'LoggingModule' -TestBlock {
    $testLogDir = Join-Path -Path $env:TEMP -ChildPath "ArchiveRetentionTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    try {
        Write-Host "  Testing logging initialization..." -NoNewline
        Initialize-LoggingModule -LogDirectory $testLogDir
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
        
        Write-Host "  Testing log stream creation..." -NoNewline
        $result = New-LogStream -Name 'Test' -FileName 'test.log' -Header "Test Header"
        if ($result) {
            Write-Host " PASS" -ForegroundColor Green
            $script:testResults.Passed++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:testResults.Failed++
        }
        
        Write-Host "  Testing log writing..." -NoNewline
        Write-Log "Test message" -Level INFO -StreamNames @('Test') -NoConsoleOutput
        Write-Log "Debug message" -Level DEBUG -StreamNames @('Test') -NoConsoleOutput
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
        
        Write-Host "  Testing log summary..." -NoNewline
        $summary = Get-LogSummary
        if ($summary.Streams.ContainsKey('Test')) {
            Write-Host " PASS" -ForegroundColor Green
            $script:testResults.Passed++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:testResults.Failed++
        }
        
        # Cleanup
        Close-AllLogStreams
        
    } finally {
        if (Test-Path -Path $testLogDir) {
            Remove-Item -Path $testLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Test 3: Progress Tracking Module
Test-Module -ModuleName 'ProgressTracking' -TestBlock {
    Write-Host "  Testing progress initialization..." -NoNewline
    Initialize-ProgressTracking -UpdateInterval ([TimeSpan]::FromMilliseconds(100))
    Write-Host " PASS" -ForegroundColor Green
    $script:testResults.Passed++
    
    Write-Host "  Testing activity creation..." -NoNewline
    New-ProgressActivity -Name 'TestActivity' -Activity 'Testing Progress' -TotalItems 100
    Write-Host " PASS" -ForegroundColor Green
    $script:testResults.Passed++
    
    Write-Host "  Testing progress updates..." -NoNewline
    Update-ProgressActivity -Name 'TestActivity' -ProcessedItems 50 -SuccessCount 45 -ErrorCount 5
    $summary = Get-ProgressSummary -Name 'TestActivity'
    if ($summary.ProcessedItems -eq 50) {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host "  Testing format functions..." -NoNewline
    $size = Format-ByteSize -Bytes 1073741824  # 1GB
    $time = Format-TimeSpan -TimeSpan ([TimeSpan]::FromMinutes(65))
    if ($size -eq "1.00 GB" -and $time -like "*1h 05m*") {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL (Size: $size, Time: $time)" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Complete-ProgressActivity -Name 'TestActivity'
}

# Test 4: Lock Manager Module
Test-Module -ModuleName 'LockManager' -TestBlock {
    Write-Host "  Testing lock creation..." -NoNewline
    $lockResult = New-ScriptLock -ScriptName 'TestScript'
    if ($lockResult.Success) {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host "  Testing duplicate lock prevention..." -NoNewline
    $dupResult = New-ScriptLock -ScriptName 'TestScript'
    if (-not $dupResult.Success -and $dupResult.Message -like "*already running*") {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
    
    Write-Host "  Testing lock removal..." -NoNewline
    $removed = Remove-ScriptLock
    if ($removed) {
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults.Passed++
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $script:testResults.Failed++
    }
}

# Test 5: File Operations Module (optional - requires test data)
if (-not $SkipFileOperations) {
    Test-Module -ModuleName 'FileOperations' -TestBlock {
        # Create test directory
        $testPath = Join-Path -Path $env:TEMP -ChildPath "FileOpsTest_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -ItemType Directory -Path $testPath -Force | Out-Null
        
        try {
            # Create test files
            Write-Host "  Creating test files..." -NoNewline
            1..20 | ForEach-Object {
                $fileName = "test$_.lca"
                $filePath = Join-Path -Path $testPath -ChildPath $fileName
                "Test content $_" | Out-File -FilePath $filePath
                # Make some files old
                if ($_ -le 10) {
                    (Get-Item $filePath).LastWriteTime = (Get-Date).AddDays(-400)
                }
            }
            Write-Host " DONE" -ForegroundColor Green
            
            Write-Host "  Testing file discovery..." -NoNewline
            $cutoff = (Get-Date).AddDays(-365)
            $filter = Get-FileTypeFilter -IncludeTypes @('.lca')
            $files = Get-FilesForRetention -Path $testPath -CutoffDate $cutoff -FileTypeFilter $filter -ParallelThreads 2
            
            if ($files.Count -eq 10) {
                Write-Host " PASS (Found $($files.Count) old files)" -ForegroundColor Green
                $script:testResults.Passed++
            } else {
                Write-Host " FAIL (Expected 10, found $($files.Count))" -ForegroundColor Red
                $script:testResults.Failed++
            }
            
            Write-Host "  Testing directory statistics..." -NoNewline
            $stats = Get-DirectoryStatistics -Path $testPath -CutoffDate $cutoff
            if ($stats.TotalFiles -eq 20 -and $stats.OldFiles -eq 10) {
                Write-Host " PASS" -ForegroundColor Green
                $script:testResults.Passed++
            } else {
                Write-Host " FAIL" -ForegroundColor Red
                $script:testResults.Failed++
            }
            
        } finally {
            # Cleanup
            if (Test-Path -Path $testPath) {
                Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    Write-Host "`n--- Skipping File Operations Tests ---" -ForegroundColor Yellow
    $script:testResults.Skipped += 2
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed:  $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Skipped: $($testResults.Skipped)" -ForegroundColor Gray
Write-Host "Total:   $($testResults.Passed + $testResults.Failed + $testResults.Skipped)" -ForegroundColor White

if ($testResults.Failed -eq 0) {
    Write-Host "`nAll tests passed! ✓" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed! ✗" -ForegroundColor Red
    exit 1
} 