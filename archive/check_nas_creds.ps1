# Check NAS credentials
cd C:\LR\Scripts\LRArchiveRetention
Import-Module .\modules\ShareCredentialHelper.psm1

$creds = Get-SavedCredentials | Where-Object { $_.Target -eq "NAS_CREDS" }
if ($creds) {
    Write-Host "NAS_CREDS found:" -ForegroundColor Green
    $creds | Format-List
} else {
    Write-Host "NAS_CREDS NOT FOUND!" -ForegroundColor Red
    Write-Host "Available credentials:"
    Get-SavedCredentials | Format-Table -AutoSize
}