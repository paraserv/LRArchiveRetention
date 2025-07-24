# Start NAS test data generation with proper production format
# This script generates data directly in \\10.20.1.7\LRArchives\Inactive

param(
    [string]$TargetSizeGB = "500",  # Default 500GB
    [int]$YearsBack = 5             # Default 5 years of data
)

# Set up the environment
$scriptPath = "C:\LR\Scripts\LRArchiveRetention"
$testScriptPath = Join-Path $scriptPath "tests\GenerateTestData.ps1"

# Import the credential module
Import-Module "$scriptPath\modules\ShareCredentialHelper.psm1" -Force

# Test if we have NAS credentials
$creds = Get-SavedCredentials | Where-Object { $_.Target -eq "NAS_CREDS" }
if (-not $creds) {
    Write-Error "NAS_CREDS not found. Please run Save-Credential.ps1 first."
    exit 1
}

# Set the NAS path - generate directly in Inactive folder (no TestData subfolder)
$nasPath = "\\10.20.1.7\LRArchives\Inactive"

Write-Host "Starting test data generation on NAS..." -ForegroundColor Green
Write-Host "Target Path: $nasPath"
Write-Host "Target Size: $TargetSizeGB GB"
Write-Host "Years Back: $YearsBack years"
Write-Host ""

# Start the generation with proper parameters
& $testScriptPath `
    -RootPath $nasPath `
    -TargetSizeGB $TargetSizeGB `
    -YearsBack $YearsBack `
    -FileTypes @('.lca') `
    -Verbose

Write-Host "`nGeneration started successfully!" -ForegroundColor Green