# Simple performance comparison test
param(
    [string]$LogFile = "C:\temp\perf_comparison.log"
)

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "Performance Comparison Test - PID: $PID"
Write-Log "=" * 60

# Test 1: Original ArchiveRetention.ps1
Write-Log "`nTEST 1: Original ArchiveRetention.ps1"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
& C:\LR\Scripts\LRArchiveRetention\ArchiveRetention.ps1 -CredentialTarget NAS_CREDS -RetentionDays 365 -QuietMode | Out-File -FilePath "$LogFile.original" -Append
$timer.Stop()
$originalTime = $timer.Elapsed.TotalSeconds
Write-Log "Original script time: $originalTime seconds"

# Extract file count from log
$logContent = Get-Content C:\LR\Scripts\LRArchiveRetention\script_logs\ArchiveRetention.log | Select-String "Found \d+ files"
if ($logContent) {
    Write-Log "Original script result: $logContent"
}

# Test 2: StreamingDelete.ps1 
Write-Log "`nTEST 2: StreamingDelete.ps1"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
& C:\LR\Scripts\LRArchiveRetention\StreamingDelete.ps1 -Path '\\10.20.1.7\LRArchives' -RetentionDays 365 -ShowProgress 0 | Out-File -FilePath "$LogFile.streaming" -Append
$timer.Stop()
$streamingTime = $timer.Elapsed.TotalSeconds
Write-Log "Streaming script time: $streamingTime seconds"

# Check output
$streamOutput = Get-Content "$LogFile.streaming" -Raw
Write-Log "Streaming output length: $($streamOutput.Length) chars"

# Test 3: Direct System.IO test on NAS
Write-Log "`nTEST 3: Direct System.IO enumeration"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$count = 0
try {
    $files = [System.IO.Directory]::EnumerateFiles('\\10.20.1.7\LRArchives', '*.lca', [System.IO.SearchOption]::AllDirectories)
    foreach ($file in $files) {
        $count++
    }
} catch {
    Write-Log "ERROR: $_"
}
$timer.Stop()
Write-Log "System.IO enumeration: $count files in $($timer.Elapsed.TotalSeconds) seconds"

Write-Log "`n" + ("=" * 60)
Write-Log "SUMMARY:"
Write-Log "Original script: $originalTime seconds"
Write-Log "Streaming script: $streamingTime seconds"
Write-Log "Direct System.IO: $($timer.Elapsed.TotalSeconds) seconds"

if ($originalTime -gt 0) {
    Write-Log "Streaming vs Original: $([Math]::Round($originalTime / $streamingTime, 1))x speed"
}