# Cleanup script for test data generation

# Kill any running pwsh processes
Get-Process pwsh -ErrorAction SilentlyContinue | Stop-Process -Force

# Check and remove TestData folder from NAS
$testDataPath = "\\10.20.1.7\LRArchives\Inactive\TestData"
if (Test-Path $testDataPath) {
    Write-Host "Found TestData folder at $testDataPath, removing..."
    Remove-Item $testDataPath -Recurse -Force
    Write-Host "TestData folder removed"
} else {
    Write-Host "No TestData folder found at $testDataPath"
}

# Clean up lock files
Remove-Item -Path "$env:TEMP\ArchiveRetention.lock" -Force -ErrorAction SilentlyContinue