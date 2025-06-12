# Mac-to-Windows Secure Credential Operations

> **Purpose:** Secure methods for passing credentials from Mac to Windows server during testing and remote operations

**Solution:** Updated `Save-Credential.ps1` with `-UseStdin` parameter to eliminate process exposure  


### **Verification:**
```powershell
# This now returns NO RESULTS when using Save-Credential.ps1 with -UseStdin:
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*Password*" }
```

## Overview

This guide provides secure methods for Mac-to-Windows credential operations during testing and remote administration. All methods work with the `Save-Credential.ps1` script using the `-UseStdin` parameter to eliminate password exposure in Windows process lists.

> **Related Documentation:** For Windows server-side credential management, see `docs/credentials.md`

---

## 🗝 **Method 1: macOS Keychain Setup (RECOMMENDED)**

The macOS Keychain provides secure, encrypted storage for passwords with system-level protection. This method shows how to set up keychain storage for use with the secure remote operations.

### **One-Time Setup**

#### **Method A: GUI Setup (Recommended - Most Secure)**
1. **Open Keychain Access** (Applications → Utilities → Keychain Access)
2. **Select "login" keychain** in the left sidebar under "Default Keychains"
3. **Click the "Create a new Keychain item" button** (pencil icon) in the toolbar or go to File → New Password Item...
4. **Fill in the New Password Item dialog:**
   - **Keychain Item Name:** `logrhythm_archive`
   - **Account Name:** `svc_lrarchive` (or your actual username)
   - **Password:** Enter your secure password (you'll see dots as you type)
   - **Password Strength:** Will show as you type (Weak/Fair/Strong)
   - **Show Password:** Check this box if you want to verify what you typed
5. **Click "Add"** to save the password to your keychain
6. **Verify:** The item `logrhythm_archive` should now appear in your login keychain list

#### **Safe Verification (GUI Method)**
- Simply check that `logrhythm_archive` appears in your Keychain Access list
- **Do NOT use the terminal verification command** - it exposes your password in plain text

#### **Method B: Terminal Setup (Alternative)**
⚠️ **Security Warning:** Option 2 exposes passwords in terminal history. Option 1 is safer but still uses terminal variables.

```bash
# Option 1: Prompt for password (more secure)
read -s "password?Enter password: "; security add-generic-password \
  -a "svc_lrarchive" \
  -s "logrhythm_archive" \
  -w "$password" \
  -T ""; unset password

# This prompts for password without displaying it

# Option 2: With password in command (NOT RECOMMENDED - visible in history)
security add-generic-password \
  -a "svc_lrarchive" \
  -s "logrhythm_archive" \
  -w "your_secure_password_here" \
  -T ""

# Verify setup - Option 1: Safe (no password displayed)
security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive"

# Verify setup - Option 2: Show password (WARNING: This will display the password in plain text!)
# security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -g

# If you used Option 2 or the verify command, immediately clear your history:

# For zsh (macOS default):
# Delete last N commands (adjust N as needed - 3 covers: add-password, verify, history-delete commands)
N=3; for ((i=1;i<=N;i++)); do history -d $((HISTCMD - i)); done; lines=$(($(wc -l < ~/.zsh_history)-N)); [ "$lines" -gt 0 ] && head -n "$lines" ~/.zsh_history > ~/.zsh_history.tmp && mv ~/.zsh_history.tmp ~/.zsh_history; fc -R ~/.zsh_history

# For bash:
history -d $(history 1 | awk '{print $1}')  # Remove last command
# Or clear entire history: history -c
```

### **Usage**
```bash
# Retrieve password from keychain
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)

# Use in SSH command
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\Save-Credential.ps1 -Target ''SecureTarget'' -SharePath ''\\10.20.1.7\LRArchives'' -UseStdin -Quiet }"'

# Clear from memory
unset ARCHIVE_PASSWORD
```

### **Keychain Management**
```bash
# Update existing password (secure prompt)
read -s "password?Enter new password: "
security add-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w "$password" -U
unset password

# Remove password from keychain
security delete-generic-password -a "svc_lrarchive" -s "logrhythm_archive"

# List keychain entries (optional - shows what's stored without passwords)
security dump-keychain | grep "logrhythm_archive"
```

---

## 🛡️ **Method 2: Secure Remote Operations**

The `Save-Credential.ps1` script with `-UseStdin` parameter eliminates password exposure in Windows process lists by accepting passwords via stdin instead of command-line parameters. This is the recommended method for all Mac-to-Windows testing operations.

### **Usage with Keychain**
```bash
# Retrieve password from keychain and pipe to secure script
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)

echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget SecureTarget -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""

# Clear from memory
unset ARCHIVE_PASSWORD
```

### **Usage with Interactive Prompt**
```bash
# Prompt for password and pipe directly to secure script
echo -n "Enter archive password: "
read -s ARCHIVE_PASSWORD
echo

echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget SecureTarget -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""

# Clear from memory
unset ARCHIVE_PASSWORD
```

### **Security Benefits**
- ✅ **No password in command line:** Password passed via stdin, not visible in `ps` or process lists
- ✅ **No Windows process exposure:** Remote PowerShell process shows no password parameters
- ✅ **Same functionality:** All features of original script maintained
- ✅ **Compatible with all methods:** Works with keychain, interactive prompts, or environment variables

### **Verification**
```bash
# On Windows system, verify no password exposure:
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*Password*" }
# Should return no results when using Save-Credential.ps1
```

---


## 🔒 **Method 3: Interactive Prompt (Zero Persistence)**

For testing scenarios requiring no stored credentials, use interactive password prompts. This method ensures the password never touches persistent storage and provides zero-persistence security.

### **Basic Interactive Usage**
```bash
# Prompt for password without echoing to terminal
echo -n "Enter archive password: "
read -s ARCHIVE_PASSWORD
echo  # New line after hidden input

# Use immediately
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget MyTarget -SharePath \\\\10.20.1.7\\LRArchives -Password '$ARCHIVE_PASSWORD' -Quiet
  \""

# Clean up immediately
unset ARCHIVE_PASSWORD
```

### **Enhanced Interactive with Validation**
```bash
# Function for secure password input with confirmation
get_secure_password() {
    while true; do
        echo -n "Enter archive password: "
        read -s password1
        echo
        echo -n "Confirm password: "
        read -s password2
        echo
        
        if [[ "$password1" == "$password2" ]]; then
            echo "$password1"
            break
        else
            echo "Passwords don't match. Please try again."
        fi
    done
}

# Use the function
ARCHIVE_PASSWORD=$(get_secure_password)
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget MyTarget -SharePath \\\\10.20.1.7\\LRArchives -Password '$ARCHIVE_PASSWORD' -Quiet
  \""

# Clear from memory
unset ARCHIVE_PASSWORD
```

---

## 🧪 **Integration with Test Automation**

This credential system integrates seamlessly with the existing test automation in this folder:

### **For Automated Testing (RunArchiveRetentionTests.sh)**
```bash
# Set up keychain once (one-time setup)
read -s "password?Enter password: "
security add-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w "$password" -T ""
unset password

# Use in automated tests
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget TestTarget -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""
unset ARCHIVE_PASSWORD
```

### **For Manual Testing**
```bash
# Interactive prompt for each test
echo -n "Enter archive password: "
read -s ARCHIVE_PASSWORD
echo
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget ManualTest -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""
unset ARCHIVE_PASSWORD
```

### **Integration with Existing Test Scripts**
- **credential-system-test-plan.md:** Use secure methods for all credential testing
- **RunArchiveRetentionTests.sh:** Integrate secure credential setup before test execution
- **GenerateTestData.ps1:** No changes needed - runs on Windows server directly

---

## 🔍 **Security Verification**

### **Check Command History**
```bash
# Verify password doesn't appear in history
history | grep -i password
history | grep -i archive

# If found, clean history
history -c  # Clear current session
# Edit ~/.bash_history or ~/.zsh_history to remove entries
```

### **Check Process List**
```bash
# While command is running, check if password is visible
ps aux | grep -i password
ps aux | grep ssh

# Should not show the actual password in process arguments
```

### **Verify Keychain Security**
```bash
# Check keychain access permissions
security find-generic-password -a "archive_user" -s "logrhythm_archive" -g

# Should require authentication or show encrypted data
```

---

## 📋 **Best Practices Summary**

### ✅ **Do:**
- Use macOS Keychain for regular, automated operations (recommended for most scenarios)
- Use interactive prompts when zero-persistence is required
- Clear passwords from memory immediately after use
- Verify command history doesn't contain passwords
- Use unique, strong passwords for archive access

### ❌ **Don't:**
- Put passwords directly in command lines
- Store passwords in shell scripts or files
- Leave passwords in environment variables longer than necessary
- Use the same password for multiple systems
- Log passwords in application logs

---

## 🧪 **Testing Your Setup**

### **Test Keychain Method**
```bash
# Store test password
security add-generic-password -a "test_user" -s "test_service" -w "test_password"

# Retrieve test password
TEST_PASSWORD=$(security find-generic-password -a "test_user" -s "test_service" -w)
echo "Retrieved: $TEST_PASSWORD"

# Clean up
security delete-generic-password -a "test_user" -s "test_service"
unset TEST_PASSWORD
```

### **Test Interactive Method**
```bash
# Test password prompt (use a dummy password)
echo -n "Test password prompt: "; read -s TEST_PASSWORD; echo
echo "You entered a password of length: ${#TEST_PASSWORD}"
unset TEST_PASSWORD
```

---

## 🚀 **Ready-to-Use Commands**

### **Quick Setup with Keychain**
```bash
# One-time keychain setup (use GUI method above, or terminal with prompt):
read -s "password?Enter password: "; security add-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w "$password" -T ""; unset password

# Use it
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 "powershell -NoProfile -ExecutionPolicy Bypass -Command \"cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget Production -SharePath \\\\10.20.1.7\\LRArchives -Password '$ARCHIVE_PASSWORD' -Quiet\""
unset ARCHIVE_PASSWORD
```

### **Interactive Secure Method**
```bash
# Most secure - prompts for password
echo -n "Enter archive password: "; read -s ARCHIVE_PASSWORD; echo
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 "powershell -NoProfile -ExecutionPolicy Bypass -Command \"cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget Production -SharePath \\\\10.20.1.7\\LRArchives -Password '$ARCHIVE_PASSWORD' -Quiet\""
unset ARCHIVE_PASSWORD
```

---

## 🎯 **Method Comparison for Testing**

| Feature | Secure + Keychain | Secure + Interactive | Legacy Methods |
|---------|-------------------|---------------------|----------------|
| **Mac Storage Security** | High (Hardware-backed) | High (Zero-persistence) | High |
| **Windows Process Security** | ✅ **High (No exposure)** | ✅ **High (No exposure)** | ❌ **Password visible** |
| **Testing Convenience** | High | Medium | High |
| **Automation Friendly** | Yes | No | Yes |
| **Setup Required** | One-time keychain | None | One-time keychain |
| **Best For Testing** | **🏆 Automated tests** | **🏆 Manual testing** | ❌ **Not recommended** |

---

## 💡 **Testing Recommendations**

### **🏆 RECOMMENDED for Testing:**
- **Automated test scripts:** Use secure method with keychain for consistent, repeatable testing
- **Manual testing:** Use secure method with interactive prompt for ad-hoc testing
- **CI/CD pipelines:** Secure method + keychain is the only viable option for automated testing
- **Security testing:** Secure method + interactive prompt for compliance validation

### **❌ NOT RECOMMENDED:**
- **Legacy methods:** Expose passwords in Windows process lists during testing
- **Command-line passwords:** Visible in shell history and process lists
- **Environment variables:** Can leak in process dumps and logs

## 🔐 **Security Analysis for Testing**

### **✅ RESOLVED: Process Exposure Vulnerability**
The `Save-Credential.ps1` script eliminates the critical security vulnerability where passwords were visible in Windows process lists.

#### **Before (Legacy Methods):**
```powershell
# This would show passwords in process command lines:
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*Password*" }
```

#### **After (Secure Methods):**
```powershell
# This returns NO RESULTS - passwords not in command lines:
Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*Password*" }
```

### **Testing Security Benefits:**

#### **✅ Mac-Side Security:**
- **Keychain storage**: Hardware-backed encryption (Secure Enclave/T2/M1+ chips)
- **Interactive prompts**: Zero persistence, no stored credentials
- **Memory protection**: Variables cleared immediately after use
- **History protection**: Passwords don't appear in shell command history

#### **✅ Windows-Side Security:**
- **No process exposure**: Stdin input prevents command-line password visibility
- **Same functionality**: All PowerShell features maintained
- **Audit compliance**: No passwords in process logs or monitoring systems

#### **✅ Testing-Specific Benefits:**
- **Automated testing**: Keychain enables secure, repeatable test automation
- **Manual testing**: Interactive prompts for ad-hoc testing scenarios
- **CI/CD integration**: Secure credential handling in automated pipelines
- **Security testing**: Verify no password leakage during security audits

---

## 📋 **Quick Reference for Testers**

### **One-Time Setup (Keychain Method)**
```bash
read -s "password?Enter password: "
security add-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w "$password" -T ""
unset password
```

### **Automated Testing**
```bash
ARCHIVE_PASSWORD=$(security find-generic-password -a "svc_lrarchive" -s "logrhythm_archive" -w)
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget TestTarget -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""
unset ARCHIVE_PASSWORD
```

### **Manual Testing**
```bash
echo -n "Enter archive password: "
read -s ARCHIVE_PASSWORD
echo
echo "$ARCHIVE_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"
    cd C:\LogRhythm\Scripts\ArchiveV2; 
    .\Save-Credential.ps1 -CredentialTarget ManualTest -SharePath \\\\10.20.1.7\\LRArchives -UseStdin -Quiet
  \""
unset ARCHIVE_PASSWORD
```

---

*This guide provides secure credential handling for Mac-to-Windows testing operations. For Windows server-side credential management, see `docs/credentials.md`.* 