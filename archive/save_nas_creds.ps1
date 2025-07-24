# Save NAS credentials
param(
    [string]$Password
)

cd C:\LR\Scripts\LRArchiveRetention

# Use the password from stdin to save credentials
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("sanghanas", $securePassword)

# Import module and save credentials
Import-Module .\modules\ShareCredentialHelper.psm1 -Force

# Test connection first
Write-Host "Testing connection to \\10.20.1.7\LRArchives..." -ForegroundColor Yellow
$testPath = "\\10.20.1.7\LRArchives"

try {
    # Try to connect with the credential
    $null = New-PSDrive -Name "TestNAS" -PSProvider FileSystem -Root $testPath -Credential $credential -ErrorAction Stop
    Remove-PSDrive -Name "TestNAS" -Force
    Write-Host "Connection successful!" -ForegroundColor Green
    
    # Save the credential
    Save-NetworkCredential -Target "NAS_CREDS" -UserName "sanghanas" -Password $Password -SharePath $testPath
    Write-Host "NAS_CREDS saved successfully!" -ForegroundColor Green
    
    # Verify it was saved
    $saved = Get-SavedCredentials | Where-Object { $_.Target -eq "NAS_CREDS" }
    if ($saved) {
        Write-Host "Verification: NAS_CREDS found in credential store" -ForegroundColor Green
        $saved | Format-List
    }
} catch {
    Write-Error "Failed to connect to NAS: $_"
    exit 1
}