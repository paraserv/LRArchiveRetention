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
python3 -c "
import winrm
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman', 
                       auth=('svc_logrhythm@LAB.PARASERV.COM', 'logrhythm!1'), 
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