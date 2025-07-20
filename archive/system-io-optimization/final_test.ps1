# Final simple test - just enumerate files
Write-Host "Testing System.IO.Directory.EnumerateFiles on NAS"
Write-Host "=" * 50

$nasPath = '\\10.20.1.7\LRArchives'
Write-Host "Path: $nasPath"

# Test 1: Can we access it at all?
Write-Host "`nTest 1: Basic access"
if (Test-Path $nasPath) {
    Write-Host "SUCCESS: Path is accessible"
} else {
    Write-Host "FAIL: Cannot access path"
    # Try with saved credentials
    Write-Host "Loading credential module..."
    Import-Module C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1 -Force
    $creds = Get-SavedShareCredential -Target NAS_CREDS
    Write-Host "Got credentials for: $($creds.SharePath)"
    
    # Map drive
    $drive = New-PSDrive -Name NASTEST -PSProvider FileSystem -Root $creds.SharePath -Credential $creds.Credential
    $nasPath = "NASTEST:"
    Write-Host "Mapped drive: $nasPath"
}

# Test 2: Count files with Get-ChildItem
Write-Host "`nTest 2: Get-ChildItem performance"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$files = @(Get-ChildItem -Path $nasPath -Filter *.lca -File -Recurse)
$timer.Stop()
Write-Host "Files found: $($files.Count)"
Write-Host "Time: $($timer.Elapsed.TotalSeconds) seconds"
Write-Host "Rate: $([Math]::Round($files.Count / $timer.Elapsed.TotalSeconds, 0)) files/sec"

# Test 3: Count with System.IO
Write-Host "`nTest 3: System.IO.Directory.EnumerateFiles performance"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$count = 0
try {
    # Use UNC path for System.IO
    $enumPath = if ($nasPath -like "*:") { '\\10.20.1.7\LRArchives' } else { $nasPath }
    Write-Host "Enumerating from: $enumPath"
    
    $enumFiles = [System.IO.Directory]::EnumerateFiles($enumPath, "*.lca", [System.IO.SearchOption]::AllDirectories)
    foreach ($file in $enumFiles) {
        $count++
    }
} catch {
    Write-Host "ERROR: $_"
}
$timer.Stop()
Write-Host "Files found: $count"
Write-Host "Time: $($timer.Elapsed.TotalSeconds) seconds"
if ($count -gt 0) {
    Write-Host "Rate: $([Math]::Round($count / $timer.Elapsed.TotalSeconds, 0)) files/sec"
}

# Summary
Write-Host "`n" + ("=" * 50)
Write-Host "RESULTS:"
Write-Host "Get-ChildItem found: $($files.Count) files"
Write-Host "System.IO found: $count files"

# Cleanup
if (Get-PSDrive -Name NASTEST -ErrorAction SilentlyContinue) {
    Remove-PSDrive -Name NASTEST -Force
}