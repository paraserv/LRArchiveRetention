# Minimal test to isolate the issue
Write-Host "Starting minimal test..." -ForegroundColor Yellow

cd C:\LR\Scripts\LRArchiveRetention

Write-Host "`nRemoving any lock files..."
Remove-Item "$env:TEMP\ArchiveRetention.lock" -Force -ErrorAction SilentlyContinue
Remove-Item ".ar_lock" -Force -ErrorAction SilentlyContinue

Write-Host "`nRunning script with minimal parameters..."
try {
    & .\ArchiveRetention.ps1 -ArchivePath "C:\Windows\Temp" -RetentionDays 365
} catch {
    Write-Host "`nERROR CAUGHT: $_" -ForegroundColor Red
    Write-Host "Exception type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}

Write-Host "`nTest complete." -ForegroundColor Green