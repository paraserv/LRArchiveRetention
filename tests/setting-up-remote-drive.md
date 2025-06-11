# tests/USING-NAS-SHARE.md

## Using the NAS Share for Test Data Generation and Automation

This guide outlines secure, best-practice steps for using the NAS share (`\\10.20.1.7\LRArchives`) with the `svc_lrarchive` account for test data generation and automation, **without mapping a network drive**. The share will remain accessible for all scripts and processes.

---

### 1. **Securely Store NAS Credentials**

#### **Option A: Windows Credential Manager (Recommended)**
Store the NAS credentials securely for seamless authentication.

```powershell
# Run this ONCE to store credentials in Windows Credential Manager
$cred = Get-Credential -UserName "svc_lrarchive" -Message "Enter NAS password"
cmdkey /add:10.20.1.7 /user:svc_lrarchive /pass:"$($cred.GetNetworkCredential().Password)"
```
- **Note:** The password argument must use `"$($cred.GetNetworkCredential().Password)"` for PowerShell to expand the variable correctly when calling a native command.
- This stores the credentials for all access to `\\10.20.1.7`.
- You will not be prompted for credentials when accessing the share from PowerShell or scripts.
- **Run this code in PowerShell, not CMD.**

#### **Option B: Encrypted Credential File**
Store credentials in an encrypted file (user/machine-specific).

```powershell
# Run this ONCE to save credentials to a file
$cred = Get-Credential -UserName "svc_lrarchive" -Message "Enter NAS password"
$cred | Export-Clixml -Path "$env:USERPROFILE\lrarchive-cred.xml"
```
- The file can only be decrypted by the user/machine that created it.

---

### 2. **Access the NAS Share in PowerShell Scripts**

#### **A. Using Windows Credential Manager (No Drive Mapping Needed)**

You can access the share directly in any script:

```powershell
# Example: List files in the NAS share
Get-ChildItem -Path "\\10.20.1.7\LRArchives"

# Example: Use as RootPath for GenerateTestData.ps1
pwsh ./tests/GenerateTestData.ps1 -RootPath "\\10.20.1.7\LRArchives\TestData" -FolderCount 5000 -MinFiles 20 -MaxFiles 500 -MaxFileSizeMB 10
```
- No need to specify credentials; Windows will use those stored in Credential Manager.

#### **B. Using an Encrypted Credential File**

For scripts that require explicit credentials (rare, but possible):

```powershell
# Import credentials
$cred = Import-Clixml -Path "$env:USERPROFILE\lrarchive-cred.xml"

# Example: Copy a file to the NAS share with credentials
Copy-Item -Path .\somefile.txt -Destination "\\10.20.1.7\LRArchives" -Credential $cred

# Example: Use with New-PSDrive (if absolutely needed, not recommended)
# New-PSDrive -Name "LR" -PSProvider FileSystem -Root "\\10.20.1.7\LRArchives" -Credential $cred -Persist
```
- **Note:** Most cmdlets (including file I/O) will use Credential Manager if available, so explicit credentials are rarely needed.

---

### 3. **Best Practices**

- **Do NOT map a network drive** unless absolutely necessary. Use UNC paths (`\\10.20.1.7\LRArchives`) directly in scripts.
- **Store credentials securely** (Credential Manager preferred).
- **Never hardcode passwords** in scripts or configuration files.
- **Test access** before running large jobs:

```powershell
Test-Path "\\10.20.1.7\LRArchives"
```
- **Ensure the share is available** for all scripts by using the same UNC path and credential method.

---

### 4. **Troubleshooting**

- If you receive access denied errors, re-enter credentials in Credential Manager:
  ```powershell
  cmdkey /delete:10.20.1.7
  # Then re-add as above
  ```
- If using an encrypted credential file, ensure you are running as the same user who created the file.
- For persistent issues, check NAS permissions and network connectivity.

---

### 5. **References**
- [Microsoft Docs: cmdkey](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/cmdkey)
- [PowerShell: Export-Clixml](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml)

---

**This document is maintained in `tests/USING-NAS-SHARE.md`.** 