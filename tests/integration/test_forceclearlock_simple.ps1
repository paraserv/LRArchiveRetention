# Simple test for ForceClearLock race condition fix v2.3.18

Write-Host "`nTesting ForceClearLock race condition fix..." -ForegroundColor Cyan

cd C:\LR\Scripts\LRArchiveRetention

# Show version
$version = Get-Content .\VERSION
Write-Host "Script version: $version" -ForegroundColor Gray

# Test 1: Create orphaned lock and use ForceClearLock
Write-Host "`nTest: ForceClearLock with orphaned lock file" -ForegroundColor Yellow

# Create fake lock
$lockPath = Join-Path $env:TEMP "ArchiveRetention.lock"
"99999`n$(Get-Date)" | Set-Content -Path $lockPath -Force
Write-Host "Created orphaned lock file at: $lockPath" -ForegroundColor Gray

# Run with ForceClearLock (dry-run mode - no -Execute flag)
Write-Host "Running script with -ForceClearLock..." -ForegroundColor Gray
$output = & .\ArchiveRetention.ps1 -ArchivePath "C:\Temp" -RetentionDays 1 -ForceClearLock 2>&1 | Out-String

# Check for key messages
$hasOrphanedMsg = $output -match "Orphaned lock file removed"
$hasCompletion = $output -match "DRY-RUN|dry-run|Dry-run"
$hasRaceError = $output -match "lock file in use|being used by another process"

Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  - Found 'Orphaned lock file removed': $hasOrphanedMsg"
Write-Host "  - Script completed successfully: $hasCompletion"  
Write-Host "  - Race condition error detected: $hasRaceError"

if ($hasOrphanedMsg -and $hasCompletion -and -not $hasRaceError) {
    Write-Host "`n✅ PASS: ForceClearLock worked correctly - no race condition!" -ForegroundColor Green
} else {
    Write-Host "`n❌ FAIL: ForceClearLock race condition detected" -ForegroundColor Red
    Write-Host "`nRelevant output lines:" -ForegroundColor Yellow
    $output -split "`n" | Where-Object { $_ -match "lock|Lock|Orphaned|ForceClearLock|ERROR|FATAL" } | Select-Object -First 10
}