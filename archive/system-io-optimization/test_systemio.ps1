# Test System.IO.Directory.EnumerateFiles performance
param(
    [string]$Path = "\\10.20.1.7\LRArchives",
    [int]$RetentionDays = 365
)

Write-Host "Testing System.IO.Directory.EnumerateFiles"
Write-Host "Path: $Path"
Write-Host "Retention: $RetentionDays days"
Write-Host ""

$cutoff = (Get-Date).AddDays(-$RetentionDays)
Write-Host "Cutoff date: $($cutoff.ToString('yyyy-MM-dd'))"

# Test 1: Count all files
Write-Host "`nTest 1: Enumerate all .lca files"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$allCount = 0
try {
    $files = [System.IO.Directory]::EnumerateFiles($Path, "*.lca", [System.IO.SearchOption]::AllDirectories)
    foreach ($file in $files) {
        $allCount++
    }
}
catch {
    Write-Host "Error: $_"
}
$timer.Stop()
Write-Host "Total files found: $allCount"
Write-Host "Enumeration time: $($timer.Elapsed.TotalSeconds) seconds"

# Test 2: Count old files
Write-Host "`nTest 2: Count files older than $RetentionDays days"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$oldCount = 0
$totalSize = 0
try {
    $files = [System.IO.Directory]::EnumerateFiles($Path, "*.lca", [System.IO.SearchOption]::AllDirectories)
    foreach ($filePath in $files) {
        $fileInfo = [System.IO.FileInfo]::new($filePath)
        if ($fileInfo.LastWriteTime -lt $cutoff) {
            $oldCount++
            $totalSize += $fileInfo.Length
        }
    }
}
catch {
    Write-Host "Error: $_"
}
$timer.Stop()
Write-Host "Files to delete: $oldCount"
Write-Host "Total size: $([Math]::Round($totalSize / 1GB, 2)) GB"
Write-Host "Processing time: $($timer.Elapsed.TotalSeconds) seconds"

# Compare with Get-ChildItem
Write-Host "`nTest 3: Compare with Get-ChildItem"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$gcFiles = Get-ChildItem -Path $Path -Filter *.lca -File -Recurse
$gcOldFiles = $gcFiles | Where-Object { $_.LastWriteTime -lt $cutoff }
$timer.Stop()
Write-Host "Get-ChildItem found: $($gcFiles.Count) total, $($gcOldFiles.Count) old"
Write-Host "Get-ChildItem time: $($timer.Elapsed.TotalSeconds) seconds"