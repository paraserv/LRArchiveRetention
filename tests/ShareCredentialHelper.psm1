<#
.SYNOPSIS
    Helper functions for secure credential management and network share access.
.DESCRIPTION
    This module provides functions for securely storing and retrieving credentials,
    as well as testing network share access with those credentials.
#>

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-level variables
$script:ModuleName = 'ShareCredentialHelper'
$script:CredentialStorePath = Join-Path -Path $PSScriptRoot -ChildPath 'CredentialStore'
$script:LogFile = $null  # Initialize LogFile variable
$script:KeyPath = Join-Path -Path $script:CredentialStorePath -ChildPath '.key'

<#
.SYNOPSIS
    Writes a log message with a timestamp and log level.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL', 'SUCCESS')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsoleOutput
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not $NoConsoleOutput) {
        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            'INFO'    { Write-Host $logMessage -ForegroundColor Cyan }
            'DEBUG'   { if ($VerbosePreference -eq 'Continue') { Write-Host $logMessage -ForegroundColor Gray } }
            'FATAL'   { Write-Host $logMessage -BackgroundColor Red -ForegroundColor White }
            default   { Write-Host $logMessage }
        }
    }
    
    # Add to log file if configured
    if (-not [string]::IsNullOrEmpty($script:LogFile)) {
        try {
            # Ensure directory exists
            $logDir = Split-Path -Path $script:LogFile -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            # Write to log file
            Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
        } catch {
            # If we can't write to the log file, write to console
            Write-Host "[WARNING] Failed to write to log file ($script:LogFile): $_" -ForegroundColor Yellow
        }
    }
}

<#
.SYNOPSIS
    Initializes the credential store directory with proper permissions.
#>
function Initialize-CredentialStore {
    [CmdletBinding()]
    param()
    
    try {
        # Initialize logging if not already set
        if ([string]::IsNullOrEmpty($script:LogFile)) {
            $logDir = Join-Path -Path $PSScriptRoot -ChildPath 'Logs'
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $script:LogFile = Join-Path -Path $logDir -ChildPath "$($script:ModuleName).log"
        }
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            $null = New-Item -Path $script:CredentialStorePath -ItemType Directory -Force
            Write-Log "Created credential store directory at: $($script:CredentialStorePath)" -Level INFO
        }
        
        # Set directory permissions to restrict access
        $acl = Get-Acl -Path $script:CredentialStorePath
        $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, remove existing rules
        
        # Add full control for the current user
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            'FullControl',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        
        # Add SYSTEM account
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $systemUser = $systemSid.Translate([System.Security.Principal.NTAccount])
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $systemUser,
            'FullControl',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        
        Set-Acl -Path $script:CredentialStorePath -AclObject $acl
        Write-Log "Set permissions on credential store directory" -Level DEBUG
        
        return $true
    }
    catch {
        $errorMsg = "Failed to initialize credential store: $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Generates or retrieves the encryption key for secure credential storage.
.DESCRIPTION
    Creates a machine-specific AES encryption key for cross-platform credential encryption.
    The key is stored in a protected file within the credential store.
#>
function Get-EncryptionKey {
    [CmdletBinding()]
    param()
    
    try {
        # Ensure credential store exists
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            Initialize-CredentialStore | Out-Null
        }
        
        # Check if key already exists
        if (Test-Path -Path $script:KeyPath) {
            Write-Log "Loading existing encryption key" -Level DEBUG
            $keyData = Get-Content -Path $script:KeyPath -Raw | ConvertFrom-Json
            $key = [System.Convert]::FromBase64String($keyData.Key)
            return $key
        }
        
        # Generate new AES key (256-bit)
        Write-Log "Generating new encryption key" -Level INFO
        $key = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        $rng.GetBytes($key)
        $rng.Dispose()
        
        # Save key to file
        $keyData = @{
            Key = [System.Convert]::ToBase64String($key)
            Created = Get-Date
            Algorithm = 'AES256'
        }
        
        $keyData | ConvertTo-Json | Set-Content -Path $script:KeyPath -Force
        
        # Set restrictive permissions on key file
        if ($env:OS -eq 'Windows_NT') {
            $acl = Get-Acl -Path $script:KeyPath
            $acl.SetAccessRuleProtection($true, $false)
            
            # Add current user
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser,
                'Read',
                'Allow'
            )
            $acl.AddAccessRule($accessRule)
            
            # Add SYSTEM account
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $systemUser = $systemSid.Translate([System.Security.Principal.NTAccount])
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $systemUser,
                'Read',
                'Allow'
            )
            $acl.AddAccessRule($accessRule)
            
            Set-Acl -Path $script:KeyPath -AclObject $acl
        } else {
            # Unix/Linux permissions
            chmod 600 $script:KeyPath 2>$null
        }
        
        Write-Log "Encryption key created and secured" -Level SUCCESS
        return $key
    }
    catch {
        $errorMsg = "Failed to manage encryption key: $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Encrypts a secure string using AES encryption.
.DESCRIPTION
    Converts a SecureString to an encrypted string using AES encryption with the machine key.
.PARAMETER SecureString
    The SecureString to encrypt.
#>
function ConvertFrom-SecureStringAES {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]$SecureString
    )
    
    try {
        # Get encryption key
        $key = Get-EncryptionKey
        
        # Convert SecureString to plain text (in memory only)
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        
        # Convert to bytes
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
        
        # Clear plain text from memory
        $plainText = $null
        [System.GC]::Collect()
        
        # Create AES encryption
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.GenerateIV()
        
        # Encrypt
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        
        # Combine IV and encrypted data
        $result = New-Object byte[] ($aes.IV.Length + $encryptedBytes.Length)
        [System.Array]::Copy($aes.IV, 0, $result, 0, $aes.IV.Length)
        [System.Array]::Copy($encryptedBytes, 0, $result, $aes.IV.Length, $encryptedBytes.Length)
        
        # Convert to base64
        $encrypted = [System.Convert]::ToBase64String($result)
        
        # Clean up
        $aes.Dispose()
        $encryptor.Dispose()
        $plainBytes = $null
        $encryptedBytes = $null
        $key = $null
        [System.GC]::Collect()
        
        return $encrypted
    }
    catch {
        throw "Failed to encrypt data: $_"
    }
}

