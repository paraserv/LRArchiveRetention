#requires -Version 5.1

<#
.SYNOPSIS
    Secure credential management module for network share access.

.DESCRIPTION
    This module provides functions for securely storing, retrieving, and managing credentials
    for network share access. It uses AES-256 encryption for cross-platform compatibility
    and implements security best practices for credential storage.

.NOTES
    Author: System Administrator
    Version: 2.0
    Requires: PowerShell 5.1 or later
    
    Security Features:
    - AES-256 encryption for credential storage
    - Secure memory handling and cleanup
    - Cross-platform compatibility
    - Restricted file permissions
    - Comprehensive logging with security-aware message filtering
#>

# Set strict mode for enhanced error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Variables and Configuration

# Module metadata
$script:ModuleName = 'ShareCredentialHelper'
$script:ModuleVersion = '2.0.0'

# Path configuration - using more secure approach
$script:CredentialStorePath = if ($PSVersionTable.PSVersion.Major -lt 6 -or (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue | Where-Object { $_.Value })) {
    Join-Path -Path $PSScriptRoot -ChildPath 'CredentialStore'
} else {
    Join-Path -Path $PSScriptRoot -ChildPath '.credential-store'
}

# Logging configuration - disabled by default
$script:LoggingEnabled = $false
$script:LogFile = $null
$script:MaxLogSizeMB = 10
$script:LogRetentionDays = 30

# Security constants
$script:AES_KEY_SIZE = 32  # 256-bit key
$script:AES_IV_SIZE = 16   # 128-bit IV
$script:MAX_CREDENTIAL_AGE_DAYS = 365

#endregion

#region Logging Control Functions

<#
.SYNOPSIS
    Enables logging for the credential management module.
#>
function Enable-ShareCredentialLogging {
    [CmdletBinding()]
    param()
    
    $script:LoggingEnabled = $true
    Write-Log "Logging enabled for ShareCredentialHelper module" -Level INFO
}

<#
.SYNOPSIS
    Disables logging for the credential management module.
#>
function Disable-ShareCredentialLogging {
    [CmdletBinding()]
    param()
    
    if ($script:LoggingEnabled) {
        Write-Log "Logging disabled for ShareCredentialHelper module" -Level INFO
    }
    $script:LoggingEnabled = $false
}

#endregion

#region Utility Functions

<#
.SYNOPSIS
    Determines if the current platform is Windows.
#>
function Test-IsWindows {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    # PowerShell 5.1 and earlier are Windows-only
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        return $true
    }
    
    # PowerShell 6+ has automatic variables
    $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    if ($isWindowsVar) {
        return $isWindowsVar.Value
    }
    
    # Fallback method for edge cases
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

<#
.SYNOPSIS
    Securely clears sensitive data from memory.
#>
function Clear-SensitiveMemory {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [ref[]]$Variables
    )
    
    if ($Variables) {
        foreach ($var in $Variables) {
            if ($var.Value) {
                $var.Value = $null
            }
        }
    }
    
    # Force garbage collection to clear sensitive data
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

<#
.SYNOPSIS
    Validates that a string contains only safe characters for file names.
#>
function Test-SafeFileName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )
    
    # Check for invalid characters and reserved names
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    
    return ($FileName -match '^[a-zA-Z0-9_.-]+$') -and 
           ($FileName -notmatch "[$([regex]::Escape($invalidChars))]") -and
           ($FileName.ToUpper() -notin $reservedNames) -and
           ($FileName.Length -le 100)
}

#endregion

#region Logging Functions

