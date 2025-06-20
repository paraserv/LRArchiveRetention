#requires -Version 5.1

<#
.SYNOPSIS
    Securely saves credentials for network share access.

.DESCRIPTION
    This script prompts for and securely stores credentials for accessing network shares.
    The credentials are encrypted using AES-256 and stored in a protected credential store.
    
    Version 2.0 - Enhanced security and error handling.

.PARAMETER CredentialTarget
    A unique name to identify the saved credentials. This will be used as the identifier
    when retrieving the credentials later. Only alphanumeric characters, hyphens, and 
    underscores are allowed.

.PARAMETER SharePath
    The UNC path to the network share that these credentials will be used to access.
    Must be in the format \\server\share.

.PARAMETER UserName
    Username for authentication. Can be in DOMAIN\Username or username@domain.com format.
    If not provided, defaults to 'svc_lrarchive'.

.PARAMETER Password
    Password for non-interactive use. Use single quotes to prevent shell interpretation.
    WARNING: This method exposes passwords in process lists. Use -UseStdin for secure automation.

.PARAMETER UseStdin
    Read password from stdin instead of prompting interactively. This prevents password
    exposure in process command lines. Recommended for secure automation.

.PARAMETER Quiet
    Suppresses interactive prompts and uses default values. Requires either -Password parameter,
    ARCHIVE_PASSWORD environment variable, or -UseStdin to be set.

.PARAMETER Force
    Overwrites existing credentials without prompting.

.PARAMETER SkipValidation
    Skips the network share validation test. Use when the share is temporarily unavailable
    but you need to save the credentials.

.EXAMPLE
    .\Save-Credential.ps1 -CredentialTarget "ProductionShare" -SharePath "\\server\share"
    Interactive mode - prompts for credentials

.EXAMPLE
    .\Save-Credential.ps1 -CredentialTarget "DevShare" -SharePath "\\dev-server\data" -UserName "DOMAIN\admin"
    Prompts for password for specific user

.EXAMPLE
    echo "MySecurePassword" | .\Save-Credential.ps1 -CredentialTarget "SecureShare" -SharePath "\\server\share" -UseStdin -Quiet
    Secure automation method using stdin

.EXAMPLE
    .\Save-Credential.ps1 -CredentialTarget "TempShare" -SharePath "\\offline-server\data" -SkipValidation
    Save credentials without validation

