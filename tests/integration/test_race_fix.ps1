# Test ForceClearLock race condition fix v2.3.18
Write-Host "`nForceClearLock Race Condition Test" -ForegroundColor Cyan

cd C:\LR\Scripts\LRArchiveRetention

# Clean up any existing lock
$lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue

Write-Host "`nTest 1: Create stale lock and use ForceClearLock" -ForegroundColor Yellow

# Create fake lock
"99999" | Set-Content -Path $lockPath -Force
Write-Host "Created stale lock with PID 99999"

# Check log before
$logBefore = Get-Content .\script_logs\ArchiveRetention.log -Tail 1

# Run with ForceClearLock and capture everything
Write-Host "Running ArchiveRetention.ps1 with -ForceClearLock..."
$proc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File .\ArchiveRetention.ps1 -ArchivePath C:\Temp -RetentionDays 1 -ForceClearLock" -Wait -PassThru -WindowStyle Hidden
$exitCode = $proc.ExitCode

Write-Host "Process exit code: $exitCode"

# Get log entries after our marker
$logAfter = Get-Content .\script_logs\ArchiveRetention.log | Select-Object -Last 50

# Look for key messages
$foundStaleRemoved = $false
$foundLockInUse = $false
$foundCompletion = $false

foreach ($line in $logAfter) {
    if ($line -match "Stale lock file removed") {
        $foundStaleRemoved = $true
        Write-Host "  ✓ Found: $line" -ForegroundColor Green
    }
    if ($line -match "lock file in use|being used by another process") {
        $foundLockInUse = $true
        Write-Host "  ✗ Found: $line" -ForegroundColor Red
    }
    if ($line -match "SCRIPT.*DRY-RUN.*COMPLETED") {
        $foundCompletion = $true
        Write-Host "  ✓ Found: $line" -ForegroundColor Green
    }
}

Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  Stale lock removed: $foundStaleRemoved"
Write-Host "  Race condition error: $foundLockInUse"
Write-Host "  Script completed: $foundCompletion"

if ($foundStaleRemoved -and -not $foundLockInUse -and $foundCompletion) {
    Write-Host "`n✅ PASS: ForceClearLock worked correctly!" -ForegroundColor Green
} else {
    Write-Host "`n❌ FAIL: Issues detected" -ForegroundColor Red
    
    # Show more context
    Write-Host "`nRelevant log entries:" -ForegroundColor Yellow
    $logAfter | Where-Object { $_ -match "ForceClearLock|lock|Lock|Orphaned|FATAL|ERROR" } | Select-Object -Last 20
}

Write-Host "`nTest 2: Quick succession test" -ForegroundColor Yellow
$raceCount = 0
for ($i = 1; $i -le 3; $i++) {
    "77777" | Set-Content -Path $lockPath -Force
    $proc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File .\ArchiveRetention.ps1 -ArchivePath C:\Temp -RetentionDays 1 -ForceClearLock" -Wait -PassThru -WindowStyle Hidden
    
    if ($proc.ExitCode -eq 0) {
        Write-Host "  Attempt $i: ✅ Success (exit code 0)" -ForegroundColor Green
    } else {
        Write-Host "  Attempt $i: ❌ Failed (exit code $($proc.ExitCode))" -ForegroundColor Red
        $raceCount++
    }
}

if ($raceCount -eq 0) {
    Write-Host "`n✅ No race conditions in succession test!" -ForegroundColor Green
} else {
    Write-Host "`n❌ $raceCount race conditions detected" -ForegroundColor Red
}