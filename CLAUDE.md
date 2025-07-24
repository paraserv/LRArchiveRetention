# CLAUDE.md

Development guidance for Claude Code when working with the LogRhythm Archive Retention Manager.

## Overview

PowerShell-based archive retention system for LogRhythm .lca files with secure credential management.

**Version**: 2.2.0 | **Docs**: [README.md](README.md) | [CHANGELOG.md](CHANGELOG.md) | [Technical Docs](docs/)

## Quick Commands

```powershell
# Dry-run (default, safe)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456

# Execute deletions
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456 -Execute

# Use saved credentials
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095 -Execute

# Save credentials
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share"

# Run tests
cd tests && bash RunArchiveRetentionTests.sh
```

## Development Environment

### Remote Access

```bash
# SSH (interactive)
ssh windev01

# WinRM (automation) - use timeout to prevent hanging
source winrm_env/bin/activate
timeout 10 python3 tools/winrm_helper.py nas_dry_run 456

# Helper tool commands
python3 tools/winrm_helper.py local          # Test local path
python3 tools/winrm_helper.py nas            # Test NAS access
python3 tools/winrm_helper.py nas_execute 456 # Execute with retention
```

### Connection Details
- **Windows**: windev01.lab.paraserv.com (10.20.1.20)
- **NAS**: 10.20.1.7 (\\10.20.1.7\LRArchives)
- **Script Path**: C:\LR\Scripts\LRArchiveRetention\

### Authentication
See [`docs/credentials.md`](docs/credentials.md) for detailed setup. Quick reference:

```bash
# Store credentials in macOS keychain
security add-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w
security add-internet-password -s "10.20.1.7" -a "sanghanas" -w
```

## Architecture Notes

### Core Scripts
- `ArchiveRetention.ps1` - Main retention engine (streaming mode in v2.2.0+)
- `Save-Credential.ps1` - Credential management
- `modules/ShareCredentialHelper.psm1` - Credential helper module

### Key Features
- **Streaming Mode**: O(1) memory usage, immediate deletion start
- **Safety**: 90+ day minimum retention, dry-run default
- **Progress**: Configurable intervals with `-QuietMode`, `-ShowScanProgress`, `-ShowDeleteProgress`
- **Logging**: `script_logs/` (execution) and `retention_actions/` (audit)

### Important Behaviors
- Empty directories cleaned automatically
- Single-instance locking prevents concurrent runs
- Network paths use UNC format (not mapped drives)
- System.IO optimization for 10-20x faster scanning

### WinRM Timeout Guidelines
- Simple commands: 5 seconds
- File operations: 10 seconds  
- Script execution: 15-30 seconds
- Large operations: 60-120 seconds

Always use `timeout` command to prevent hanging.

## Git Workflow

Standard workflow - no special scripts needed:

```bash
git add -A
git commit -m "your message"
git push origin main
```

For security setup and troubleshooting, see [`docs/pre-commit-security-setup.md`](docs/pre-commit-security-setup.md).

## Important Reminders
- NEVER create files unless necessary - prefer editing existing files
- NEVER create documentation proactively - only when requested
- Clear communication - avoid emojis in responses