<#
.SYNOPSIS
    Decrypts an AES encrypted string to a SecureString.
.DESCRIPTION
    Converts an AES encrypted string back to a SecureString.
.PARAMETER EncryptedString
    The encrypted base64 string to decrypt.
#>
function ConvertTo-SecureStringAES {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$EncryptedString
    )
    
    try {
        # Get encryption key
        $key = Get-EncryptionKey
        
        # Convert from base64
        $encryptedData = [System.Convert]::FromBase64String($EncryptedString)
        
        # Extract IV and encrypted bytes
        $ivLength = 16  # AES IV is always 16 bytes
        $iv = New-Object byte[] $ivLength
        $encryptedBytes = New-Object byte[] ($encryptedData.Length - $ivLength)
        
        [System.Array]::Copy($encryptedData, 0, $iv, 0, $ivLength)
        [System.Array]::Copy($encryptedData, $ivLength, $encryptedBytes, 0, $encryptedBytes.Length)
        
        # Create AES decryption
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV = $iv
        
        # Decrypt
        $decryptor = $aes.CreateDecryptor()
        $plainBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        
        # Convert to string
        $plainText = [System.Text.Encoding]::UTF8.GetString($plainBytes)
        
        # Convert to SecureString
        $secureString = New-Object System.Security.SecureString
        foreach ($char in $plainText.ToCharArray()) {
            $secureString.AppendChar($char)
        }
        $secureString.MakeReadOnly()
        
        # Clean up
        $aes.Dispose()
        $decryptor.Dispose()
        $plainText = $null
        $plainBytes = $null
        $key = $null
        [System.GC]::Collect()
        
        return $secureString
    }
    catch {
        throw "Failed to decrypt data: $_"
    }
}

<#
.SYNOPSIS
    Saves credentials to the secure credential store.
.DESCRIPTION
    Saves the provided credentials to an encrypted file in the credential store.
.PARAMETER Target
    A name to identify the saved credentials.
.PARAMETER SharePath
    The network share path these credentials are for.
.PARAMETER Credential
    Optional PSCredential object containing the username and password to save.
    If not provided, the user will be prompted.
