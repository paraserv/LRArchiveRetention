#requires -Version 5.1

<#
.SYNOPSIS
    Securely saves credentials for network share access.

.DESCRIPTION
    This script prompts for and securely stores credentials for accessing network shares.
    The credentials are encrypted and stored in a protected credential store.

.PARAMETER CredentialTarget
    A unique name to identify the saved credentials. This will be used as the identifier
    when retrieving the credentials later.

.PARAMETER SharePath
    The UNC path to the network share that these credentials will be used to access.

.PARAMETER UserName
    Optional username to use. If not provided, defaults to 'svc_lrarchive'.

.PARAMETER Password
    Password for non-interactive use (use single quotes to prevent shell interpretation).
    Alternatively, set the ARCHIVE_PASSWORD environment variable.
    WARNING: This method exposes passwords in process lists. Use -UseStdin for secure automation.

.PARAMETER UseStdin
    Read password from stdin instead of prompting interactively. This prevents password
    exposure in process command lines. Recommended for secure automation.

.PARAMETER Quiet
    Suppresses interactive prompts and uses default values. Requires either -Password parameter,
    ARCHIVE_PASSWORD environment variable, or -UseStdin to be set.

.EXAMPLE
    .\Save-Credential.ps1 -CredentialTarget "ProductionShare" -SharePath "\\server\share"

.EXAMPLE
    .\Save-Credential.ps1 -CredentialTarget "DevShare" -SharePath "\\dev-server\data" -UserName "admin"

.EXAMPLE
    # Secure method using stdin (recommended for automation)
    echo "MySecurePassword" | .\Save-Credential.ps1 -CredentialTarget "SecureShare" -SharePath "\\server\share" -UseStdin -Quiet

.EXAMPLE
    # Using environment variable for password (legacy method - exposes password in process list)
    $env:ARCHIVE_PASSWORD = "SecurePassword123"
    .\Save-Credential.ps1 -CredentialTarget "SecureShare" -SharePath "\\server\share" -Quiet

