# Quick test of v2.3.7 auto-enable parallel feature

cd C:\LR\Scripts\LRArchiveRetention
Remove-Item .ar_lock -Force -ErrorAction SilentlyContinue

Write-Host "`n=== Test 1: Local path (should NOT auto-enable) ===" -ForegroundColor Yellow
$localPath = "C:\LR\TestArchives"
if (-not (Test-Path $localPath)) { New-Item -ItemType Directory -Path $localPath -Force | Out-Null }

$output = .\ArchiveRetention.ps1 -ArchivePath $localPath -RetentionDays 511 2>&1 | Out-String
$parallelLine = $output -split "`n" | Where-Object { $_ -match "Parallel Processing:" } | Select-Object -First 1
Write-Host "Result: $parallelLine" -ForegroundColor Cyan

Write-Host "`n=== Test 2: Network path (should auto-enable) ===" -ForegroundColor Yellow
# Use a fake network path that will fail but show config
$output2 = .\ArchiveRetention.ps1 -ArchivePath "\\fake-server\share" -RetentionDays 511 2>&1 | Out-String
$autoLine = $output2 -split "`n" | Where-Object { $_ -match "Auto-enabled" } | Select-Object -First 1
$parallelLine2 = $output2 -split "`n" | Where-Object { $_ -match "Parallel Processing:" } | Select-Object -First 1
Write-Host "Auto-enable: $autoLine" -ForegroundColor Cyan
Write-Host "Config: $parallelLine2" -ForegroundColor Cyan

Write-Host "`nDone!" -ForegroundColor Green