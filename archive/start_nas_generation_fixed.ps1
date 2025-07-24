# Start NAS test data generation with proper production format
# This script generates data directly in \\10.20.1.7\LRArchives\Inactive

param(
    [int]$FolderCount = 10000,      # Number of folders to create
    [int]$MinFiles = 50,            # Min files per folder
    [int]$MaxFiles = 100,           # Max files per folder
    [int]$MaxFileSizeMB = 10,       # Max file size in MB
    [double]$MaxSizeGB = 500        # Target size in GB
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
Write-Host "Folder Count: $FolderCount"
Write-Host "Files per folder: $MinFiles-$MaxFiles"
Write-Host "Max file size: $MaxFileSizeMB MB"
Write-Host "Max total size: $MaxSizeGB GB"
Write-Host ""

# Start the generation with proper parameters
& $testScriptPath `
    -RootPath $nasPath `
    -FolderCount $FolderCount `
    -MinFiles $MinFiles `
    -MaxFiles $MaxFiles `
    -MaxFileSizeMB $MaxFileSizeMB `
    -MaxSizeGB $MaxSizeGB `
    -CredentialTarget "NAS_CREDS" `
    -ProgressUpdateIntervalSeconds 30

Write-Host "`nGeneration started successfully!" -ForegroundColor Green