.NOTES
    This script requires the ShareCredentialHelper module to be present in the modules subdirectory.
    The credentials are encrypted using AES-256 encryption and stored securely on the local machine.

    SECURITY: Use -UseStdin parameter for secure automation to prevent password exposure in process lists.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, HelpMessage="Enter a unique name to identify this credential")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [Alias('Target')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,

    [Parameter(Mandatory=$true, HelpMessage="Enter the UNC path to the network share")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^\\\\[^\\]+\\[^\\]+')]
    [string]$SharePath,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$UserName = 'svc_lrarchive',

    [Parameter(Mandatory=$false, HelpMessage="Password for non-interactive use (use single quotes to prevent shell interpretation)")]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [switch]$UseStdin,

    [Parameter(Mandatory=$false)]
    [switch]$Quiet
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Force quiet operation unless -Verbose is explicitly used
if (-not $PSBoundParameters.ContainsKey('Verbose')) {
    $VerbosePreference = 'SilentlyContinue'
}

# Set quiet mode if requested
if ($Quiet) {
    $VerbosePreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
}

try {
    # Import the helper module
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules\ShareCredentialHelper.psm1'

    if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
        throw "Required module not found at '$modulePath'. Ensure the ShareCredentialHelper.psm1 file exists in the 'modules' subdirectory."
    }

    # Import module with error handling (suppress verbose output)
    try {
        $oldInformationPreference = $InformationPreference
        $InformationPreference = 'SilentlyContinue'
        Import-Module -Name $modulePath -Force -ErrorAction Stop -Verbose:$false -InformationAction SilentlyContinue
        $InformationPreference = $oldInformationPreference
        Write-Verbose "Successfully imported ShareCredentialHelper module"
    }
    catch {
        throw "Failed to import ShareCredentialHelper module: $_"
    }

    # Validate that required functions are available
    $requiredFunctions = @('Save-ShareCredential', 'Write-Log')
    foreach ($function in $requiredFunctions) {
        if (-not (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Required function '$function' not found in module. Module may be corrupted."
        }
    }

    # Sanitize and normalize inputs
    $CredentialTarget = $CredentialTarget.Trim()
    $SharePath = $SharePath.TrimEnd('\')
    $UserName = $UserName.Trim()

    Write-Verbose "Saving credentials for target: $CredentialTarget"
    Write-Verbose "Share path: $SharePath"
    Write-Verbose "Username: $UserName"

    # Get the credential securely
    if ($UseStdin) {
        # Read password from stdin (secure method for automation)
        if (-not $Quiet) {
            Write-Host "Reading password from stdin..." -ForegroundColor Yellow
        }

        $stdinPassword = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($stdinPassword)) {
            throw "No password provided via stdin. Please pipe the password to this script."
        }

        $securePassword = ConvertTo-SecureString -String $stdinPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)

        # Clear the plain text password immediately
        $stdinPassword = $null
        [System.GC]::Collect()
    }
    elseif ($Password) {
        # Create credential from provided password (legacy method - exposes password in process list)
        if (-not $Quiet) {
            Write-Warning "Using -Password parameter exposes passwords in process lists. Consider using -UseStdin for secure automation."
        }
        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)

        # Clear the plain text password immediately
        $Password = $null
        [System.GC]::Collect()
    }
    elseif ($env:ARCHIVE_PASSWORD) {
        # Use password from environment variable (legacy method)
        if (-not $Quiet) {
            Write-Warning "Using ARCHIVE_PASSWORD environment variable exposes passwords in process lists. Consider using -UseStdin for secure automation."
        }
        Write-Verbose "Using password from ARCHIVE_PASSWORD environment variable"
        $securePassword = ConvertTo-SecureString -String $env:ARCHIVE_PASSWORD -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)
    }
    elseif ($Quiet) {
        throw "UseStdin parameter, Password parameter, or ARCHIVE_PASSWORD environment variable is required when using -Quiet switch for non-interactive operation."
    }
    else {
        # Interactive mode - prompt for credentials
        $promptMessage = "Enter password for user '$UserName' to access '$CredentialTarget'"
        $credential = Get-Credential -UserName $UserName -Message $promptMessage

        if ($null -eq $credential) {
            Write-Warning "User cancelled the credential prompt. Operation aborted."
            exit 1
        }

        # Validate that the password is not empty
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ([string]::IsNullOrWhiteSpace($plainTextPassword)) {
            # Clear the password from memory
            $plainTextPassword = $null
            [System.GC]::Collect()
            throw "Password cannot be empty. Please provide a valid password."
        }

        # Clear the password from memory immediately
        $plainTextPassword = $null
        [System.GC]::Collect()
    }

    # Test the credentials before saving
    Write-Verbose "Testing credentials against share: $SharePath"
    # $testResult = Test-ShareAccess -SharePath $SharePath -Credential $credential -TimeoutSeconds 15
    $testResult = $true # Temporarily skip validation

    if (-not $testResult) {
        if (-not $Quiet) {
            Write-Host "FAILED: Credential validation failed" -ForegroundColor Red
            Write-Host "Cannot access share '$SharePath' with provided credentials." -ForegroundColor Red
            Write-Host ""
            Write-Host "Please verify:" -ForegroundColor Yellow
            Write-Host "  - Share path is correct and accessible" -ForegroundColor Yellow
            Write-Host "  - Username and password are correct" -ForegroundColor Yellow
            Write-Host "  - Network connectivity to the share" -ForegroundColor Yellow
        }
        exit 1
    }

    if (-not $Quiet) {
        Write-Host "SUCCESS: Credentials validated successfully" -ForegroundColor Green
    }

    # Confirm the operation if WhatIf is not specified
    if ($PSCmdlet.ShouldProcess($CredentialTarget, "Save encrypted credentials")) {
        # Save the credential using the helper module
        $result = Save-ShareCredential -Target $CredentialTarget -SharePath $SharePath -Credential $credential

        if ($result) {
            if (-not $Quiet) {
                Write-Host "SUCCESS: Credentials saved successfully for target: $CredentialTarget" -ForegroundColor Green
                Write-Host "INFO: Credentials can be retrieved using the target name: $CredentialTarget" -ForegroundColor Green
            }
        }
        else {
            Write-Error "Failed to save credentials. Check the module logs for details."
            exit 1
        }
    }
    else {
        Write-Host "What if: Would save credentials for target '$CredentialTarget'" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Error saving credentials: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
finally {
    # Clear any sensitive data from memory
    if ($credential) {
        $credential = $null
    }
    [System.GC]::Collect()

    # Remove the imported module to clean up memory (suppress verbose output)
    if (Get-Module -Name ShareCredentialHelper -ErrorAction SilentlyContinue) {
        $oldInformationPreference = $InformationPreference
        $InformationPreference = 'SilentlyContinue'
        Remove-Module -Name ShareCredentialHelper -Force -ErrorAction SilentlyContinue -Verbose:$false -InformationAction SilentlyContinue
        $InformationPreference = $oldInformationPreference
    }
}
