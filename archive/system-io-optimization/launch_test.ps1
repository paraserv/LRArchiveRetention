# Launch the test in background and monitor it
param(
    [string]$TestScript = "C:\LR\Scripts\LRArchiveRetention\test_systemio_nas.ps1",
    [string]$LogFile = "C:\temp\systemio_test.log"
)

# Clean up any existing log
if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force
}

# Kill any existing PowerShell processes running our test
Get-Process powershell* | Where-Object { 
    $_.CommandLine -like "*test_systemio*" 
} | Stop-Process -Force

Write-Host "Starting background test job..." -ForegroundColor Green
$job = Start-Job -ScriptBlock {
    param($script)
    & $script
} -ArgumentList $TestScript

Write-Host "Job started with ID: $($job.Id)"
Write-Host "Job PID: $($job.ChildJobs[0].Output)"
Write-Host "Log file: $LogFile"
Write-Host ""
Write-Host "Monitoring log output (press Ctrl+C to stop monitoring)..." -ForegroundColor Yellow

# Monitor the log file
$lastPosition = 0
while ($true) {
    if (Test-Path $LogFile) {
        $content = Get-Content $LogFile -Raw
        if ($content.Length -gt $lastPosition) {
            $newContent = $content.Substring($lastPosition)
            Write-Host $newContent -NoNewline
            $lastPosition = $content.Length
        }
    }
    
    # Check if job is still running
    $jobState = Get-Job -Id $job.Id
    if ($jobState.State -ne 'Running') {
        Write-Host "`nJob completed with state: $($jobState.State)" -ForegroundColor Cyan
        break
    }
    
    Start-Sleep -Milliseconds 500
}