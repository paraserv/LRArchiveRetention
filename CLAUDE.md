# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a PowerShell-based LogRhythm Archive Retention Manager for automated cleanup of LogRhythm Inactive Archive files (.lca). It provides enterprise-grade file retention management with secure credential handling, comprehensive logging, and safety features.

## Key Commands

### Development & Testing
```powershell
# Run main script in dry-run mode (safe, shows what would be deleted)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90

# Execute actual deletions (production use)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90 -Execute

# Use saved network credentials
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 180 -Execute

# Run with verbose output for debugging
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90 -Verbose
```

### Credential Management
```powershell
# Save network credentials (interactive GUI prompt)
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share"

# Save credentials via stdin (for automation)
echo "password" | .\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share" -UseStdin -Quiet

# List saved credentials
Import-Module .\modules\ShareCredentialHelper.psm1
Get-SavedCredentials | Format-Table -AutoSize
```

### Testing
```bash
# Run automated test suite (from Mac/Linux)
cd tests && bash RunArchiveRetentionTests.sh

# Generate test data on Windows server
.\tests\GenerateTestData.ps1 -RootPath "D:\LogRhythmArchives\Test"
```

### Remote Management

**PREFERRED: Use WinRM for all PowerShell operations** (session persistence, clean syntax, enterprise authentication)

```bash
# Activate WinRM environment
source winrm_env/bin/activate

# WinRM for PowerShell operations (PREFERRED)
# First, get password from keychain
WINDOWS_PASSWORD=$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)

python3 -c "
import winrm, os
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', os.environ['WINDOWS_PASSWORD']),
                       transport='kerberos',
                       server_cert_validation='ignore')

# Example: Run PowerShell commands with clean syntax
result = session.run_ps('Get-Host | Select-Object Name, Version')
print(result.std_out.decode().strip())

# Example: Session persistence - variables persist between commands
session.run_ps('$testPath = \"D:\\LogRhythmArchives\"')
result = session.run_ps('Test-Path $testPath')
print(f'Path exists: {result.std_out.decode().strip()}')
"

# SSH for simple operations only (when WinRM not available)
ssh windev01 "powershell -Command 'Get-Host'"
```

## Authentication & Connectivity

### Windows Server Access (windev01)

**SSH Access** (Preferred for interactive work):
```bash
# Uses ~/.ssh/config entry for windev01
ssh windev01
# Connects to: Administrator@10.20.1.20 with key: ~/.ssh/windows_server
```

**WinRM Access** (Preferred for PowerShell automation):

First, store the Windows service account credentials in your Mac's keychain:
```bash
# Store Windows service account password in keychain (run once)
security add-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w
```

Then use it securely in your WinRM sessions:
```bash
# Get Windows service account password from keychain
WINDOWS_PASSWORD=$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)
```

```python
import winrm
import os

# Get password from environment (set via keychain retrieval above)
windows_password = os.environ.get('WINDOWS_PASSWORD')
if not windows_password:
    raise ValueError("WINDOWS_PASSWORD environment variable not set. Run keychain retrieval first.")

session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', windows_password),
                       transport='kerberos',
                       server_cert_validation='ignore')
```

### NAS Access (10.20.1.7)

**Credential Retrieval from macOS Keychain**:
```bash
# Get NAS username (always 'sanghanas')
security find-internet-password -s "10.20.1.7" -a "sanghanas"

# Get NAS password securely
NAS_PASSWORD=$(security find-internet-password -s "10.20.1.7" -a "sanghanas" -w)
```

**Setting up NAS_CREDS on Windows Server**:

*Option 1: Interactive (Secure)*
```powershell
# On Windows server, save the credential (interactive password prompt - hidden input)
cd C:\LR\Scripts\LRArchiveRetention
.\Save-Credential.ps1 -Target "NAS_CREDS" -SharePath "\\10.20.1.7\LRArchives" -UserName "sanghanas"
# You'll be prompted to enter the password securely (input will be hidden)
```

*Option 2: Via WinRM from Mac (Fully Automated)*
```bash
# From Mac: Retrieve password and execute via WinRM (no password exposure)
WINDOWS_PASSWORD=$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)
NAS_PASSWORD=$(security find-internet-password -s "10.20.1.7" -a "sanghanas" -w)

python3 -c "
import winrm, os
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', os.environ['WINDOWS_PASSWORD']),
                       transport='kerberos', server_cert_validation='ignore')

# Change to script directory
session.run_ps('cd C:\\LR\\Scripts\\LRArchiveRetention')

# Save credential via secure stdin (password never exposed in command line)
cmd = f'echo \"{os.environ[\"NAS_PASSWORD\"]}\" | .\\Save-Credential.ps1 -Target \"NAS_CREDS\" -SharePath \"\\\\10.20.1.7\\LRArchives\" -UserName \"sanghanas\" -UseStdin -Quiet'
result = session.run_ps(cmd)
print('Credential saved successfully' if result.status_code == 0 else f'Error: {result.std_err.decode()}')
"
```

**Verification**:
```powershell
# Test the saved credential
Import-Module .\modules\ShareCredentialHelper.psm1
Get-SavedCredentials | Where-Object { $_.Target -eq "NAS_CREDS" }
```

### Key Connection Details
- **Windows Server**: windev01.lab.paraserv.com (10.20.1.20)
- **NAS Server**: 10.20.1.7 (QNAP)
- **NAS Share**: \\10.20.1.7\LRArchives
- **NAS Username**: sanghanas (stored in macOS Keychain)
- **Script Location**: C:\LR\Scripts\LRArchiveRetention\

## Architecture

### Core Components

**Main Script** (`ArchiveRetention.ps1`):
- Primary file retention engine with safety features
- Supports both local paths and network shares with credentials
- Implements minimum retention enforcement (90+ days hardcoded)
- Provides dry-run mode by default for safety

**Credential Management** (`Save-Credential.ps1` + `modules/ShareCredentialHelper.psm1`):
- Secure credential storage using AES-256 encryption (cross-platform) or Windows DPAPI
- Machine-bound encryption keys derived from hardware identifiers
- Credential validation before storage
- Cross-platform support (Windows/Linux/macOS)

**Scheduled Task Helper** (`CreateScheduledTask.ps1`):
- Automated Windows scheduled task creation
- Service account configuration support
- Production-ready task settings

### Security Model

**Credential Security**:
- Primary: Windows DPAPI (machine+user binding)
- Fallback: AES-256 with hardware-derived keys (CPU ID, motherboard serial, etc.)
- No portable key files - credentials bound to specific machines
- Automatic credential validation and connection testing

**File Safety**:
- Dry-run mode by default (requires explicit `-Execute` flag)
- Minimum retention enforcement (90+ days hardcoded)
- Comprehensive audit logging of all deletions
- Retry logic with configurable delays

### Parameter Sets

The main script uses PowerShell parameter sets:
- `LocalPath`: Uses `-ArchivePath` for local/UNC paths
- `NetworkShare`: Uses `-CredentialTarget` for saved credentials

### Logging Structure

**Script Logs** (`script_logs/`):
- `ArchiveRetention.log` - Main execution log with rotation
- Logs configuration, progress, warnings, and errors

**Retention Audit** (`retention_actions/`):
- `retention_*.log` - Complete audit trail of deleted files
- Only created in execute mode for compliance

### Testing Framework

**Test Data Generation**:
- `GenerateTestData.ps1` creates realistic test datasets
- Auto-scales based on available disk space
- Creates mixed file types and date ranges

**Automated Testing**:
- `RunArchiveRetentionTests.sh` executes comprehensive test suite
- SSH-based remote execution from Mac/Linux to Windows
- Covers dry-run, execute, edge cases, and error conditions

## Development Notes

### Key Safety Features
- Script enforces minimum retention (90+ days) even if lower value specified
- Dry-run mode is default behavior
- Parameter validation prevents dangerous operations
- Comprehensive error handling and logging

### Common File Patterns
- `.lca` files - LogRhythm compressed archives (default target)
- `.log` files - Standard log files
- Configuration via `-IncludeFileTypes` parameter

### Important Behaviors
- Empty directories are automatically cleaned up after file deletion
- Network drives use UNC paths, not mapped drives
- Credential system validates network access before saving
- Script implements single-instance locking to prevent concurrent runs

### Module Dependencies
- `ShareCredentialHelper.psm1` - Core credential management functions
- PowerShell 5.1+ required (PowerShell 7+ recommended for test scripts)
- Windows-specific features use conditional platform detection

### Remote Execution Preferences
- **PREFERRED**: WinRM for all PowerShell operations (session persistence, clean syntax, Kerberos auth)
- **FALLBACK**: SSH for simple commands when WinRM unavailable
- **TESTING**: Use WinRM for complex test scenarios and script execution

## Production Deployment

### Prerequisites
- PowerShell 5.1 or later
- Appropriate permissions on target directories
- Network connectivity for UNC paths
- Service account with "Log on as a batch job" rights

### Typical Deployment
1. Deploy scripts to secure location (e.g., `C:\LogRhythm\Scripts\`)
2. Configure credentials using `Save-Credential.ps1`
3. Test with dry-run mode
4. Create scheduled task using `CreateScheduledTask.ps1`
5. Monitor via logs and Windows Task Scheduler

### Security Recommendations
- Use dedicated service account for automation
- Store scripts in restricted-access directory
- Enable audit logging for compliance
- Regular credential rotation (system warns after 365 days)
- Test in non-production environment first

## 🔐 Security & Development

This repository includes comprehensive security protections and development safeguards to prevent credential exposure and maintain security standards.

**Key Security Features**:
- Automated credential detection and blocking before commits
- PowerShell-specific security pattern detection
- Documentation scanning for exposed secrets
- macOS keychain integration for secure credential storage

**Setup & Documentation**: For complete security framework setup instructions, troubleshooting, and best practices, see [`docs/pre-commit-security-setup.md`](docs/pre-commit-security-setup.md).
