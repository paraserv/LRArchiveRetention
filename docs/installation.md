# Installation Guide

This guide covers all installation and setup procedures for the LogRhythm Archive Retention Manager.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Setup](#quick-setup)
- [Network Credentials Setup](#network-credentials-setup)
- [WinRM Setup for Remote Operations](#winrm-setup-for-remote-operations)
- [Scheduled Task Configuration](#scheduled-task-configuration)
- [Verification](#verification)

## Prerequisites

### System Requirements
- **Operating System**: Windows Server 2016+ or Windows 10+
- **PowerShell**: Version 5.1+ (PowerShell 7+ recommended for test scripts)
- **Permissions**: Administrative access to archive directories
- **Network**: Access to target archive locations (local or network shares)

### Service Account Requirements (for automation)
- "Log on as a batch job" rights
- Read/Write/Delete permissions on archive directories
- Network share access permissions (if using UNC paths)

## Quick Setup

### 1. Clone Repository

```bash
# Clone to your preferred directory
git clone <repository-url>
cd LRArchiveRetention
```

### 2. Deploy to Production Location

For production deployments, copy scripts to a secure location:

```powershell
# Create production directory
New-Item -ItemType Directory -Path "C:\LogRhythm\Scripts\LRArchiveRetention" -Force

# Copy scripts (from deployment server)
Copy-Item -Path ".\*" -Destination "C:\LogRhythm\Scripts\LRArchiveRetention\" -Recurse
```

### 3. Verify Installation

```powershell
# Change to script directory
cd C:\LogRhythm\Scripts\LRArchiveRetention

# Verify script execution
.\ArchiveRetention.ps1 -Version

# Test with local path (dry-run mode)
.\ArchiveRetention.ps1 -ArchivePath "C:\temp" -RetentionDays 90
```

## Network Credentials Setup

For network share access, credentials must be saved securely using the credential management system.

### Interactive Setup (Recommended)

```powershell
# Save credentials with GUI prompt
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share"

# For specific username
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share" -UserName "domain\username"
```

### Automated Setup (for CI/CD)

```powershell
# Via stdin (password not shown in command history)
echo "password" | .\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share" -UserName "domain\username" -UseStdin -Quiet
```

### Verify Saved Credentials

```powershell
# Import module
Import-Module .\modules\ShareCredentialHelper.psm1

# List all saved credentials
Get-SavedCredentials | Format-Table -AutoSize

# Test specific credential
Test-SavedCredential -Target "NAS_PROD"
```

## WinRM Setup for Remote Operations

For managing the retention script from Mac/Linux systems, configure WinRM access.

### 1. Configure WinRM on Windows Server

```powershell
# Run on Windows server as Administrator
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Kerberos -Value true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value false

# For HTTPS (recommended)
New-SelfSignedCertificate -DnsName "servername.domain.com" -CertStoreLocation Cert:\LocalMachine\My
$thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "servername"}).Thumbprint
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $thumbprint -Force

# Firewall rules
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow
```

### 2. Setup Python Environment on Mac/Linux

```bash
# Create virtual environment
python3 -m venv winrm_env
source winrm_env/bin/activate

# Install dependencies
pip install pywinrm requests-kerberos

# For the helper tool
pip install -r requirements.txt
```

### 3. Store Windows Credentials Securely (macOS)

```bash
# Store service account password in keychain
security add-internet-password -s "servername.domain.com" -a "username@DOMAIN.COM" -w

# Retrieve for use in scripts
WINDOWS_PASSWORD=$(security find-internet-password -s "servername.domain.com" -a "username@DOMAIN.COM" -w)
```

### 4. Test WinRM Connection

```bash
# Using winrm_helper.py
source winrm_env/bin/activate
python3 tools/winrm_helper.py test

# Manual test
python3 -c "
import winrm
session = winrm.Session('https://servername:5986/wsman',
                       auth=('username@DOMAIN.COM', 'password'),
                       transport='kerberos',
                       server_cert_validation='ignore')
result = session.run_ps('hostname')
print(result.std_out.decode())
"
```

## Scheduled Task Configuration

### Using the Helper Script

```powershell
# Create scheduled task with service account
.\CreateScheduledTask.ps1 `
    -TaskName "LogRhythm Archive Cleanup" `
    -TaskDescription "Weekly cleanup of LogRhythm archives older than 15 months" `
    -ScriptPath "C:\LogRhythm\Scripts\LRArchiveRetention\ArchiveRetention.ps1" `
    -CredentialTarget "NAS_PROD" `
    -RetentionDays 456 `
    -ServiceAccount "DOMAIN\svc_logrhythm" `
    -Execute
```

### Manual Task Creation

1. Open Task Scheduler (`taskschd.msc`)
2. Create new task with these settings:
   - **General**: Run whether user is logged on or not
   - **Trigger**: Weekly, Sunday, 2:00 AM
   - **Action**: Start a program
     - Program: `powershell.exe`
     - Arguments: `-ExecutionPolicy Bypass -File "C:\LogRhythm\Scripts\LRArchiveRetention\ArchiveRetention.ps1" -CredentialTarget "NAS_PROD" -RetentionDays 456 -QuietMode -Execute`
   - **Settings**: 
     - Allow task to run on demand
     - Stop task if runs longer than 12 hours
     - If task fails, restart every 30 minutes

## Verification

### 1. Test Script Execution

```powershell
# Dry-run test with local path
.\ArchiveRetention.ps1 -ArchivePath "C:\temp" -RetentionDays 90

# Test with network credentials (dry-run)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 456
```

### 2. Check Logs

```powershell
# View recent log entries
Get-Content .\script_logs\ArchiveRetention.log -Tail 50

# Check for errors
Select-String -Path .\script_logs\ArchiveRetention.log -Pattern "ERROR" -Context 2
```

### 3. Verify Scheduled Task

```powershell
# Check task status
Get-ScheduledTask -TaskName "LogRhythm Archive Cleanup" | Select-Object State, LastRunTime, NextRunTime

# View task history
Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational | 
    Where-Object {$_.Message -like "*LogRhythm Archive Cleanup*"} | 
    Select-Object TimeCreated, Message -First 10
```

## Troubleshooting

### Common Issues

1. **Access Denied**
   - Verify service account permissions
   - Check credential target name matches exactly
   - Ensure network share is accessible

2. **Script Not Found**
   - Verify script path in scheduled task
   - Check file permissions

3. **Credential Errors**
   - Re-save credentials using `Save-Credential.ps1`
   - Test with `Test-SavedCredential`

4. **WinRM Connection Failed**
   - Verify WinRM service is running
   - Check firewall rules
   - Ensure Kerberos authentication is enabled

### Getting Help

1. Enable verbose logging: Add `-Verbose` parameter
2. Check documentation in `/docs` directory
3. Review CLAUDE.md for detailed examples
4. Examine test scripts for usage patterns