# Test NAS access with credentials
cd C:\LR\Scripts\LRArchiveRetention
Import-Module .\modules\ShareCredentialHelper.psm1

# Get saved credentials
$savedCred = Get-StoredCredential -Target "NAS_CREDS"
if (-not $savedCred) {
    Write-Error "NAS_CREDS not found!"
    exit 1
}

# Test connection
$nasPath = "\\10.20.1.7\LRArchives"
Write-Host "Testing connection to $nasPath with saved credentials..." -ForegroundColor Yellow

try {
    # Create temporary drive
    $null = New-PSDrive -Name "TestNAS" -PSProvider FileSystem -Root $nasPath -Credential $savedCred -ErrorAction Stop
    Write-Host "Successfully connected!" -ForegroundColor Green
    
    # Check Inactive folder
    $inactivePath = Join-Path $nasPath "Inactive"
    if (Test-Path $inactivePath) {
        Write-Host "Inactive folder exists: $inactivePath" -ForegroundColor Green
        
        # List contents
        $items = Get-ChildItem -Path $inactivePath -ErrorAction SilentlyContinue
        Write-Host "Current items in Inactive: $($items.Count)" -ForegroundColor Cyan
    } else {
        Write-Host "Inactive folder not found!" -ForegroundColor Red
    }
    
    # Clean up
    Remove-PSDrive -Name "TestNAS" -Force
} catch {
    Write-Error "Failed to connect: $_"
}