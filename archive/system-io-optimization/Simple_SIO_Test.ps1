# Simple System.IO test that actually works
Write-Host "Simple System.IO Performance Test" -ForegroundColor Cyan
Write-Host ("=" * 50)

# Step 1: Load module and get credentials
Import-Module C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1 -Force
$creds = Get-SavedShareCredential -Target NAS_CREDS
Write-Host "Got credentials for: $($creds.SharePath)"

# Step 2: Map drive
$drive = New-PSDrive -Name NASTEST -PSProvider FileSystem -Root $creds.SharePath -Credential $creds.Credential -Scope Global
Write-Host "Mapped drive: NASTEST:"

# Step 3: Test Get-ChildItem
Write-Host "`nTest 1: Get-ChildItem"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$files1 = @(Get-ChildItem NASTEST: -Filter *.lca -Recurse | Where-Object { -not $_.PSIsDirectory })
$sw.Stop()
$time1 = $sw.Elapsed.TotalSeconds
Write-Host "  Files: $($files1.Count)"
Write-Host "  Time: $time1 seconds"

# Step 4: Test System.IO
Write-Host "`nTest 2: System.IO.Directory.EnumerateFiles"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$count2 = 0
try {
    # Use the NAS share path directly
    $sioFiles = [System.IO.Directory]::EnumerateFiles($creds.SharePath, "*.lca", [System.IO.SearchOption]::AllDirectories)
    foreach ($f in $sioFiles) { $count2++ }
} catch {
    Write-Host "  Error: $_"
}
$sw.Stop()
$time2 = $sw.Elapsed.TotalSeconds
Write-Host "  Files: $count2"
Write-Host "  Time: $time2 seconds"

# Step 5: Summary
Write-Host "`nSummary:"
Write-Host "  Get-ChildItem: $time1 sec ($($files1.Count) files)"
Write-Host "  System.IO: $time2 sec ($count2 files)"
if ($time1 -gt 0 -and $time2 -gt 0) {
    $speedup = [Math]::Round($time1 / $time2, 1)
    Write-Host "  Speedup: ${speedup}x"
}

# Cleanup
Remove-PSDrive NASTEST -Force