<#
.SYNOPSIS
    Writes a log message with enhanced security and formatting.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL', 'SUCCESS', 'SECURITY')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsoleOutput,
        
        [switch]$SensitiveData
    )
    
    # Only initialize logging if enabled and not already configured
    if ($script:LoggingEnabled) {
        if ([string]::IsNullOrEmpty($script:LogFile)) {
            Initialize-Logging
        }
    } else {
        # If logging is disabled, only show important messages to console
        if (-not $NoConsoleOutput) {
            # Only show ERROR, FATAL, WARNING, and SUCCESS when logging is disabled
            # Also respect VerbosePreference for other messages
            switch ($Level) {
                'ERROR'    { Write-Host $Message -ForegroundColor Red }
                'FATAL'    { Write-Host $Message -BackgroundColor Red -ForegroundColor White }
                'WARNING'  { Write-Host $Message -ForegroundColor Yellow }
                'SUCCESS'  { Write-Host $Message -ForegroundColor Green }
                'INFO'     { 
                    if ($VerbosePreference -eq 'Continue') { 
                        Write-Host $Message -ForegroundColor Cyan 
                    } 
                }
                'DEBUG'    { 
                    if ($VerbosePreference -eq 'Continue') { 
                        Write-Host $Message -ForegroundColor Gray 
                    } 
                }
                # Suppress SECURITY and other levels when logging is disabled
                default    { }
            }
        }
        return  # Exit early if logging is disabled
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    
    # Filter sensitive information from logs
    $logMessage = if ($SensitiveData) {
        "[$timestamp] [$Level] [REDACTED] Sensitive operation completed"
    } else {
        # Remove potential sensitive data patterns
        $filteredMessage = $Message -replace '(password[=:\s]+)[^\s]+', '$1***' -replace '(key[=:\s]+)[^\s]+', '$1***'
        "[$timestamp] [$Level] $filteredMessage"
    }
    
    # Console output with color coding (only show important messages unless verbose)
    if (-not $NoConsoleOutput) {
        switch ($Level) {
            'ERROR'    { Write-Host $logMessage -ForegroundColor Red }
            'FATAL'    { Write-Host $logMessage -BackgroundColor Red -ForegroundColor White }
            'WARNING'  { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS'  { Write-Host $logMessage -ForegroundColor Green }
            'INFO'     { 
                if ($VerbosePreference -eq 'Continue') { 
                    Write-Host $logMessage -ForegroundColor Cyan 
                } 
            }
            'SECURITY' { 
                if ($VerbosePreference -eq 'Continue') { 
                    Write-Host $logMessage -ForegroundColor Magenta 
                } 
            }
            'DEBUG'    { 
                if ($VerbosePreference -eq 'Continue' -or $DebugPreference -eq 'Continue') { 
                    Write-Host $logMessage -ForegroundColor Gray 
                } 
            }
            default    { Write-Host $logMessage }
        }
    }
    
    # File logging with rotation (only if logging is enabled)
    if ($script:LoggingEnabled -and -not [string]::IsNullOrEmpty($script:LogFile)) {
        try {
            # Check log file size and rotate if necessary
            if ((Test-Path -Path $script:LogFile) -and 
                ((Get-Item -Path $script:LogFile).Length / 1MB) -gt $script:MaxLogSizeMB) {
                Rotate-LogFile
            }
            
            # Log file will be created in script directory (no need to create separate directory)
            
            # Write to log file
            Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to log file ($script:LogFile): $_"
        }
    }
}

<#
.SYNOPSIS
    Initializes the logging system.
#>
function Initialize-Logging {
    [CmdletBinding()]
    param()
    
    try {
        # Log directly in the script directory (no separate Logs folder)
        $script:LogFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:ModuleName)-$(Get-Date -Format 'yyyy-MM').log"
        
        Write-Log "Logging initialized for module $script:ModuleName v$script:ModuleVersion" -Level INFO
        Write-Log "Log file: $script:LogFile" -Level DEBUG
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
    }
}

<#
.SYNOPSIS
    Rotates log files when they exceed the maximum size.
#>
function Rotate-LogFile {
    [CmdletBinding()]
    param()
    
    try {
        $logInfo = Get-Item -Path $script:LogFile
        $archiveFileName = "$($logInfo.BaseName)-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')$($logInfo.Extension)"
        $archivePath = Join-Path -Path $logInfo.DirectoryName -ChildPath $archiveFileName
        
        Move-Item -Path $script:LogFile -Destination $archivePath
        Write-Log "Log file rotated to: $archivePath" -Level INFO
        
        # Clean up old log files
        $cutoffDate = (Get-Date).AddDays(-$script:LogRetentionDays)
        Get-ChildItem -Path $logInfo.DirectoryName -Filter "*.log" | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate } |
            Remove-Item -Force
    }
    catch {
        Write-Warning "Failed to rotate log file: $_"
    }
}

#endregion

#region Security and Permissions Functions

<#
.SYNOPSIS
    Sets secure permissions on files and directories.
#>
function Set-SecurePermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [switch]$IsDirectory,
        
        [switch]$ReadOnly
    )
    
    try {
        if (Test-IsWindows) {
            # Windows ACL configuration
            $acl = Get-Acl -Path $Path
            $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance
            
            # Get current user and SYSTEM account
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $systemUser = $systemSid.Translate([System.Security.Principal.NTAccount])
            
            # Set permissions based on type
            $permission = if ($ReadOnly) { 'Read' } else { 'FullControl' }
            $inheritanceFlags = if ($IsDirectory) { 'ContainerInherit,ObjectInherit' } else { 'None' }
            
            # Add current user permissions
            $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser, $permission, $inheritanceFlags, 'None', 'Allow'
            )
            $acl.AddAccessRule($userRule)
            
            # Add SYSTEM permissions
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $systemUser, $permission, $inheritanceFlags, 'None', 'Allow'
            )
            $acl.AddAccessRule($systemRule)
            
            Set-Acl -Path $Path -AclObject $acl
            Write-Log "Set Windows ACL permissions on: $Path" -Level DEBUG
        }
        else {
            # Unix/Linux permissions
            $mode = if ($IsDirectory) {
                if ($ReadOnly) { '0500' } else { '0700' }
            } else {
                if ($ReadOnly) { '0400' } else { '0600' }
            }
            
            & chmod $mode $Path 2>$null
            Write-Log "Set Unix permissions ($mode) on: $Path" -Level DEBUG
        }
    }
    catch {
        Write-Log "Failed to set secure permissions on '$Path': $_" -Level WARNING
    }
}

<#
.SYNOPSIS
    Initializes the credential store with proper security settings.
#>
function Initialize-CredentialStore {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        Write-Log "Initializing credential store at: $script:CredentialStorePath" -Level DEBUG
        
        # Create credential store directory if it doesn't exist
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            $null = New-Item -Path $script:CredentialStorePath -ItemType Directory -Force
            Write-Log "Created credential store directory" -Level SUCCESS
        }
        
        # Set secure permissions
        Set-SecurePermissions -Path $script:CredentialStorePath -IsDirectory
        
        # Validate directory security
        if (-not (Test-DirectorySecurity -Path $script:CredentialStorePath)) {
            Write-Log "Credential store directory security validation failed" -Level WARNING
        }
        
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
    Tests the security of a directory.
#>
function Test-DirectorySecurity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path -Path $Path)) {
            return $false
        }
        
        if (Test-IsWindows) {
            $acl = Get-Acl -Path $Path
            $accessRules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
            
            # Check that only authorized users have access
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $systemUser = $systemSid.Translate([System.Security.Principal.NTAccount]).Value
            
            $authorizedUsers = @($currentUser, $systemUser, 'NT AUTHORITY\SYSTEM')
            
            foreach ($rule in $accessRules) {
                if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $authorizedUsers) {
                    Write-Log "Unauthorized access found for: $($rule.IdentityReference.Value)" -Level WARNING
                    return $false
                }
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to test directory security: $_" -Level WARNING
        return $false
    }
}

#endregion

#region Encryption Functions

<#
.SYNOPSIS
    Generates or retrieves the AES encryption key.
#>
function Get-EncryptionKey {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param()
    
    try {
        # Ensure credential store exists
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            Initialize-CredentialStore | Out-Null
        }
        
        # Load existing key if available
        if (Test-Path -Path $script:KeyPath) {
            Write-Log "Loading existing encryption key" -Level DEBUG
            $keyData = Get-Content -Path $script:KeyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            
            # Validate key structure
            if (-not $keyData.Key -or -not $keyData.Algorithm -or $keyData.Algorithm -ne 'AES256') {
                throw "Invalid key file format"
            }
            
            # Check key age and warn if old
            if ($keyData.Created) {
                $keyAge = (Get-Date) - [datetime]$keyData.Created
                if ($keyAge.TotalDays -gt $script:MAX_CREDENTIAL_AGE_DAYS) {
                    Write-Log "Encryption key is $([math]::Round($keyAge.TotalDays)) days old. Consider regenerating." -Level WARNING
                }
            }
            
            return [System.Convert]::FromBase64String($keyData.Key)
        }
        
        # Generate new encryption key
        Write-Log "Generating new AES-256 encryption key" -Level INFO
        $key = New-Object byte[] $script:AES_KEY_SIZE
        
        # Use cryptographically secure random number generator
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($key)
        }
        finally {
            $rng.Dispose()
        }
        
        # Save key with metadata
        $keyData = @{
            Key = [System.Convert]::ToBase64String($key)
            Algorithm = 'AES256'
            Created = Get-Date -Format 'o'
            KeySize = $script:AES_KEY_SIZE * 8
            ModuleVersion = $script:ModuleVersion
        }
        
        $keyData | ConvertTo-Json -Depth 3 | Set-Content -Path $script:KeyPath -Force -Encoding UTF8
        
        # Set restrictive permissions on key file
        Set-SecurePermissions -Path $script:KeyPath -ReadOnly
        
        Write-Log "Encryption key generated and secured" -Level SUCCESS -SensitiveData
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
    Encrypts a SecureString using AES-256 encryption.
#>
function ConvertFrom-SecureStringAES {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]$SecureString
    )
    
    $aes = $null
    $encryptor = $null
    $bstr = [IntPtr]::Zero
    $plainText = $null
    $plainBytes = $null
    
    try {
        # Get encryption key
        $key = Get-EncryptionKey
        
        # Convert SecureString to plain text temporarily
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        
        # Convert to bytes
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
        
        # Create AES encryption
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = $script:AES_KEY_SIZE * 8
        $aes.Key = $key
        $aes.GenerateIV()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # Encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        
        # Combine IV and encrypted data
        $result = New-Object byte[] ($aes.IV.Length + $encryptedBytes.Length)
        [System.Array]::Copy($aes.IV, 0, $result, 0, $aes.IV.Length)
        [System.Array]::Copy($encryptedBytes, 0, $result, $aes.IV.Length, $encryptedBytes.Length)
        
        # Convert to base64
        return [System.Convert]::ToBase64String($result)
    }
    catch {
        Write-Log "Encryption failed: $_" -Level ERROR
        throw "Failed to encrypt data: $_"
    }
    finally {
        # Secure cleanup
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        
        Clear-SensitiveMemory -Variables ([ref]$plainText, [ref]$plainBytes, [ref]$key)
        
        if ($encryptor) { $encryptor.Dispose() }
        if ($aes) { $aes.Dispose() }
    }
}

<#
.SYNOPSIS
    Decrypts an AES encrypted string to a SecureString.
#>
function ConvertTo-SecureStringAES {
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EncryptedString
    )
    
    $aes = $null
    $decryptor = $null
    $plainText = $null
    $plainBytes = $null
    
    try {
        # Get encryption key
        $key = Get-EncryptionKey
        
        # Convert from base64
        $encryptedData = [System.Convert]::FromBase64String($EncryptedString)
        
        # Validate data length
        if ($encryptedData.Length -lt $script:AES_IV_SIZE) {
            throw "Invalid encrypted data format"
        }
        
        # Extract IV and encrypted bytes
        $iv = New-Object byte[] $script:AES_IV_SIZE
        $encryptedBytes = New-Object byte[] ($encryptedData.Length - $script:AES_IV_SIZE)
        
        [System.Array]::Copy($encryptedData, 0, $iv, 0, $script:AES_IV_SIZE)
        [System.Array]::Copy($encryptedData, $script:AES_IV_SIZE, $encryptedBytes, 0, $encryptedBytes.Length)
        
        # Create AES decryption
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = $script:AES_KEY_SIZE * 8
        $aes.Key = $key
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # Decrypt the data
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
        
        return $secureString
    }
    catch {
        Write-Log "Decryption failed: $_" -Level ERROR
        throw "Failed to decrypt data: $_"
    }
    finally {
        # Secure cleanup
        Clear-SensitiveMemory -Variables ([ref]$plainText, [ref]$plainBytes, [ref]$key)
        
        if ($decryptor) { $decryptor.Dispose() }
        if ($aes) { $aes.Dispose() }
    }
}

#endregion

#region Enhanced Security Functions

<#
.SYNOPSIS
    Gets a machine-bound encryption key for enhanced security.
#>
function Get-MachineSpecificKey {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param()
    
    try {
        # Gather machine-specific data
        $machineData = @()
        
        # Computer UUID (most stable identifier)
        try {
            $uuid = (Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID
            if ($uuid) { $machineData += $uuid }
        } catch { }
        
        # Motherboard serial number
        try {
            $motherboard = (Get-WmiObject -Class Win32_BaseBoard -ErrorAction SilentlyContinue).SerialNumber
            if ($motherboard -and $motherboard -ne "To be filled by O.E.M.") { $machineData += $motherboard }
        } catch { }
        
        # CPU ID
        try {
            $cpu = (Get-WmiObject -Class Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).ProcessorId
            if ($cpu) { $machineData += $cpu }
        } catch { }
        
        # Current user SID
        try {
            $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            if ($userSid) { $machineData += $userSid }
        } catch { }
        
        # Computer name as fallback
        $machineData += $env:COMPUTERNAME
        
        # Combine all machine data
        $combinedData = $machineData -join "|"
        Write-Log "Machine binding data points: $($machineData.Count)" -Level DEBUG
        
        # Derive key using PBKDF2
        $salt = [System.Text.Encoding]::UTF8.GetBytes("ShareCredentialHelper.v2.MachineKey")
        $pbkdf2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($combinedData, $salt, 10000)
        
        try {
            return $pbkdf2.GetBytes($script:AES_KEY_SIZE)
        }
        finally {
            $pbkdf2.Dispose()
        }
    }
    catch {
        Write-Log "Failed to generate machine-specific key: $_" -Level ERROR
        throw "Unable to generate machine-bound encryption key: $_"
    }
}

<#
.SYNOPSIS
    Encrypts data using DPAPI with AES fallback.
#>
function ConvertFrom-SecureStringEnhanced {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]$SecureString
    )
    
    # Try DPAPI first (Windows-only, most secure)
    if (Test-IsWindows) {
        try {
            $dpapiData = ConvertFrom-SecureString -SecureString $SecureString -ErrorAction Stop
            Write-Log "Using DPAPI encryption (machine+user bound)" -Level DEBUG
            return @{
                Data = $dpapiData
                Method = "DPAPI"
                Version = "2.0"
                Created = Get-Date -Format 'o'
            }
        }
        catch {
            Write-Log "DPAPI encryption failed, falling back to AES: $_" -Level WARNING
        }
    }
    
    # Fallback to machine-bound AES
    $aes = $null
    $encryptor = $null
    $bstr = [IntPtr]::Zero
    $plainText = $null
    $plainBytes = $null
    
    try {
        # Get machine-specific key
        $key = Get-MachineSpecificKey
        
        # Convert SecureString to plain text temporarily
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        
        # Convert to bytes
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
        
        # Create AES encryption
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = $script:AES_KEY_SIZE * 8
        $aes.Key = $key
        $aes.GenerateIV()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # Encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        
        # Combine IV and encrypted data
        $result = New-Object byte[] ($aes.IV.Length + $encryptedBytes.Length)
        [System.Array]::Copy($aes.IV, 0, $result, 0, $aes.IV.Length)
        [System.Array]::Copy($encryptedBytes, 0, $result, $aes.IV.Length, $encryptedBytes.Length)
        
        Write-Log "Using machine-bound AES encryption" -Level DEBUG
        return @{
            Data = [System.Convert]::ToBase64String($result)
            Method = "AES-MachineKey"
            Version = "2.0"
            Created = Get-Date -Format 'o'
        }
    }
    catch {
        Write-Log "Enhanced encryption failed: $_" -Level ERROR
        throw "Failed to encrypt data: $_"
    }
    finally {
        # Secure cleanup
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        
        Clear-SensitiveMemory -Variables ([ref]$plainText, [ref]$plainBytes, [ref]$key)
        
        if ($encryptor) { $encryptor.Dispose() }
        if ($aes) { $aes.Dispose() }
    }
}

<#
.SYNOPSIS
    Decrypts data using DPAPI or machine-bound AES.
#>
function ConvertTo-SecureStringEnhanced {
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$EncryptedData
    )
    
    switch ($EncryptedData.Method) {
        "DPAPI" {
            try {
                Write-Log "Decrypting using DPAPI" -Level DEBUG
                return ConvertTo-SecureString -String $EncryptedData.Data -ErrorAction Stop
            }
            catch {
                Write-Log "DPAPI decryption failed: $_" -Level ERROR
                throw "Failed to decrypt DPAPI data. Credential may have been created by different user/machine: $_"
            }
        }
        
        "AES-MachineKey" {
            $aes = $null
            $decryptor = $null
            $plainText = $null
            $plainBytes = $null
            
            try {
                Write-Log "Decrypting using machine-bound AES" -Level DEBUG
                
                # Get machine-specific key
                $key = Get-MachineSpecificKey
                
                # Convert from base64
                $encryptedBytes = [System.Convert]::FromBase64String($EncryptedData.Data)
                
                # Validate data length
                if ($encryptedBytes.Length -lt $script:AES_IV_SIZE) {
                    throw "Invalid encrypted data format"
                }
                
                # Extract IV and encrypted bytes
                $iv = New-Object byte[] $script:AES_IV_SIZE
                $dataBytes = New-Object byte[] ($encryptedBytes.Length - $script:AES_IV_SIZE)
                
                [System.Array]::Copy($encryptedBytes, 0, $iv, 0, $script:AES_IV_SIZE)
                [System.Array]::Copy($encryptedBytes, $script:AES_IV_SIZE, $dataBytes, 0, $dataBytes.Length)
                
                # Create AES decryption
                $aes = [System.Security.Cryptography.Aes]::Create()
                $aes.KeySize = $script:AES_KEY_SIZE * 8
                $aes.Key = $key
                $aes.IV = $iv
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
                
                # Decrypt the data
                $decryptor = $aes.CreateDecryptor()
                $plainBytes = $decryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)
                
                # Convert to string
                $plainText = [System.Text.Encoding]::UTF8.GetString($plainBytes)
                
                # Convert to SecureString
                $secureString = New-Object System.Security.SecureString
                foreach ($char in $plainText.ToCharArray()) {
                    $secureString.AppendChar($char)
                }
                $secureString.MakeReadOnly()
                
                return $secureString
            }
            catch {
                Write-Log "Machine-bound AES decryption failed: $_" -Level ERROR
                throw "Failed to decrypt machine-bound data. Credential may have been created on different machine: $_"
            }
            finally {
                Clear-SensitiveMemory -Variables ([ref]$plainText, [ref]$plainBytes, [ref]$key)
                
                if ($decryptor) { $decryptor.Dispose() }
                if ($aes) { $aes.Dispose() }
            }
        }
        
        # Legacy support for old AES format
        { $_ -eq "AES256" -or $_ -eq $null } {
            Write-Log "Attempting legacy AES decryption" -Level WARNING
            try {
                return ConvertTo-SecureStringAES -EncryptedString $EncryptedData.Data
            }
            catch {
                Write-Log "Legacy AES decryption failed: $_" -Level ERROR
                throw "Failed to decrypt legacy credential. Consider re-saving: $_"
            }
        }
        
        default {
            throw "Unknown encryption method: $($EncryptedData.Method)"
        }
    }
}

#endregion

#region Credential Management Functions

<#
.SYNOPSIS
    Saves credentials to the secure credential store.
#>
function Save-ShareCredential {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SharePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        # Validate inputs
        if (-not (Test-SafeFileName -FileName $Target)) {
            throw "Invalid target name. Use only alphanumeric characters, hyphens, underscores, and periods."
        }
        
        # Normalize SharePath
        $SharePath = $SharePath.TrimEnd('\')
        
        Write-Log "Saving credentials for target: $Target" -Level DEBUG
        Write-Log "Share path: $SharePath" -Level DEBUG
        
        # Initialize credential store
        Initialize-CredentialStore | Out-Null
        
        # Check if credential already exists and confirm overwrite
        $credentialFile = Join-Path -Path $script:CredentialStorePath -ChildPath "$Target.cred"
        if ((Test-Path -Path $credentialFile) -and $PSCmdlet.ShouldProcess($Target, "Overwrite existing credential")) {
            Write-Log "Overwriting existing credential for target: $Target" -Level WARNING
        }
        
        # Encrypt password using enhanced method
        $encryptedPassword = ConvertFrom-SecureStringEnhanced -SecureString $Credential.Password
        
        # Create credential object with enhanced metadata
        $credObject = [PSCustomObject]@{
            Target = $Target
            SharePath = $SharePath
            UserName = $Credential.UserName
            EncryptedPassword = $encryptedPassword
            EncryptionMethod = $encryptedPassword.Method
            Created = Get-Date -Format 'o'
            Modified = Get-Date -Format 'o'
            ModuleVersion = $script:ModuleVersion
            ComputerName = $env:COMPUTERNAME
            UserDomain = $env:USERDOMAIN
        }
        
        # Save to file with enhanced error handling
        if ($PSCmdlet.ShouldProcess($credentialFile, "Save encrypted credential file")) {
            $credObject | Export-Clixml -Path $credentialFile -Force -ErrorAction Stop
            
            # Set restrictive permissions
            Set-SecurePermissions -Path $credentialFile
            
            Write-Log "Credential saved successfully for target: $Target" -Level SUCCESS -SensitiveData
            return $true
        }
        
        return $false
    }
    catch {
        $errorMsg = "Failed to save credential for target '$Target': $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Retrieves credentials from the secure credential store.
#>
function Get-ShareCredential {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target
    )
    
    try {
        # Validate target name
        if (-not (Test-SafeFileName -FileName $Target)) {
            throw "Invalid target name format"
        }
        
        $credentialFile = Join-Path -Path $script:CredentialStorePath -ChildPath "$Target.cred"
        
        if (-not (Test-Path -Path $credentialFile)) {
            Write-Log "No credential found for target: $Target" -Level WARNING
            return $null
        }
        
        Write-Log "Retrieving credential for target: $Target" -Level DEBUG
        
        # Import and validate credential data
        $credentialData = Import-Clixml -Path $credentialFile -ErrorAction Stop
        
        # Validate credential structure
        $requiredProperties = @('Target', 'SharePath', 'UserName', 'EncryptedPassword')
        foreach ($prop in $requiredProperties) {
            if (-not $credentialData.PSObject.Properties[$prop]) {
                throw "Invalid credential file format: missing property '$prop'"
            }
        }
        
        # Check credential age
        if ($credentialData.Created) {
            $credAge = (Get-Date) - [datetime]$credentialData.Created
            if ($credAge.TotalDays -gt $script:MAX_CREDENTIAL_AGE_DAYS) {
                Write-Log "Credential for '$Target' is $([math]::Round($credAge.TotalDays)) days old. Consider updating." -Level WARNING
            }
        }
        
        # Decrypt password based on encryption method
        $securePassword = if ($credentialData.EncryptionMethod -in @('DPAPI', 'AES-MachineKey')) {
            ConvertTo-SecureStringEnhanced -EncryptedData $credentialData.EncryptedPassword
        } elseif ($credentialData.EncryptionMethod -eq 'AES256') {
            ConvertTo-SecureStringAES -EncryptedString $credentialData.EncryptedPassword
        } else {
            # Legacy DPAPI fallback (Windows only)
            if (-not (Test-IsWindows)) {
                throw "Legacy DPAPI credentials are not supported on this platform. Please re-save the credential."
            }
            try {
                $credentialData.EncryptedPassword | ConvertTo-SecureString -ErrorAction Stop
            } catch {
                throw "Failed to decrypt legacy credential. Please re-save the credential on this system."
            }
        }
        
        # Create PSCredential object
        $psCredential = New-Object System.Management.Automation.PSCredential($credentialData.UserName, $securePassword)
        
        # Return enhanced result object
        $result = [PSCustomObject]@{
            Credential = $psCredential
            SharePath = $credentialData.SharePath
            Target = $credentialData.Target
            Created = $credentialData.Created
            Modified = $credentialData.Modified
            Age = if ($credentialData.Created) { (Get-Date) - [datetime]$credentialData.Created } else { $null }
        }
        
        Write-Log "Successfully retrieved credential for target: $Target" -Level SUCCESS -SensitiveData
        
        # Clear sensitive data
        Clear-SensitiveMemory -Variables ([ref]$securePassword)
        
        return $result
    }
    catch {
        $errorMsg = "Failed to retrieve credential for target '$Target': $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Lists all available credentials in the store.
#>
function Get-SavedCredentials {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()
    
    try {
        if (-not (Test-Path -Path $script:CredentialStorePath)) {
            Write-Log "Credential store does not exist" -Level WARNING
            return @()
        }
        
        $credentialFiles = Get-ChildItem -Path $script:CredentialStorePath -Filter "*.cred" -ErrorAction SilentlyContinue
        
        if (-not $credentialFiles) {
            Write-Log "No saved credentials found" -Level INFO
            return @()
        }
        
        $results = foreach ($file in $credentialFiles) {
            try {
                $credData = Import-Clixml -Path $file.FullName -ErrorAction Stop
                [PSCustomObject]@{
                    Target = $credData.Target
                    SharePath = $credData.SharePath
                    UserName = $credData.UserName
                    Created = $credData.Created
                    Modified = $credData.Modified
                    Age = if ($credData.Created) { (Get-Date) - [datetime]$credData.Created } else { $null }
                    EncryptionMethod = $credData.EncryptionMethod
                }
            }
            catch {
                Write-Log "Failed to read credential file '$($file.Name)': $_" -Level WARNING
            }
        }
        
        # Handle PowerShell strict mode - use @() to ensure array
        $resultArray = @($results)
        Write-Log "Found $($resultArray.Count) saved credentials" -Level INFO
        return $resultArray
    }
    catch {
        Write-Log "Failed to list saved credentials: $_" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Removes a credential from the secure store.
#>
function Remove-ShareCredential {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target
    )
    
    try {
        # Validate target name
        if (-not (Test-SafeFileName -FileName $Target)) {
            throw "Invalid target name format"
        }
        
        $credentialFile = Join-Path -Path $script:CredentialStorePath -ChildPath "$Target.cred"
        
        if (-not (Test-Path -Path $credentialFile)) {
            Write-Log "No credential found for target: $Target" -Level WARNING
            return $false
        }
        
        if ($PSCmdlet.ShouldProcess($Target, "Remove stored credential")) {
            Remove-Item -Path $credentialFile -Force -ErrorAction Stop
            Write-Log "Successfully removed credential for target: $Target" -Level SUCCESS
            return $true
        }
        
        return $false
    }
    catch {
        $errorMsg = "Failed to remove credential for target '$Target': $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

#endregion

#region Network Share Functions

<#
.SYNOPSIS
    Tests access to a network share with enhanced security and error handling.
#>
function Test-ShareAccess {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SharePath,
        
        [System.Management.Automation.PSCredential]$Credential,
        
        [int]$TimeoutSeconds = 30
    )
    
    $tempDrive = $null
    
    try {
        # Normalize and validate share path
        $SharePath = $SharePath.TrimEnd('\')
        if (-not ($SharePath -match '^\\\\[^\\]+\\[^\\]+')) {
            throw "Invalid UNC path format. Expected format: \\server\share"
        }
        
        Write-Log "Testing access to share: $SharePath" -Level DEBUG
        
        # Find available drive letter
        $driveLetter = [char[]](67..90) | 
            Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } | 
            Select-Object -First 1
        
        if (-not $driveLetter) {
            throw "No available drive letters found for testing"
        }
        
        # Prepare PSDrive parameters
        $params = @{
            Name = $driveLetter
            PSProvider = 'FileSystem'
            Root = $SharePath
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $params['Credential'] = $Credential
            Write-Log "Using provided credentials for authentication" -Level DEBUG
        }
        
        # Create PSDrive with timeout
        $job = Start-Job -ScriptBlock {
            param($Params)
            New-PSDrive @Params | Out-Null
            Get-ChildItem -Path "$($Params.Name):\" -ErrorAction Stop | Select-Object -First 10
        } -ArgumentList $params
        
        $result = $job | Wait-Job -Timeout $TimeoutSeconds
        
        if ($result.State -eq 'Completed') {
            $jobErrors = Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable jobErrorVar
            
            if ($jobErrorVar) {
                # Check for specific error types
                $errorMessage = $jobErrorVar[0].ToString()
                if ($errorMessage -match "Access is denied|credentials|authentication|logon failure") {
                    throw "Authentication failed. Invalid username or password for share '$SharePath'"
                }
                elseif ($errorMessage -match "network path|not found|unreachable") {
                    throw "Network path '$SharePath' not found or unreachable"
                }
                else {
                    throw "Failed to access share: $errorMessage"
                }
            }
            
            $items = $jobErrors
            $tempDrive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
            
            Write-Log "Successfully accessed share: $SharePath" -Level SUCCESS
            Write-Log "Found $($items.Count) items in the root directory" -Level DEBUG
            
            if ($items.Count -gt 0) {
                Write-Log "Sample items:" -Level DEBUG
                $itemsOutput = $items | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String
                Write-Log -Message $itemsOutput.Trim() -Level DEBUG
            }
            
            return $true
        }
        elseif ($result.State -eq 'Failed') {
            $jobError = Receive-Job -Job $job -ErrorAction SilentlyContinue
            $errorDetails = $job.ChildJobs[0].JobStateInfo.Reason.Message
            
            if ($errorDetails -match "Access is denied|credentials|authentication|logon failure") {
                throw "Authentication failed. Invalid username or password for share '$SharePath'"
            }
            elseif ($errorDetails -match "network path|not found|unreachable") {
                throw "Network path '$SharePath' not found or unreachable"
            }
            else {
                throw "Failed to access share: $errorDetails"
            }
        }
        else {
            throw "Share access test timed out after $TimeoutSeconds seconds"
        }
    }
    catch {
        $errorMsg = "Failed to access share '$SharePath': $_"
        Write-Log $errorMsg -Level ERROR
        return $false
    }
    finally {
        # Cleanup
        if ($job) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        
        if ($tempDrive) {
            try {
                Remove-PSDrive -Name $tempDrive.Name -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up temporary drive: $($tempDrive.Name)" -Level DEBUG
            }
            catch {
                Write-Log "Failed to remove temporary drive: $_" -Level WARNING
            }
        }
    }
}

<#
.SYNOPSIS
    Lists available shares on a server with enhanced error handling.
#>
function Get-NetworkShares {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,
        
        [System.Management.Automation.PSCredential]$Credential,
        
        [int]$TimeoutSeconds = 30
    )
    
    try {
        # Validate server name/IP
        $Server = $Server.Trim()
        if ([string]::IsNullOrWhiteSpace($Server)) {
            throw "Server name cannot be empty"
        }
        
        Write-Log "Attempting to list shares on server: $Server" -Level INFO
        
        # Test basic connectivity first
        if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Server '$Server' is not responding to ping" -Level WARNING
        }
        
        # Prepare WMI/CIM parameters
        $params = @{
            ClassName = 'Win32_Share'
            ComputerName = $Server
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $params['Credential'] = $Credential
        }
        
        # Try CIM first (preferred), fall back to WMI
        $shares = $null
        try {
            if ($Credential) {
                $cimSession = New-CimSession -ComputerName $Server -Credential $Credential -ErrorAction Stop
                $shares = Get-CimInstance -CimSession $cimSession -ClassName 'Win32_Share' -ErrorAction Stop
                Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
            } else {
                $shares = Get-CimInstance -ComputerName $Server -ClassName 'Win32_Share' -ErrorAction Stop
            }
        }
        catch {
            Write-Log "CIM query failed, falling back to WMI: $_" -Level DEBUG
            $shares = Get-WmiObject @params
        }
        
        if ($shares) {
            $shareList = $shares | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Path = $_.Path
                    Description = ($_.Description -replace '\s+', ' ').Trim()
                    Type = switch ($_.Type) {
                        0 { 'Disk Drive' }
                        1 { 'Print Queue' }
                        2 { 'Device' }
                        3 { 'IPC' }
                        2147483648 { 'Disk Drive Admin' }
                        2147483649 { 'Print Queue Admin' }
                        2147483650 { 'Device Admin' }
                        2147483651 { 'IPC Admin' }
                        default { "Unknown ($($_))" }
                    }
                    MaxUsers = $_.MaximumAllowed
                }
            } | Sort-Object Name
            
            Write-Log "Found $($shareList.Count) shares on server: $Server" -Level SUCCESS
            
            # Display results
            $shareList | Format-Table -AutoSize | Out-String | Write-Log -Level INFO
            
            return $shareList
        }
        else {
            Write-Log "No shares found on server: $Server" -Level WARNING
            return @()
        }
    }
    catch {
        $errorMsg = "Failed to list shares on server '$Server': $_"
        Write-Log $errorMsg -Level ERROR
        throw $errorMsg
    }
}

#endregion

#region Module Cleanup

<#
.SYNOPSIS
    Cleans up module resources and performs security cleanup.
#>
function Clear-ModuleState {
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Performing module cleanup" -Level DEBUG
        
        # Clear sensitive variables
        $script:LogFile = $null
        
        # Force garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        
        Write-Log "Module cleanup completed" -Level DEBUG
    }
    catch {
        Write-Log "Failed to cleanup module state: $_" -Level WARNING
    }
}

# Register cleanup on module removal
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = { Clear-ModuleState }

#endregion

#region Export Module Members

# Export public functions
Export-ModuleMember -Function @(
    'Save-ShareCredential',
    'Get-ShareCredential',
    'Get-SavedCredentials',
    'Remove-ShareCredential',
    'Test-ShareAccess',
    'Get-NetworkShares',
    'Enable-ShareCredentialLogging',
    'Disable-ShareCredentialLogging',
    'Write-Log'
)

# Export aliases for backward compatibility
Set-Alias -Name 'Get-StoredCredentials' -Value 'Get-SavedCredentials'
Export-ModuleMember -Alias 'Get-StoredCredentials'

#endregion
