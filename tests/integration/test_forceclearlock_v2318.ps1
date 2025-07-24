# Comprehensive test script for ForceClearLock functionality in v2.3.18
# Tests all scenarios: normal lock, stale lock, forced clear, race conditions

param(
    [switch]$SkipCleanup
)

$ErrorActionPreference = "Continue"
Write-Host "`n=== ForceClearLock Comprehensive Test Suite v2.3.18 ===" -ForegroundColor Cyan
Write-Host "This test will verify all lock file handling scenarios" -ForegroundColor Yellow

# Change to script directory
cd C:\LR\Scripts\LRArchiveRetention

# Function to create a fake lock file
function Create-FakeLock {
    param(
        [int]$PID = 99999,
        [switch]$CurrentPID
    )
    
    $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
    if ($CurrentPID) {
        $PID = $pid
    }
    
    "$PID`n$(Get-Date)" | Set-Content -Path $lockPath -Force
    Write-Host "Created fake lock file with PID: $PID" -ForegroundColor Gray
    return $lockPath
}

# Function to check if lock file exists
function Test-LockExists {
    $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
    return Test-Path $lockPath
}

# Function to run test and capture output
function Run-Test {
    param(
        [string]$TestName,
        [string]$Arguments,
        [scriptblock]$Setup = {},
        [scriptblock]$Validate
    )
    
    Write-Host "`n--- Test: $TestName ---" -ForegroundColor Yellow
    
    # Setup
    & $Setup
    
    # Run command
    $output = & {
        $ErrorActionPreference = "Continue"
        Invoke-Expression ".\ArchiveRetention.ps1 $Arguments 2>&1"
    }
    
    # Show relevant output
    $output | Where-Object { 
        $_ -match "(lock|Lock|FATAL|ERROR|WARNING|SUCCESS|ForceClearLock)" 
    } | ForEach-Object {
        if ($_ -match "FATAL|ERROR") {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match "WARNING") {
            Write-Host $_ -ForegroundColor Yellow
        } elseif ($_ -match "SUCCESS") {
            Write-Host $_ -ForegroundColor Green
        } else {
            Write-Host $_ -ForegroundColor Gray
        }
    }
    
    # Validate
    $result = & $Validate
    if ($result.Success) {
        Write-Host "[PASS] $($result.Message)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $($result.Message)" -ForegroundColor Red
    }
    
    return $result.Success
}

# Clean up any existing lock files
Write-Host "`nCleaning up any existing lock files..." -ForegroundColor Gray
Remove-Item -Path (Join-Path $env:TEMP "ArchiveRetention.lock") -Force -ErrorAction SilentlyContinue

# Test 1: Normal execution without existing lock
$test1 = Run-Test -TestName "Normal execution (no existing lock)" `
    -Arguments "-ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf" `
    -Setup {
        # Ensure no lock exists
        Remove-Item -Path (Join-Path $env:TEMP "ArchiveRetention.lock") -Force -ErrorAction SilentlyContinue
    } `
    -Validate {
        # Should complete successfully
        $logContent = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
        $completed = $logContent -match "SCRIPT.*DRY-RUN"
        @{
            Success = $completed.Count -gt 0
            Message = if ($completed) { "Script completed successfully" } else { "Script did not complete" }
        }
    }

Start-Sleep -Seconds 2

# Test 2: Stale lock file (non-existent PID)
$test2 = Run-Test -TestName "Stale lock file (non-existent PID)" `
    -Arguments "-ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf" `
    -Setup {
        Create-FakeLock -PID 99999
    } `
    -Validate {
        # Should detect and remove stale lock
        $logContent = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
        $staleDetected = $logContent -match "stale lock|Stale lock"
        $completed = $logContent -match "SCRIPT.*DRY-RUN"
        @{
            Success = ($staleDetected.Count -gt 0) -and ($completed.Count -gt 0)
            Message = if ($staleDetected -and $completed) { 
                "Stale lock detected and removed, script completed" 
            } else { 
                "Failed to handle stale lock properly" 
            }
        }
    }

