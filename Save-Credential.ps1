param(
    [Parameter(Mandatory=$true)]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,

    [Parameter(Mandatory=$true)]
    [string]$SharePath
)

# Import the helper module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules\ShareCredentialHelper.psm1'
if (-not (Test-Path -Path $modulePath)) {
    throw "Helper module not found at '$modulePath'. Make sure it is in the 'modules' subdirectory."
}
Import-Module -Name $modulePath -Force

# Get the credential from the user
$credential = Get-Credential -UserName 'svc_lrarchive' -Message "Enter password for '$CredentialTarget'"

if ($null -eq $credential) {
    Write-Error "User cancelled the credential prompt. Aborting."
    exit 1
}

# Save the credential
Save-ShareCredential -Target $CredentialTarget -SharePath $SharePath -Credential $credential
