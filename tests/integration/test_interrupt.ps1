# Test script to verify Ctrl-C handling in v2.3.9

Write-Host "`n=== Starting test with 120 days retention ===" -ForegroundColor Cyan
Write-Host "This will delete files! Press Ctrl-C after you see some files being deleted." -ForegroundColor Yellow
Write-Host "Starting in 3 seconds..." -ForegroundColor Yellow

Start-Sleep -Seconds 3

cd C:\LR\Scripts\LRArchiveRetention

# Run the script
& .\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 120 -Execute -ShowDeleteProgress

Write-Host "`nScript ended. Checking logs..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# Check the last line of script log
Write-Host "`n=== Script Log Status ===" -ForegroundColor Cyan
$lastStatus = Get-Content .\script_logs\ArchiveRetention.log | Select-Object -Last 20 | Where-Object { $_ -match "SCRIPT.*SUCCESS|TERMINATED" } | Select-Object -Last 1
if ($lastStatus) {
    if ($lastStatus -match "TERMINATED") {
        Write-Host "✓ GOOD: $lastStatus" -ForegroundColor Green
    } else {
        Write-Host "✗ BAD: $lastStatus" -ForegroundColor Red
    }
} else {
    Write-Host "No retention log found" -ForegroundColor Yellow
} else {
    Write-Host "No completion status found" -ForegroundColor Yellow
}

# Check retention log
Write-Host "`n=== Retention Log Check ===" -ForegroundColor Cyan
$retLog = Get-ChildItem .\retention_actions\*.log | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if ($retLog) {
    $content = Get-Content $retLog.FullName
    $files = $content | Where-Object { $_ -notmatch "^#" }
    Write-Host "Retention log: $($retLog.Name)"
    Write-Host "Files recorded: $($files.Count)"
    
    # Check summary
    $summary = $content | Select-Object -Last 10 | Where-Object { $_ -match "Status:" }
    if ($summary) {
        if ($summary -match "TERMINATED") {
            Write-Host "✓ GOOD: $summary" -ForegroundColor Green
        } else {
            Write-Host "✗ BAD: $summary" -ForegroundColor Red
        }
    }
} else {
    Write-Host "No retention log found" -ForegroundColor Yellow
}