.NOTES
    This script requires the ShareCredentialHelper module to be present in the modules subdirectory.
    The credentials are encrypted using AES-256 encryption and stored securely on the local machine.
    
    SECURITY: Use -UseStdin parameter for secure automation to prevent password exposure in process lists.
    
    Version: 2.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, HelpMessage="Enter a unique name to identify this credential")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [ValidateLength(1, 50)]
    [Alias('Target')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '', 
        Justification='CredentialTarget is a name/identifier, not a password.')]
    [string]$CredentialTarget,

    [Parameter(Mandatory=$true, HelpMessage="Enter the UNC path to the network share")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^\\\\[^\\]+\\[^\\]+')]
    [string]$SharePath,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$UserName = 'svc_lrarchive',

    [Parameter(Mandatory=$false, HelpMessage="Password for non-interactive use")]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [switch]$UseStdin,

    [Parameter(Mandatory=$false)]
    [switch]$Quiet,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script version
$SCRIPT_VERSION = '2.0.0'

# Force quiet operation unless -Verbose is explicitly used
if (-not $PSBoundParameters.ContainsKey('Verbose')) {
    $VerbosePreference = 'SilentlyContinue'
}

# Set quiet mode if requested
if ($Quiet) {
    $VerbosePreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
}

# Function to safely clear sensitive variables
function Clear-SensitiveData {
    [CmdletBinding()]
    param(
        [string[]]$VariableNames
    )
    
    foreach ($varName in $VariableNames) {
        if (Test-Path -Path "variable:$varName") {
            Set-Variable -Name $varName -Value $null -Scope 1
        }
    }
    [System.GC]::Collect()
}

try {
    if (-not $Quiet) {
        Write-Host "Save-Credential v$SCRIPT_VERSION" -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
    }
    
    # Import the helper module
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'modules\ShareCredentialHelper.psm1'
    
    if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
        throw "Required module not found at '$modulePath'. Ensure the ShareCredentialHelper.psm1 file exists in the 'modules' subdirectory."
    }

    # Import module with error handling
    try {
        Import-Module -Name $modulePath -Force -ErrorAction Stop -Verbose:$false
        Write-Verbose "Successfully imported ShareCredentialHelper module"
    }
    catch {
        throw "Failed to import ShareCredentialHelper module: $_"
    }

    # Validate that required functions are available
    $requiredFunctions = @('Save-ShareCredential', 'Get-ShareCredential', 'Test-ShareAccess')
    foreach ($function in $requiredFunctions) {
        if (-not (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Required function '$function' not found in module. Module may be corrupted."
        }
    }

    # Check if credential already exists
    $existingCred = Get-ShareCredential -Target $CredentialTarget -ErrorAction SilentlyContinue
    if ($existingCred -and -not $Force) {
        if ($Quiet) {
            throw "Credential '$CredentialTarget' already exists. Use -Force to overwrite."
        }
        else {
            Write-Warning "Credential '$CredentialTarget' already exists."
            $overwrite = Read-Host "Do you want to overwrite it? (Y/N)"
            if ($overwrite -ne 'Y' -and $overwrite -ne 'y') {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                exit 0
            }
        }
    }

    # Sanitize and normalize inputs
    $CredentialTarget = $CredentialTarget.Trim()
    $SharePath = $SharePath.TrimEnd('\')
    $UserName = $UserName.Trim()

    if (-not $Quiet) {
        Write-Host "`nCredential Details:" -ForegroundColor White
        Write-Host "  Target Name: $CredentialTarget" -ForegroundColor Gray
        Write-Host "  Share Path:  $SharePath" -ForegroundColor Gray
        Write-Host "  Username:    $UserName" -ForegroundColor Gray
    }

    Write-Verbose "Saving credentials for target: $CredentialTarget"
    Write-Verbose "Share path: $SharePath"
    Write-Verbose "Username: $UserName"

    # Get the credential securely
    $credential = $null
    
    if ($UseStdin) {
        # Read password from stdin (secure method for automation)
        if (-not $Quiet) {
            Write-Host "`nReading password from stdin..." -ForegroundColor Yellow
        }
        
        # Read with timeout to prevent hanging
        $inputAvailable = $false
        $timeout = 5000 # 5 seconds
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        while ($stopwatch.ElapsedMilliseconds -lt $timeout -and -not $inputAvailable) {
            if ([Console]::KeyAvailable -or [Console]::In.Peek() -ne -1) {
                $inputAvailable = $true
                break
            }
            Start-Sleep -Milliseconds 100
        }
        
        if (-not $inputAvailable) {
            throw "No input received from stdin within $($timeout/1000) seconds."
        }
        
        $stdinPassword = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($stdinPassword)) {
            throw "No password provided via stdin. Please pipe the password to this script."
        }
        
        $securePassword = ConvertTo-SecureString -String $stdinPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)
        
        # Clear the plain text password immediately
        Clear-SensitiveData -VariableNames 'stdinPassword'
    }
    elseif ($Password) {
        # Create credential from provided password (legacy method)
        if (-not $Quiet) {
            Write-Warning "Using -Password parameter exposes passwords in process lists. Consider using -UseStdin for secure automation."
        }
        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)
        
        # Clear the plain text password immediately
        Clear-SensitiveData -VariableNames 'Password'
    }
    elseif ($env:ARCHIVE_PASSWORD) {
        # Use password from environment variable (legacy method)
        if (-not $Quiet) {
            Write-Warning "Using ARCHIVE_PASSWORD environment variable. Consider using -UseStdin for secure automation."
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
        if (-not $Quiet) {
            Write-Host "`nEnter credentials for accessing '$SharePath'" -ForegroundColor Cyan
        }
        
        $promptMessage = "Enter password for user '$UserName'"
        $credential = Get-Credential -UserName $UserName -Message $promptMessage

        if ($null -eq $credential) {
            Write-Warning "User cancelled the credential prompt. Operation aborted."
            exit 1
        }

        # Validate that the password is not empty
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        try {
            $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            if ([string]::IsNullOrWhiteSpace($plainTextPassword)) {
                throw "Password cannot be empty. Please provide a valid password."
            }
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            Clear-SensitiveData -VariableNames 'plainTextPassword'
        }
    }

    # Test the credentials before saving (unless skipped)
    if (-not $SkipValidation) {
        if (-not $Quiet) {
            Write-Host "`nValidating credentials..." -ForegroundColor Yellow
        }
        
        Write-Verbose "Testing credentials against share: $SharePath"
        
        $testParams = @{
            SharePath = $SharePath
            Credential = $credential
            TimeoutSeconds = 15
        }
        
        $testResult = Test-ShareAccess @testParams
        
        if (-not $testResult) {
            if (-not $Quiet) {
                Write-Host "FAILED: Credential validation failed" -ForegroundColor Red
                Write-Host "Cannot access share '$SharePath' with provided credentials." -ForegroundColor Red
                Write-Host ""
                Write-Host "Please verify:" -ForegroundColor Yellow
                Write-Host "  - Share path is correct and accessible" -ForegroundColor Yellow
                Write-Host "  - Username and password are correct" -ForegroundColor Yellow
                Write-Host "  - Network connectivity to the share" -ForegroundColor Yellow
                Write-Host "  - User has appropriate permissions" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "To skip validation, use the -SkipValidation parameter." -ForegroundColor Gray
            }
            throw "Credential validation failed for share '$SharePath'"
        }
        
        if (-not $Quiet) {
            Write-Host "SUCCESS: Credentials validated successfully" -ForegroundColor Green
        }
    }
    elseif (-not $Quiet) {
        Write-Host "`nSkipping credential validation as requested." -ForegroundColor Yellow
    }

    # Save the credential
    if ($PSCmdlet.ShouldProcess($CredentialTarget, "Save encrypted credentials")) {
        if (-not $Quiet) {
            Write-Host "`nSaving credentials..." -ForegroundColor Yellow
        }
        
        $saveParams = @{
            Target = $CredentialTarget
            SharePath = $SharePath
            Credential = $credential
        }
        
        $result = Save-ShareCredential @saveParams
        
        if ($result) {
            if (-not $Quiet) {
                Write-Host "`nSUCCESS: Credentials saved successfully!" -ForegroundColor Green
                Write-Host ""
                Write-Host "Credential Information:" -ForegroundColor Cyan
                Write-Host "  Target Name: $CredentialTarget" -ForegroundColor White
                Write-Host "  Share Path:  $SharePath" -ForegroundColor White
                Write-Host "  Username:    $UserName" -ForegroundColor White
                Write-Host ""
                Write-Host "To use these credentials, specify: " -NoNewline -ForegroundColor Gray
                Write-Host "-CredentialTarget '$CredentialTarget'" -ForegroundColor Yellow
            }
        }
        else {
            throw "Failed to save credentials. Check the module logs for details."
        }
    }
    else {
        Write-Host "What if: Would save credentials for target '$CredentialTarget'" -ForegroundColor Yellow
    }

    # Success exit
    if (-not $Quiet) {
        Write-Host "`nOperation completed successfully." -ForegroundColor Green
    }
    exit 0
}
catch {
    $errorMsg = $_.Exception.Message
    
    if (-not $Quiet) {
        Write-Host "`nERROR: $errorMsg" -ForegroundColor Red
        
        if ($VerbosePreference -eq 'Continue') {
            Write-Host "`nStack trace:" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        }
    }
    else {
        Write-Error $errorMsg
    }
    
    exit 1
}
finally {
    # Clear any sensitive data from memory
    Clear-SensitiveData -VariableNames @('credential', 'securePassword', 'stdinPassword', 'plainTextPassword', 'Password')
    
    # Remove the imported module to clean up memory
    if (Get-Module -Name ShareCredentialHelper -ErrorAction SilentlyContinue) {
        Remove-Module -Name ShareCredentialHelper -Force -ErrorAction SilentlyContinue -Verbose:$false
    }
}

# End of script
