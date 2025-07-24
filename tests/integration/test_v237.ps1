# Test script for v2.3.7 parallel auto-enable

cd C:\LR\Scripts\LRArchiveRetention

Write-Host "`n=== Testing v2.3.7 Parallel Auto-Enable ===" -ForegroundColor Cyan

# Remove lock file
if (Test-Path .ar_lock) { Remove-Item .ar_lock -Force }

# Test 1: Network path via credentials (should auto-enable)
Write-Host "`nTest 1: Network path via NAS_CREDS (should auto-enable parallel)" -ForegroundColor Yellow
$output = .\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 511 2>&1 | Out-String

# Check for key indicators
$foundAutoEnable = $output -match "Auto-enabled parallel"
$foundParallel = $output -match "Parallel Processing: Enabled"
$found8Threads = $output -match "8 threads"

Write-Host "  Auto-enable message: $(if($foundAutoEnable){'✓ FOUND'}else{'✗ NOT FOUND'})" -ForegroundColor $(if($foundAutoEnable){'Green'}else{'Red'})
Write-Host "  Parallel enabled: $(if($foundParallel){'✓ FOUND'}else{'✗ NOT FOUND'})" -ForegroundColor $(if($foundParallel){'Green'}else{'Red'})
Write-Host "  8 threads: $(if($found8Threads){'✓ FOUND'}else{'✗ NOT FOUND'})" -ForegroundColor $(if($found8Threads){'Green'}else{'Red'})

# Show relevant output lines
Write-Host "`nRelevant output lines:" -ForegroundColor Cyan
$output -split "`n" | Where-Object { $_ -match "(configuration:|Archive Path:|Parallel Processing:|Auto-enabled|threads)" } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

# Test 2: Sequential override (should show warning)
Write-Host "`n`nTest 2: Network path with -Sequential (should show warning)" -ForegroundColor Yellow
$output2 = .\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 511 -Sequential 2>&1 | Out-String

$foundWarning = $output2 -match "PERFORMANCE WARNING"
$foundSequential = $output2 -match "sequential mode requested"

Write-Host "  Performance warning: $(if($foundWarning){'✓ FOUND'}else{'✗ NOT FOUND'})" -ForegroundColor $(if($foundWarning){'Green'}else{'Red'})
Write-Host "  Sequential mode: $(if($foundSequential){'✓ FOUND'}else{'✗ NOT FOUND'})" -ForegroundColor $(if($foundSequential){'Green'}else{'Red'})

# Show warning output
if ($foundWarning) {
    Write-Host "`nWarning output:" -ForegroundColor Cyan
    $output2 -split "`n" | Where-Object { $_ -match "WARNING" } | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan