# Cross-Platform Credential Storage Implementation

## Overview

The ShareCredentialHelper module has been updated to use cross-platform compatible AES-256 encryption instead of Windows Data Protection API (DPAPI). This allows the credential storage to work on Windows Server Core, Linux, and macOS systems where DPAPI is not available.

## Key Changes

### 1. Encryption Method
- **Previous**: Used Windows DPAPI via `ConvertFrom-SecureString` and `ConvertTo-SecureString`
- **Current**: Uses AES-256 encryption with machine-specific keys

### 2. Key Management
- A 256-bit AES encryption key is generated per machine
- The key is stored in a protected `.key` file within the credential store
- Proper file permissions are set based on the operating system

### 3. Backward Compatibility
- The module can still read credentials encrypted with the old DPAPI method
- When encountering DPAPI-encrypted credentials, it will prompt to re-save them
- New saves always use the AES-256 method

## Implementation Details

### New Functions

1. **Get-EncryptionKey**
   - Generates or retrieves the machine-specific AES key
   - Creates the key file with restrictive permissions
   - Returns the key as a byte array

2. **ConvertFrom-SecureStringAES**
   - Encrypts a SecureString using AES-256
   - Generates a random IV for each encryption
   - Returns a base64-encoded string containing IV + encrypted data

3. **ConvertTo-SecureStringAES**
   - Decrypts an AES-encrypted string back to SecureString
   - Extracts the IV and encrypted data
   - Securely handles the decryption process

### Security Features

1. **Key Protection**
   - Windows: ACL restricted to current user and SYSTEM
   - Unix/Linux: File permissions set to 600 (owner read/write only)

2. **Memory Management**
   - Sensitive data is cleared from memory after use
   - Garbage collection is explicitly called
   - BSTR pointers are zeroed

3. **Encryption Details**
   - Algorithm: AES-256 (256-bit key)
   - Mode: CBC with random IV per encryption
   - IV is prepended to encrypted data

## Usage

### Saving Credentials
```powershell
# Import the module
Import-Module ./tests/ShareCredentialHelper.psm1

# Save credentials for a network share
Save-ShareCredential -Target "NAS_Archive" -SharePath "\\10.20.1.7\LRArchives"
```

### Testing Access
```powershell
# Test access with saved credentials
./tests/Test-NetworkShareAccess.ps1 -Action TestAccess -Target NAS_Archive
```

### Re-saving Old Credentials
If you have credentials encrypted with the old DPAPI method:
```powershell
# The module will detect old format and prompt for re-encryption
$cred = Get-ShareCredential -Target "OldCredential"
# This will throw an error suggesting to re-save

# Re-save with new encryption
Save-ShareCredential -Target "OldCredential" -SharePath "\\server\share"
```

## File Structure

```
tests/
├── ShareCredentialHelper.psm1     # Main module with encryption functions
├── Test-NetworkShareAccess.ps1    # Test script for credential management
└── CredentialStore/               # Credential storage directory
    ├── .key                       # Machine-specific encryption key
    ├── NAS_Archive.cred          # Example encrypted credential file
    └── Logs/                      # Log files directory
```

## Troubleshooting

### Permission Issues
- Ensure the script is run with appropriate permissions to create/modify files
- On Windows, may need to run as Administrator for initial setup
- On Unix/Linux, ensure the user has write permissions to the script directory

### Migration from DPAPI
1. List all saved credentials: `Get-ChildItem ./tests/CredentialStore/*.cred`
2. For each credential, attempt to load and re-save:
   ```powershell
   $targets = @("Target1", "Target2", "Target3")
   foreach ($target in $targets) {
       Write-Host "Re-saving credential: $target"
       Save-ShareCredential -Target $target -SharePath "\\server\share"
   }
   ```

### Verification
To verify the encryption is working correctly:
```powershell
# Save a test credential
Save-ShareCredential -Target "TestCred" -SharePath "\\test\share"

# Retrieve and test
$cred = Get-ShareCredential -Target "TestCred"
Write-Host "Username: $($cred.UserName)"
```

## Benefits

1. **Cross-Platform**: Works on Windows, Linux, and macOS
2. **No External Dependencies**: Uses built-in .NET cryptography classes
3. **Secure**: AES-256 encryption with proper key management
4. **Backward Compatible**: Can read old DPAPI credentials (Windows only)
5. **Service Account Friendly**: Works in non-interactive environments
