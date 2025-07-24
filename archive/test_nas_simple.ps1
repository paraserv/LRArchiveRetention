# Simple NAS test
cd C:\LR\Scripts\LRArchiveRetention
Import-Module .\modules\ShareCredentialHelper.psm1 -Force

# Get credentials
$cred = Get-CredentialFromStore -Target "NAS_CREDS"
if (-not $cred) {
    Write-Error "NAS_CREDS not found"
    exit 1
}

# Create test folder
$testPath = "\\10.20.1.7\LRArchives\Inactive\TEST_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "Creating test folder: $testPath" -ForegroundColor Yellow

# Map drive with credentials
try {
    $null = New-PSDrive -Name "NASTest" -PSProvider FileSystem -Root "\\10.20.1.7\LRArchives" -Credential $cred -ErrorAction Stop
    Write-Host "Drive mapped successfully" -ForegroundColor Green
    
    # Create test folder
    New-Item -Path "NASTest:\Inactive\TEST_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -ItemType Directory -Force
    Write-Host "Test folder created successfully!" -ForegroundColor Green
    
    # List contents
    Get-ChildItem "NASTest:\Inactive" | Select-Object Name, LastWriteTime
    
    Remove-PSDrive -Name "NASTest" -Force
} catch {
    Write-Error "Failed: $_"
}