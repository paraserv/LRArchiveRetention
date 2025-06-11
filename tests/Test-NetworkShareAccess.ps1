<#
.SYNOPSIS
    Test script for network share access with secure credential management.

.DESCRIPTION
    This script demonstrates how to securely store and use credentials for accessing network shares.
    It includes functions for saving, retrieving, and testing credentials.

.PARAMETER Action
    The action to perform: 'SaveCredential', 'TestAccess', or 'ListShares'.

.PARAMETER Target
    A name to identify the saved credential (e.g., 'NAS_Archive').

.PARAMETER SharePath
    The UNC path to the network share (e.g., '\\server\share').

.EXAMPLE
    # Save credentials for later use
    .\Test-NetworkShareAccess.ps1 -Action SaveCredential -Target NAS_Archive -SharePath \\nas\archive

.EXAMPLE
    # Test access to a share
    .\Test-NetworkShareAccess.ps1 -Action TestAccess -Target NAS_Archive

.EXAMPLE
    # List available shares on a server (requires admin rights)
    .\Test-NetworkShareAccess.ps1 -Action ListShares -SharePath \\nas
#>

# Simple parameter handling without attributes to avoid parsing issues
param (
    [string]$Action,
    [string]$Target,
    [string]$SharePath
)

# Validate action parameter
$validActions = @('SaveCredential', 'TestAccess', 'ListShares')
if ($validActions -notcontains $Action) {
    Write-Error "Invalid action. Must be one of: $($validActions -join ', ')"
    exit 1
}

# Validate parameter combinations based on action
if ($Action -eq 'ListShares' -and -not $SharePath) {
    throw "SharePath is required when Action is 'ListShares'"
}

if ($Action -eq 'TestAccess' -and -not $Target) {
    throw "Target is required when Action is 'TestAccess'"
}

if ($Action -eq 'SaveCredential' -and (-not $Target -or -not $SharePath)) {
    throw "Both Target and SharePath are required when Action is 'SaveCredential'"
}

# Set error action preference
$ErrorActionPreference = "Stop"

# Load helper module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "ShareCredentialHelper.psm1"
if (-not (Test-Path -Path $modulePath)) {
    Write-Error "Required module not found: $modulePath"
    exit 1
}
Import-Module -Name $modulePath -Force

try {
    switch ($Action) {
        'SaveCredential' {
            # Prompt for credentials
            $credential = Get-Credential -Message "Enter credentials for $SharePath"
            if ($credential) {
                $result = Save-ShareCredential -Target $Target -SharePath $SharePath -Credential $credential
                if ($result) {
                    Write-Log "Credentials saved successfully for target: $Target" -Level SUCCESS
                } else {
                    Write-Log "Failed to save credentials" -Level ERROR
                }
            } else {
                Write-Log "No credentials provided" -Level WARNING
            }
        }
        
        'TestAccess' {
            # Get saved credential data
            $credFile = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'CredentialStore') -ChildPath "$Target.cred"
            if (-not (Test-Path -Path $credFile)) {
                throw "No saved credential found for target: $Target"
            }
            
            # Import the credential data to get the saved SharePath
            $credData = Import-Clixml -Path $credFile
            
            # Use the saved SharePath if not explicitly provided
            if (-not $PSBoundParameters.ContainsKey('SharePath')) {
                $SharePath = $credData.SharePath
                Write-Log "Using saved SharePath: $SharePath" -Level INFO
            }
            
            $credential = Get-ShareCredential -Target $Target
            $result = Test-ShareAccess -SharePath $SharePath -Credential $credential
            
            if (-not $result) {
                Write-Log "Access test failed. Would you like to try with different credentials? (Y/N)" -Level WARNING
                $response = Read-Host
                if ($response -eq 'Y') {
                    $credential = Get-Credential -Message "Enter alternate credentials for $SharePath"
                    if ($credential) {
                        $result = Test-ShareAccess -SharePath $SharePath -Credential $credential
                        if ($result) {
                            Write-Log "Success! Would you like to save these credentials? (Y/N)" -Level INFO
                            $saveResponse = Read-Host
                            if ($saveResponse -eq 'Y') {
                                Save-ShareCredential -Target $Target -Credential $credential
                            }
                        }
                    }
                }
            }
        }
        
        'ListShares' {
            $server = ($SharePath -replace '^\\\\', '') -split '\\' | Select-Object -First 1
            if (-not $server) {
                throw "Invalid server path: $SharePath"
            }
            
            # Try with current user first
            $result = Get-NetworkShares -Server $server
            
            if (-not $result) {
                Write-Log "Failed to list shares with current credentials. Would you like to try with different credentials? (Y/N)" -Level WARNING
                $response = Read-Host
                if ($response -eq 'Y') {
                    $credential = Get-Credential -Message "Enter credentials for $server"
                    if ($credential) {
                        Get-NetworkShares -Server $server -Credential $credential
                    }
                }
            }
        }
    }
} catch {
    Write-Log "An error occurred: $_" -Level ERROR
    exit 1
} finally {
    # Clean up
    Remove-Module -Name ShareCredentialHelper -ErrorAction SilentlyContinue
}