Start-Sleep -Seconds 2

# Test 3: Active lock file (current process)
$test3 = Run-Test -TestName "Active lock file (simulated active instance)" `
    -Arguments "-ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf" `
    -Setup {
        # Create a lock file and hold it open
        $lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
        $global:lockStream = [System.IO.File]::Open($lockPath, 'Create', 'ReadWrite', 'None')
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$pid`n$(Get-Date)")
        $global:lockStream.Write($bytes, 0, $bytes.Length)
        $global:lockStream.Flush()
    } `
    -Validate {
        # Should fail with "already running" message
        $logContent = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
        $alreadyRunning = $logContent -match "already running|in use"
        
        # Clean up lock stream
        if ($global:lockStream) {
            $global:lockStream.Close()
            $global:lockStream.Dispose()
        }
        
        @{
            Success = $alreadyRunning.Count -gt 0
            Message = if ($alreadyRunning) { 
                "Correctly detected active instance" 
            } else { 
                "Failed to detect active instance" 
            }
        }
    }

Start-Sleep -Seconds 2

# Test 4: ForceClearLock with no other instances
$test4 = Run-Test -TestName "ForceClearLock with orphaned lock" `
    -Arguments "-ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock" `
    -Setup {
        Create-FakeLock -PID 99999
    } `
    -Validate {
        # Should remove orphaned lock and complete
        $logContent = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
        $orphanedRemoved = $logContent -match "Orphaned lock file removed"
        $completed = $logContent -match "SCRIPT.*DRY-RUN"
        $noRaceCondition = -not ($logContent -match "lock file in use.*after.*ForceClearLock")
        
        @{
            Success = $orphanedRemoved -and $completed -and $noRaceCondition
            Message = if ($orphanedRemoved -and $completed -and $noRaceCondition) { 
                "ForceClearLock worked correctly - no race condition!" 
            } else { 
                "ForceClearLock failed or race condition detected" 
            }
        }
    }

Start-Sleep -Seconds 2

# Test 5: ForceClearLock with simulated running instance
$test5 = Run-Test -TestName "ForceClearLock with active PowerShell process" `
    -Arguments "-ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock" `
    -Setup {
        # Start a dummy PowerShell process that looks like it's running ArchiveRetention
        $global:dummyProcess = Start-Process powershell -ArgumentList "-Command", "Write-Host 'Dummy ArchiveRetention.ps1 process'; Start-Sleep -Seconds 30" -PassThru
        Start-Sleep -Seconds 1
        Create-FakeLock -PID $global:dummyProcess.Id
    } `
    -Validate {
        # Should detect running process and refuse to force clear
        $logContent = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
        $cannotForce = $logContent -match "Cannot force clear lock"
        
        # Clean up dummy process
        if ($global:dummyProcess -and -not $global:dummyProcess.HasExited) {
            Stop-Process -Id $global:dummyProcess.Id -Force -ErrorAction SilentlyContinue
        }
        
        @{
            Success = $cannotForce.Count -gt 0
            Message = if ($cannotForce) { 
                "Correctly refused to force clear with active process" 
            } else { 
                "Failed to detect active process" 
            }
        }
    }

Start-Sleep -Seconds 2

# Test 6: Rapid succession test (race condition check)
Write-Host "`n--- Test: Rapid succession ForceClearLock ---" -ForegroundColor Yellow
$rapidResults = @()

for ($i = 1; $i -le 5; $i++) {
    Write-Host "  Attempt $i..." -ForegroundColor Gray
    
    # Create lock file
    Create-FakeLock -PID 88888 | Out-Null
    
    # Run with ForceClearLock
    $output = & {
        .\ArchiveRetention.ps1 -ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock 2>&1
    }
    
    # Check for race condition error
    $hasRaceError = $output -match "lock file in use.*being used by another process"
    $completed = $output -match "What if:"
    
    $rapidResults += @{
        Attempt = $i
        RaceError = $hasRaceError.Count -gt 0
        Completed = $completed.Count -gt 0
    }
    
    Start-Sleep -Milliseconds 500
}

# Validate rapid succession results
$raceErrors = $rapidResults | Where-Object { $_.RaceError }
if ($raceErrors.Count -eq 0) {
    Write-Host "[PASS] No race conditions in 5 rapid attempts!" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Race conditions detected in $($raceErrors.Count) attempts" -ForegroundColor Red
}

# Test 7: Concurrent ForceClearLock attempts
Write-Host "`n--- Test: Concurrent ForceClearLock attempts ---" -ForegroundColor Yellow

# Create lock file
Create-FakeLock -PID 77777

# Start multiple concurrent attempts
$jobs = @()
for ($i = 1; $i -le 3; $i++) {
    $jobs += Start-Job -ScriptBlock {
        cd C:\LR\Scripts\LRArchiveRetention
        .\ArchiveRetention.ps1 -ArchivePath 'C:\Temp' -RetentionDays 1 -WhatIf -ForceClearLock 2>&1
    }
}

# Wait for jobs to complete
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

# Check results
$successCount = @($results | Where-Object { $_ -match "What if:" }).Count
$errorCount = @($results | Where-Object { $_ -match "lock file in use" }).Count

Write-Host "Successful completions: $successCount/3" -ForegroundColor $(if($successCount -ge 1){'Green'}else{'Red'})
Write-Host "Lock errors: $errorCount" -ForegroundColor $(if($errorCount -le 2){'Green'}else{'Red'})

if ($successCount -ge 1 -and $errorCount -le 2) {
    Write-Host "[PASS] At least one concurrent attempt succeeded" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Concurrent execution handling needs improvement" -ForegroundColor Red
}

# Final cleanup
if (-not $SkipCleanup) {
    Write-Host "`nCleaning up test artifacts..." -ForegroundColor Gray
    Remove-Item -Path (Join-Path $env:TEMP "ArchiveRetention.lock") -Force -ErrorAction SilentlyContinue
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Test 1 (Normal execution): $(if($test1){'PASS'}else{'FAIL'})" -ForegroundColor $(if($test1){'Green'}else{'Red'})
Write-Host "Test 2 (Stale lock): $(if($test2){'PASS'}else{'FAIL'})" -ForegroundColor $(if($test2){'Green'}else{'Red'})
Write-Host "Test 3 (Active lock): $(if($test3){'PASS'}else{'FAIL'})" -ForegroundColor $(if($test3){'Green'}else{'Red'})
Write-Host "Test 4 (ForceClearLock orphaned): $(if($test4){'PASS'}else{'FAIL'})" -ForegroundColor $(if($test4){'Green'}else{'Red'})
Write-Host "Test 5 (ForceClearLock active): $(if($test5){'PASS'}else{'FAIL'})" -ForegroundColor $(if($test5){'Green'}else{'Red'})
Write-Host "Test 6 (Race condition): $(if($raceErrors.Count -eq 0){'PASS'}else{'FAIL'})" -ForegroundColor $(if($raceErrors.Count -eq 0){'Green'}else{'Red'})
Write-Host "Test 7 (Concurrent): $(if($successCount -ge 1){'PASS'}else{'FAIL'})" -ForegroundColor $(if($successCount -ge 1){'Green'}else{'Red'})

$allPassed = $test1 -and $test2 -and $test3 -and $test4 -and $test5 -and ($raceErrors.Count -eq 0) -and ($successCount -ge 1)
Write-Host "`nOverall: $(if($allPassed){'ALL TESTS PASSED!'}else{'SOME TESTS FAILED'})" -ForegroundColor $(if($allPassed){'Green'}else{'Red'})