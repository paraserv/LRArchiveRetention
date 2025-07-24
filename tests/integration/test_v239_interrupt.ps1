# Test script to verify Ctrl-C handling in v2.3.9

Write-Host "`n=== Starting test with 120 days retention ===" -ForegroundColor Cyan
Write-Host "This will delete files! Press Ctrl-C after you see some files being deleted." -ForegroundColor Yellow
Write-Host "Starting in 3 seconds..." -ForegroundColor Yellow

Start-Sleep -Seconds 3

cd C:\LR\Scripts\LRArchiveRetention

# Run the script
try {
    & .\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 120 -Execute -ShowDeleteProgress
} catch {
    Write-Host "`nScript was interrupted" -ForegroundColor Yellow
}

Write-Host "`nScript ended. Checking logs in 3 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Check the script log
Write-Host "`n=== Script Log Status ===" -ForegroundColor Cyan
$scriptLog = Get-Content .\script_logs\ArchiveRetention.log -Tail 50
$lastStatus = $scriptLog | Where-Object { $_ -match "SCRIPT.*(SUCCESS|TERMINATED|FAILED)" } | Select-Object -Last 1

if ($lastStatus) {
    if ($lastStatus -match "TERMINATED") {
        Write-Host "[PASS] $lastStatus" -ForegroundColor Green
    } elseif ($lastStatus -match "SUCCESS") {
        Write-Host "[FAIL] $lastStatus" -ForegroundColor Red
        Write-Host "       Script shows SUCCESS but was interrupted!" -ForegroundColor Red
    } else {
        Write-Host "[INFO] $lastStatus" -ForegroundColor Yellow
    }
} else {
    Write-Host "No completion status found in log" -ForegroundColor Yellow
}

# Show deletion progress
Write-Host "`n=== Deletion Progress ===" -ForegroundColor Cyan
$scriptLog | Where-Object { $_ -match "deleted.*files|Parallel streaming progress" } | Select-Object -Last 3

# Check retention log
Write-Host "`n=== Retention Log Check ===" -ForegroundColor Cyan
$retLog = Get-ChildItem .\retention_actions\retention_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($retLog) {
    Write-Host "Checking: $($retLog.Name)" -ForegroundColor Gray
    $content = Get-Content $retLog.FullName
    $fileEntries = @($content | Where-Object { $_ -notmatch "^#" })
    
    Write-Host "Files recorded: $($fileEntries.Count)" -ForegroundColor $(if($fileEntries.Count -gt 0){'Green'}else{'Red'})
    
    if ($fileEntries.Count -gt 0) {
        Write-Host "First 3 files:" -ForegroundColor Gray
        $fileEntries | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" }
    }
    
    # Check summary section
    Write-Host "`nSummary Status:" -ForegroundColor Cyan
    $summaryLine = $content | Where-Object { $_ -match "# Status:" } | Select-Object -Last 1
    if ($summaryLine) {
        if ($summaryLine -match "TERMINATED") {
            Write-Host "[PASS] $summaryLine" -ForegroundColor Green
        } elseif ($summaryLine -match "SUCCESS") {
            Write-Host "[FAIL] $summaryLine" -ForegroundColor Red
        } else {
            Write-Host "[INFO] $summaryLine" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No status line found in summary" -ForegroundColor Yellow
    }
} else {
    Write-Host "No retention log found!" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan