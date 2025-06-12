# PowerShell Credential Management System Guide

## Overview
This document outlines the comprehensive PowerShell credential management system for secure network share access on Windows servers. The system provides enterprise-grade credential storage with AES-256 encryption and automatic validation.

## Files Overview
- `Save-Credential.ps1` - Credential saving script with secure stdin input (recommended) and legacy password parameters
- `modules/ShareCredentialHelper.psm1` - Core credential management module
- `ArchiveRetention.ps1` - Archive management script (uses stored credentials)

> **Security Note:** For Mac-to-Windows remote credential operations, see `tests/mac-to-windows-secure-credentials.md`

## Key Features

### 1. Secure Credential Storage
- **AES-256 Encryption**: Cross-platform encryption replacing Windows-only DPAPI
- **Secure Key Management**: Cryptographically secure key generation using `RandomNumberGenerator`
- **Cross-Platform Support**: Works on Windows, Linux, and macOS (PowerShell 5.1+)
- **Backward Compatibility**: Continues to support existing DPAPI-encrypted credentials

### 2. Credential Validation
- **Pre-Save Validation**: Tests credentials against the actual network share before storing
- **Authentication Detection**: Distinguishes between invalid credentials and network issues
- **Clean Error Messages**: Clear, actionable error messages without technical stack traces
- **Connection Conflict Handling**: Manages Windows networking connection limitations

### 3. Memory and File Security
- **Secure Memory Cleanup**: Automatic clearing of sensitive data from memory
- **Protected Storage**: Restrictive file permissions (Windows ACL + Unix 0600/0700)
- **Security Validation**: Directory security testing and validation
- **Hidden Storage**: Uses `.credential-store` on Unix systems for better security

### 4. Enhanced User Experience
- **Windows GUI Integration**: Uses native `Get-Credential` dialog for secure password entry
- **PowerShell 5.1 Compatibility**: Fixed compatibility issues with older PowerShell versions
- **Comprehensive Logging**: Security-aware logging with automatic sensitive data filtering
- **Clean Output**: Professional, color-coded console output

## Core Functions

### Credential Management
- **`Save-ShareCredential`**: Stores encrypted credentials with validation
- **`Get-ShareCredential`**: Retrieves and decrypts stored credentials
- **`Get-SavedCredentials`**: Lists all stored credentials with metadata
- **`Remove-ShareCredential`**: Safely removes credentials with confirmation

### Network Operations
- **`Test-ShareAccess`**: Tests network share access with timeout support
- **`Get-NetworkShares`**: Lists available shares on a server
- **Connection Testing**: Automatic connectivity verification

### Security Functions
- **`Clear-SensitiveMemory`**: Secure memory cleanup utility
- **`Test-SafeFileName`**: Input validation for safe file operations
- **`Set-SecurePermissions`**: Cross-platform file permission management

### Logging Functions
- **`Enable-ShareCredentialLogging`**: Enables optional logging to script directory
- **`Disable-ShareCredentialLogging`**: Disables logging (default state)

## Usage Examples

### Saving Credentials (Run locally on server)
```powershell
cd "C:\LogRhythm\Scripts\ArchiveV2"
.\Save-Credential.ps1 -CredentialTarget "ProductionNAS" -SharePath "\\server\share"   # GUI prompt on server
```

### Saving Credentials **Remotely** (Mac → Windows via stdin)
```bash
# Retrieve password from macOS Keychain
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)

# Pipe via SSH to Save-Credential.ps1 using -UseStdin
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\Save-Credential.ps1 -Target ''ProductionNAS'' -SharePath ''\\server\share'' -UseStdin -Quiet }"'

unset ARCHIVE_PASSWORD
```

### Using Stored Credentials in Scripts
```powershell
# Archive retention with stored credentials
.\ArchiveRetention.ps1 -CredentialTarget "ProductionNAS" -RetentionDays 180 -Execute
```

### Managing Credentials
```powershell
# List all stored credentials
Import-Module .\modules\ShareCredentialHelper.psm1
Get-SavedCredentials | Format-Table -AutoSize

# Remove old credentials
Remove-ShareCredential -Target "OldServer" -Confirm

# Enable logging (optional - disabled by default)
Enable-ShareCredentialLogging

# Disable logging
Disable-ShareCredentialLogging
```

## Security Architecture

### Enhanced Security Architecture
The credential system uses a **layered security approach** with machine binding:

**Primary Method - DPAPI (Windows)**:
- Uses Windows Data Protection API for true machine+user binding
- Credentials encrypted with DPAPI cannot be decrypted on different machines or by different users
- No key files stored - encryption tied to Windows security subsystem
- Highest security level for Windows environments

**Fallback Method - Machine-Bound AES**:
- Derives encryption keys from machine-specific hardware identifiers (CPU ID, motherboard serial, computer UUID)
- Uses PBKDF2 key derivation with 10,000 iterations for additional security
- Keys are regenerated from machine data each time (no key files stored)
- Credentials cannot be moved between machines due to hardware binding

### Encryption Details

**DPAPI Method (Primary)**:
- **Algorithm**: Windows Data Protection API with machine+user scope
- **Key Management**: Handled entirely by Windows security subsystem
- **Binding**: Tied to specific machine and user account
- **Portability**: Cannot be moved between machines or users

**Machine-Bound AES Method (Fallback)**:
- **Algorithm**: AES-256 with CBC mode and PKCS7 padding
- **Key Derivation**: PBKDF2 with 10,000 iterations from machine hardware identifiers
- **Key Sources**: Computer UUID, motherboard serial, CPU ID, user SID, computer name
- **Key Size**: 256-bit derived keys (no stored key files)
- **IV Generation**: Cryptographically secure random IV per encryption (16 bytes)
- **Data Format**: Base64-encoded string containing IV + encrypted data
- **Machine Binding**: Keys derived from hardware cannot be replicated on different machines

### Access Control
- **File Permissions**: Limited to current user and SYSTEM account only
- **Directory Security**: Inheritance disabled, explicit permissions only
- **Cross-Platform**: Windows ACL and Unix permissions automatically applied
- **Hardware Binding**: Encryption keys derived from machine hardware (not stored in files)
- **User Binding**: DPAPI ties credentials to specific Windows user accounts
- **Security Validation**: Regular security posture checking

### Audit and Compliance
- **Optional Logging**: Logging disabled by default, can be enabled when needed
- **Script Directory Logs**: Log files created in script directory (no separate folders)
- **Sensitive Data Protection**: Automatic redaction of passwords and keys in logs
- **Log Rotation**: Automatic rotation when logs exceed 10MB
- **Retention Policy**: 30-day log retention with configurable settings

## Error Handling and Troubleshooting

### Common Scenarios
- **Invalid Credentials**: "Authentication failed. Invalid username or password"
- **Network Issues**: "Network path not found or unreachable"
- **Connection Conflicts**: "Multiple connections to server" (resolved with `net use /delete`)
- **Permission Issues**: Clear guidance on file system permissions

### Troubleshooting Commands
```powershell
# Check network connectivity
Test-NetConnection -ComputerName "server" -Port 445

# Clear existing connections
net use \\server\share /delete

# Test credentials manually
$cred = Get-ShareCredential -Target "MyTarget"
Test-ShareAccess -SharePath $cred.SharePath -Credential $cred.Credential
```

## PowerShell Compatibility

### Version Support
- **PowerShell 5.1+**: Full compatibility with Windows PowerShell
- **PowerShell Core 6+**: Cross-platform support on Linux/macOS
- **Automatic Detection**: Platform-specific code paths

### Compatibility Fixes Applied
- **Removed**: `ErrorMessage` parameter from `ValidatePattern` (PS 6+ only)
- **Fixed**: `$IsWindows` variable detection for PS 5.1
- **Enhanced**: Platform detection with fallback methods
- **Improved**: Cross-platform file permission handling

## Deployment Considerations

### Requirements
- **PowerShell Version**: 5.1 or later
- **Network Access**: Connectivity to target shares for validation
- **File Permissions**: Write access to script directory for credential storage
- **Platform Support**: Windows, Linux, macOS

### Installation
1. Copy scripts to target directory
2. Ensure `modules` subdirectory contains `ShareCredentialHelper.psm1`
3. Run credential setup locally on server (via RDP/console for GUI dialog)
4. Use stored credentials in automated scripts

### Migration from Legacy
- **Automatic**: Existing DPAPI credentials continue to work
- **Gradual**: New credentials use AES-256 encryption
- **Seamless**: No disruption to existing automation
- **Upgrade Prompts**: Suggestions to re-save old credentials

### File Structure
```
C:\LogRhythm\Scripts\ArchiveV2\
├── Save-Credential.ps1
├── ArchiveRetention.ps1
└── modules\
    ├── ShareCredentialHelper.psm1
    ├── ShareCredentialHelper-2025-06.log  # Optional log file (when enabled)
    └── CredentialStore\
        ├── (no key files)           # Keys derived from machine hardware
        ├── QNAP.cred                # Encrypted credential files
        └── LRArchives_NAS.cred
```

### Bulk Migration Commands
If migrating multiple legacy DPAPI credentials:
```powershell
# List all credential files
Get-ChildItem .\modules\CredentialStore\*.cred | ForEach-Object {
    $targetName = $_.BaseName
    Write-Host "Found credential: $targetName"
}

# Migrate specific credentials (requires manual password entry)
$legacyTargets = @("OldServer1", "OldServer2", "OldServer3")
foreach ($target in $legacyTargets) {
    Write-Host "Migrating credential: $target" -ForegroundColor Yellow
    # Will prompt for re-save if old DPAPI format detected
    .\Save-Credential.ps1 -CredentialTarget $target -SharePath "\\server\share"
}
```

## Best Practices

### Security
- **Local Setup**: Always run credential setup locally on server for secure GUI
- **Regular Rotation**: Update credentials periodically (system warns after 365 days)
- **Minimal Permissions**: Use service accounts with least privilege
- **Audit Regularly**: Review stored credentials and access logs

### Operations
- **Testing**: Always test with `-Verbose` flag first
- **Validation**: Rely on automatic credential validation before storage
- **Documentation**: Document credential targets and their purposes
- **Backup**: Consider backup strategy for credential store
- **Logging**: Enable logging only when troubleshooting or auditing is needed

## Version History

### v2.0.0 (Current)
- **Added**: Credential validation before saving
- **Enhanced**: AES-256 encryption with cross-platform support
- **Improved**: Error handling and user experience
- **Fixed**: PowerShell 5.1 compatibility issues
- **Added**: Comprehensive logging and security features

### v1.x (Legacy)
- **Basic**: DPAPI-based credential storage (Windows only)
- **Limited**: No credential validation
- **Simple**: Basic error handling

## Security Improvements Over Previous Version

### Issues with Original Random Key Approach
The previous version had significant security weaknesses:
- **Portable Keys**: Random encryption keys could be copied between machines
- **File-Based Security**: Security relied entirely on file system permissions
- **Single Point of Failure**: One compromised key file exposed all credentials
- **No Machine Binding**: Credentials could work on any machine with the key file

### Enhanced Security Features (Current Version)

**True Machine Binding**:
- DPAPI provides Windows-native machine+user binding (cannot be bypassed)
- AES fallback derives keys from multiple hardware identifiers
- No stored key files that can be copied or compromised
- Credentials become unusable if moved to different hardware

**Defense in Depth**:
- Primary: DPAPI (Windows security subsystem)
- Secondary: Hardware-derived AES keys
- Tertiary: File system permissions
- Legacy: Support for old DPAPI credentials

**Key Derivation Sources**:
- Computer UUID (motherboard-specific)
- Motherboard serial number
- CPU processor ID
- Windows user SID
- Computer name (fallback)

This multi-factor approach ensures credentials are truly bound to the specific machine and user combination.

## Conclusion

This credential management system provides enterprise-grade security for PowerShell automation while maintaining ease of use and backward compatibility. The combination of strong encryption, credential validation, and comprehensive error handling makes it suitable for production environments requiring secure credential management. 