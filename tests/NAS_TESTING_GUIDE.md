# NAS Testing Guide

**Date:** July 18, 2025
**Environment:** Windows Server VM (windev01.lab.paraserv.com)
**Target:** QNAP NAS at 10.20.1.7/LRArchives

## 🎯 Overview

This guide documents the complete process for testing ArchiveRetention.ps1 against network storage (NAS), including setup challenges, solutions, and security considerations.

## 🔧 Technical Setup Requirements

### 1. Module Directory Structure
**Issue:** ArchiveRetention.ps1 expects ShareCredentialHelper.psm1 in a `modules` subdirectory, but it was deployed to the root script directory.

**Solution:**
```powershell
# Create modules directory
mkdir C:\LR\Scripts\LRArchiveRetention\modules

# Move ShareCredentialHelper to correct location
move C:\LR\Scripts\LRArchiveRetention\ShareCredentialHelper.psm1 C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1
```

### 2. Parameter Set Usage
**Issue:** ArchiveRetention.ps1 has two parameter sets:
- `LocalPath`: Requires `-ArchivePath` and `-RetentionDays`
- `NetworkShare`: Requires `-CredentialTarget` and `-RetentionDays` (no `-ArchivePath`)

**Incorrect Usage:**
```powershell
# This fails - mixing parameter sets
.\ArchiveRetention.ps1 -ArchivePath "\\server\share" -CredentialTarget "NAS_CREDS" -RetentionDays 1000
```

**Correct Usage Options:**
```powershell
# Option 1: NetworkShare parameter set (requires stored credential)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 1000

# Option 2: LocalPath parameter set with mapped drive
.\ArchiveRetention.ps1 -ArchivePath "MappedDrive:\" -RetentionDays 1000
```

## 🛡️ Security Considerations

### Credential Storage Issues
**Problem:** The ShareCredentialHelper credential storage system has session isolation issues. Credentials stored in one PowerShell session may not be accessible to another session.

**Workaround:** Use temporary drive mapping approach instead of the built-in credential system.

### Secure Testing Approach
**Working Solution:**
```powershell
# Set up credentials (secure variables in script)
$username = "svc_lrarchive"
$password = "YOUR_PASSWORD_HERE"  # pragma: allowlist secret
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username, $securePassword)

# Map network drive with credentials
New-PSDrive -Name "LRArchives" -PSProvider FileSystem -Root "\\10.20.1.7\LRArchives" -Credential $cred

# Run retention script against mapped drive
.\ArchiveRetention.ps1 -ArchivePath "LRArchives:\" -RetentionDays 1000

# Clean up
Remove-PSDrive -Name "LRArchives" -Force
```

## 📊 Test Results

### NAS Environment Analysis
- **Total Files:** 20,574 files (100.01 GB)
- **LCA Files:** 20,572 files (excellent for testing)
- **Date Range:** 2022-06-29 to 2025-07-18 (3+ years)
- **Directory Structure:** 149 folders

### Performance Results
- **Files Processed:** 3,283 files (15.97 GB) eligible for 1000-day retention
- **Processing Rate:** 5,773 files/second (excellent network performance)
- **Total Time:** 5.06 seconds
- **Network Connectivity:** Successful with proper credential handling

## 🚨 Security Lessons Learned

### 1. Password Exposure Risks
**Issue:** During testing, passwords were embedded in temporary PowerShell scripts and may appear in:
- Temp files (`/tmp/nas_retention_*.ps1`)
- Command history (bash/PowerShell)
- Process lists (if using command-line parameters)
- Log files (if not properly filtered)

**Prevention:**
- Use secure credential retrieval (macOS Keychain, Windows Credential Manager)
- Avoid hardcoding passwords in scripts
- Use `-UseStdin` parameter for Save-Credential.ps1
- Clean up temporary files after testing

### 2. Recommended Secure Testing Pattern
```bash
# On macOS - retrieve from keychain
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)

# Pipe to remote script without command-line exposure
echo "$ARCHIVE_PASSWORD" | ssh windev01 'pwsh -c "
    \$password = \$input | ConvertTo-SecureString -AsPlainText -Force
    \$cred = New-Object PSCredential(\"svc_lrarchive\", \$password)
    # Use credential object...
"'

# Clean up
unset ARCHIVE_PASSWORD
```

## 🔄 Reusable Testing Script Template

```powershell
# NAS_Testing_Template.ps1
# Change to script directory
Set-Location "C:\LR\Scripts\LRArchiveRetention"

# Retrieve credentials securely (replace with your method)
$username = "svc_lrarchive"
$password = Read-Host "Enter NAS password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($username, $password)

try {
    # Map network drive
    New-PSDrive -Name "TestDrive" -PSProvider FileSystem -Root "\\10.20.1.7\LRArchives" -Credential $cred -ErrorAction Stop

    Write-Host "Network drive mapped successfully."

    # Run retention script
    .\ArchiveRetention.ps1 -ArchivePath "TestDrive:\" -RetentionDays 1000

} catch {
    Write-Error "Failed to map network drive: $($_.Exception.Message)"
} finally {
    # Always clean up
    Remove-PSDrive -Name "TestDrive" -Force -ErrorAction SilentlyContinue
}
```

## 🔐 Advanced Security Considerations

### Mac-to-Windows Secure Credential Operations

#### macOS Keychain Setup (RECOMMENDED)
**One-Time Setup:**
1. Open Keychain Access (Applications → Utilities → Keychain Access)
2. Select "login" keychain in the left sidebar
3. Click "Create a new Keychain item" button (pencil icon)
4. Fill in the New Password Item dialog:
   - **Keychain Item Name:** `logrhythm_archive`
   - **Account Name:** `svc_lrarchive`
   - **Password:** Enter your secure password
5. Click "Add" to save

**Usage:**
```bash
# Retrieve password from keychain
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)

# Use in SSH command with updated paths
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.20 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LR\Scripts\LRArchiveRetention''; .\Save-Credential.ps1 -Target ''SecureTarget'' -SharePath ''\\10.20.1.7\LRArchives'' -UseStdin -Quiet }"'

# Clear from memory
unset ARCHIVE_PASSWORD
```

#### Security Benefits
- ✅ **No password in command line:** Password passed via stdin
- ✅ **No Windows process exposure:** Remote PowerShell process shows no password parameters
- ✅ **Keychain Protection:** System-level encryption and access control
- ✅ **Automatic Cleanup:** Credentials cleared from memory after use

#### Process Verification
```powershell
# Verify no password exposure on Windows
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*Password*" }
# Should return no results when using -UseStdin parameter
```

## 🛠️ Troubleshooting Guide

### Common Issues

1. **"Parameter set cannot be resolved"**
   - **Cause:** Mixing LocalPath and NetworkShare parameter sets
   - **Solution:** Use only one parameter set at a time

2. **"ShareCredentialHelper module not found"**
   - **Cause:** Module not in expected `modules` subdirectory
   - **Solution:** Move module to `C:\LR\Scripts\LRArchiveRetention\modules\`

3. **"No credential found for target"**
   - **Cause:** Credential storage session isolation
   - **Solution:** Use drive mapping approach instead

4. **"Access denied" to network path**
   - **Cause:** No credentials provided or invalid credentials
   - **Solution:** Verify credentials and use drive mapping

## 🏆 Production Deployment Notes

For production use:
1. Use the built-in ShareCredentialHelper system with proper credential setup
2. Run Save-Credential.ps1 to store credentials securely
3. Use the NetworkShare parameter set: `.\ArchiveRetention.ps1 -CredentialTarget "TARGET_NAME" -RetentionDays N`
4. Avoid the drive mapping workaround (testing only)

## 📋 Testing Checklist

- [ ] ShareCredentialHelper module in correct location
- [ ] Network connectivity verified (Test-NetConnection)
- [ ] Credentials tested manually first
- [ ] Dry-run mode tested before execution
- [ ] Temporary files cleaned up after testing
- [ ] Command history cleared if needed
- [ ] Performance metrics documented

## 🧪 Testing Procedures

### Test Data Generation (Prerequisite)

Before running core tests, generate realistic test data using `GenerateTestData.ps1`:

```bash
# Copy script to server
scp -i ~/.ssh/id_rsa_windows tests/GenerateTestData.ps1 administrator@10.20.1.20:'C:/LR/Scripts/LRArchiveRetention/tests/'

# Generate test data
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.20 \
  "pwsh -NoProfile -ExecutionPolicy Bypass -Command \"& { cd 'C:/LR/Scripts/LRArchiveRetention/tests'; ./GenerateTestData.ps1 -RootPath 'D:/LogRhythmArchives/Test' }\""
```

**Note:** Update paths to match current infrastructure (10.20.1.20, C:/LR/Scripts/LRArchiveRetention/)

### Automated Test Execution

Use the `RunArchiveRetentionTests.sh` script from your Mac/Linux machine:

```bash
cd tests
bash RunArchiveRetentionTests.sh
```

### Validating Results

Use SSH to view logs:
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.20 \
  'powershell -Command "Get-Content -Tail 20 ''C:\LR\Scripts\LRArchiveRetention\script_logs\ArchiveRetention.log''"'
```

### Quick Workflow Checklist
1. **Generate test data** using `GenerateTestData.ps1`
2. **Run tests** using `RunArchiveRetentionTests.sh`
3. **Validate logs** and interpret results using SSH commands
4. **Document results** in test tracking

### Troubleshooting
- **SSH connection fails:** Check SSH key path and permissions
- **Not enough disk space:** Ensure at least 20% free disk space
- **PowerShell errors:** Verify PowerShell 7+ is installed
- **Permission denied:** Ensure user has write/delete permissions
- **Test data missing:** Always run `GenerateTestData.ps1` before tests

---

*This guide ensures future testing sessions can efficiently test NAS functionality without re-discovering these setup requirements and security considerations.*
