# PowerShell script to generate 2TB of test data
# This will be uploaded and run on the Windows server

Set-Location C:\LR\Scripts\LRArchiveRetention

# Import credential module
Import-Module .\modules\ShareCredentialHelper.psm1 -Force

# Get saved NAS credentials
$credInfo = Get-ShareCredential -Target "NAS_CREDS"
if ($null -eq $credInfo) {
    Write-Error "Failed to load NAS_CREDS. Please run Save-Credential.ps1 first."
    exit 1
}

# Map network drive
Write-Host "Mapping network drive..." -ForegroundColor Cyan
if (Get-PSDrive -Name T -ErrorAction SilentlyContinue) {
    Remove-PSDrive -Name T -Force
}
$drive = New-PSDrive -Name T -PSProvider FileSystem -Root $credInfo.SharePath -Credential $credInfo.Credential -Persist

Write-Host "Successfully mapped drive T: to $($credInfo.SharePath)" -ForegroundColor Green
Write-Host ""

# Run the test data generation
Write-Host "Starting 2TB test data generation..." -ForegroundColor Green
Write-Host "This will take several hours to complete." -ForegroundColor Yellow
Write-Host ""

# Run without CredentialTarget since we already mapped the drive
& pwsh -File .\tests\GenerateTestData.ps1 `
    -RootPath "T:\TestData" `
    -FolderCount 10000 `
    -MinFiles 50 `
    -MaxFiles 100 `
    -MaxFileSizeMB 50 `
    -MaxSizeGB 2048 `
    -ProgressUpdateIntervalSeconds 30

Write-Host ""
Write-Host "Generation complete!" -ForegroundColor Green

# Cleanup drive mapping
Remove-PSDrive -Name T -Force