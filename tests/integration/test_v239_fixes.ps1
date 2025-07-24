# Test v2.3.9 fixes for Ctrl-C and retention logging

Write-Host "`n=== Testing v2.3.9 Fixes ===" -ForegroundColor Cyan

cd C:\LR\Scripts\LRArchiveRetention

# Test 1: Quick execution with manual termination
Write-Host "`nTest 1: Starting execution with 548 days (1.5 years) retention..." -ForegroundColor Yellow
Write-Host "Press Ctrl-C after you see some files being deleted!" -ForegroundColor Yellow
Write-Host "Starting in 3 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

try {
    .\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 548 -Execute -ShowDeleteProgress
} catch {
    Write-Host "`nCaught interruption!" -ForegroundColor Yellow
}

# Wait a moment for logs to be written
Start-Sleep -Seconds 2

# Check the results
Write-Host "`n=== Checking Results ===" -ForegroundColor Cyan

# Check script log
Write-Host "`nScript log (last 20 lines):" -ForegroundColor Yellow
Get-Content .\script_logs\ArchiveRetention.log -Tail 20 | Where-Object { $_ -match "(SCRIPT|deleted|TERMINATED|SUCCESS|FAILED)" } | ForEach-Object {
    if ($_ -match "TERMINATED") {
        Write-Host $_ -ForegroundColor Green
    } elseif ($_ -match "SUCCESS" -and $_ -match "SCRIPT") {
        Write-Host $_ -ForegroundColor Red
    } else {
        Write-Host $_
    }
}

# Check retention log
Write-Host "`nRetention log check:" -ForegroundColor Yellow
$retentionLog = Get-ChildItem .\retention_actions\retention_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($retentionLog) {
    $lines = Get-Content $retentionLog.FullName
    $fileCount = ($lines | Where-Object { $_ -notmatch "^#" }).Count
    Write-Host "  Retention log: $($retentionLog.Name)" -ForegroundColor Cyan
    Write-Host "  Files recorded: $fileCount" -ForegroundColor $(if($fileCount -gt 0){'Green'}else{'Red'})
    
    # Show summary section
    Write-Host "`n  Summary section:" -ForegroundColor Yellow
    $lines | Select-Object -Last 10 | ForEach-Object {
        if ($_ -match "TERMINATED") {
            Write-Host "  $_" -ForegroundColor Green
        } elseif ($_ -match "SUCCESS" -and $_ -match "Status:") {
            Write-Host "  $_" -ForegroundColor Red
        } else {
            Write-Host "  $_"
        }
    }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "Look for:" -ForegroundColor Yellow
Write-Host "  ✓ 'TERMINATED' in script log (not 'SUCCESS')" -ForegroundColor Green
Write-Host "  ✓ Files listed in retention log" -ForegroundColor Green
Write-Host "  ✓ 'Status: TERMINATED' in retention log summary" -ForegroundColor Green