#>
function Save-ShareCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Target,
        
        [Parameter(Mandatory=$true)]
        [string]$SharePath,
        
        [System.Management.Automation.PSCredential]$Credential = $null
    )
    
    try {
        # Initialize credential store if it doesn't exist
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            Initialize-CredentialStore | Out-Null
        }
        
        # Create a credential object with the password as a secure string
        $credObject = [PSCustomObject]@{
            Target = $Target
            SharePath = $SharePath
            UserName = $Credential.UserName
            # Use cross-platform AES encryption instead of Windows DPAPI
            EncryptedPassword = ConvertFrom-SecureStringAES -SecureString $Credential.Password
            EncryptionMethod = 'AES256'
            Created = Get-Date
            Modified = Get-Date
        }
        
        # Save to file
        $credentialFile = Join-Path -Path $script:CredentialStorePath -ChildPath "$Target.cred"
        $credObject | Export-Clixml -Path $credentialFile -Force
        
        # Set file permissions
        $acl = Get-Acl -Path $credentialFile
        $acl.SetAccessRuleProtection($true, $false)
        
        # Add current user
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            'FullControl',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        
        # Add SYSTEM account
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $systemUser = $systemSid.Translate([System.Security.Principal.NTAccount])
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $systemUser,
            'FullControl',
            'Allow'
        )
        $acl.AddAccessRule($accessRule)
        
        Set-Acl -Path $credentialFile -AclObject $acl
        
        Write-Log "Credential saved successfully for target: $Target" -Level SUCCESS
        return $true
    }
    catch {
        $errorMsg = "Failed to save credential: $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Retrieves credentials from the secure credential store.
.DESCRIPTION
    Retrieves and decrypts credentials from the secure credential store.
.PARAMETER Target
    The name of the credential to retrieve.
#>
function Get-ShareCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Target
    )
    
    try {
        $credentialFile = Join-Path -Path $script:CredentialStorePath -ChildPath "$Target.cred"
        
        if (-not (Test-Path -Path $credentialFile)) {
            Write-Log "No credential found for target: $Target" -Level WARNING
            return $null
        }
        
        # Import the credential data
        $credentialData = Import-Clixml -Path $credentialFile
        
        # Handle different encryption methods for backwards compatibility
        if ($credentialData.PSObject.Properties['EncryptionMethod'] -and $credentialData.EncryptionMethod -eq 'AES256') {
            # Use AES decryption for new format
            $securePassword = ConvertTo-SecureStringAES -EncryptedString $credentialData.EncryptedPassword
        } else {
            # Try legacy DPAPI method (Windows only)
            try {
                $securePassword = ConvertTo-SecureString $credentialData.EncryptedPassword
            } catch {
                Write-Log "Failed to decrypt with DPAPI, attempting re-encryption with AES" -Level WARNING
                throw "Credential encrypted with Windows DPAPI. Please re-save the credential on this system."
            }
        }
        
        # Create and return a PSCredential object
        $credential = New-Object System.Management.Automation.PSCredential($credentialData.UserName, $securePassword)
        
        # Clear sensitive data from memory
        $securePassword = $null
        [System.GC]::Collect()
        
        Write-Log "Successfully retrieved credentials for target: $Target" -Level DEBUG
        return $credential
    }
    catch {
        $errorMsg = "Failed to retrieve credential: $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Tests access to a network share with the provided credentials.
.DESCRIPTION
    Attempts to access a network share using the provided credentials.
.PARAMETER SharePath
    The UNC path to the network share.
.PARAMETER Credential
    The PSCredential to use for authentication.
#>
function Test-ShareAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SharePath,
        
        [System.Management.Automation.PSCredential]$Credential
    )
    
    begin {
        $tempDrive = $null
        $result = $false
    }
    
    process {
        try {
            # Normalize the share path
            $SharePath = $SharePath.TrimEnd('\')
            
            # Create a temporary PSDrive to test access
            $driveLetter = [char[]](67..90) | 
                          Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } | 
                          Select-Object -First 1
            
            if (-not $driveLetter) {
                throw "No available drive letters found"
            }
            
            Write-Log "Testing access to share: $SharePath" -Level INFO
            
            $params = @{
                Name = $driveLetter
                PSProvider = 'FileSystem'
                Root = $SharePath
                Scope = 'Script'
                ErrorAction = 'Stop'
            }
            
            if ($Credential) {
                $params['Credential'] = $Credential
                Write-Log "Using credentials for user: $($Credential.UserName)" -Level DEBUG
            } else {
                Write-Log "Using current user context" -Level DEBUG
            }
            
            # Create the PSDrive
            $tempDrive = New-PSDrive @params
            
            # Test access by getting the root directory
            $items = Get-ChildItem -Path "${driveLetter}:\" -ErrorAction Stop
            
            Write-Log "Successfully accessed share: $SharePath" -Level SUCCESS
            Write-Log "Found $($items.Count) items in the root directory" -Level INFO
            
            if ($items.Count -gt 0) {
                $items | Select-Object -First 5 | Format-Table Name, Length, LastWriteTime
                if ($items.Count -gt 5) {
                    Write-Log "... and $($items.Count - 5) more items" -Level INFO
                }
            }
            
            $result = $true
        }
        catch {
            $errorMsg = "Failed to access share '$SharePath': $_"
            Write-Log $errorMsg -Level ERROR
            $result = $false
        }
        finally {
            # Clean up the temporary drive if it was created
            if ($tempDrive) {
                try {
                    Remove-PSDrive -Name $tempDrive.Name -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log "Failed to remove temporary drive: $_" -Level WARNING
                }
            }
        }
        
        return $result
    }
}

<#
.SYNOPSIS
    Lists available shares on a server.
.DESCRIPTION
    Lists all available shares on the specified server.
.PARAMETER Server
    The name or IP address of the server.
.PARAMETER Credential
    Optional credentials to use for authentication.
#>
function Get-NetworkShares {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Server,
        
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        Write-Log "Attempting to list shares on server: $Server" -Level INFO
        
        $params = @{
            Class = 'Win32_Share'
            ComputerName = $Server
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $params['Credential'] = $Credential
        }
        
        $shares = Get-WmiObject @params | 
                  Select-Object Name, Path, @{Name='Description'; Expression={$_.Description -replace '\s+', ' ' -replace '^\s+|\s+$',''}}
        
        if ($shares) {
            Write-Log "Available shares on $($Server):" -Level SUCCESS
            $shares | Format-Table -AutoSize
            return $true
        } else {
            Write-Log "No shares found on $Server" -Level WARNING
            return $false
        }
    }
    catch {
        $errorMsg = "Failed to list shares: $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Save-ShareCredential',
    'Get-ShareCredential',
    'Test-ShareAccess',
    'Get-NetworkShares',
    'Write-Log'
)
