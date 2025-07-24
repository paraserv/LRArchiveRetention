# Command Reference

Complete reference for all commands and parameters in the LogRhythm Archive Retention Manager.

## Table of Contents
- [ArchiveRetention.ps1](#archiveretentionps1)
- [Save-Credential.ps1](#save-credentialps1)
- [CreateScheduledTask.ps1](#createscheduledtaskps1)
- [Module Commands](#module-commands)
- [Remote Operations (winrm_helper.py)](#remote-operations-winrm_helperpy)
- [Test Commands](#test-commands)

## ArchiveRetention.ps1

Main retention script for cleaning up old archive files.

### Basic Syntax

```powershell
.\ArchiveRetention.ps1 [-ArchivePath <String>] | [-CredentialTarget <String>]
                       -RetentionDays <Int32>
                       [-Execute]
                       [-ShowScanProgress] [-ShowDeleteProgress]
                       [-ProgressInterval <Int32>]
                       [-QuietMode]
                       [-ParallelProcessing]
                       [-ThreadCount <Int32>]
                       [-BatchSize <Int32>]
                       [-IncludeFileTypes <String[]>]
                       [-Force]
                       [-Verbose]
```

### Parameter Sets

**LocalPath**: For local directories or UNC paths without saved credentials
```powershell
-ArchivePath <String>    # Required: Path to archive directory
```

**NetworkShare**: For network shares using saved credentials
```powershell
-CredentialTarget <String>    # Required: Name of saved credential
```

### Common Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-RetentionDays` | Int32 | Required | Days to retain files (minimum 90) |
| `-Execute` | Switch | False | Execute deletions (default is dry-run) |
| `-ShowScanProgress` | Switch | False | Show scanning progress indicators |
| `-ShowDeleteProgress` | Switch | False | Show deletion progress counters |
| `-ProgressInterval` | Int32 | 30 | Progress update interval in seconds |
| `-QuietMode` | Switch | False | Suppress all progress output |
| `-ParallelProcessing` | Switch | False | Enable multi-threaded processing |
| `-ThreadCount` | Int32 | 4 | Number of parallel threads |
| `-BatchSize` | Int32 | 100 | Files per batch in parallel mode |
| `-IncludeFileTypes` | String[] | @("*.lca") | File patterns to process |
| `-Force` | Switch | False | Skip confirmation prompts |
| `-Verbose` | Switch | False | Enable detailed logging |

### Usage Examples

#### Basic Operations

```powershell
# Dry-run on local path (default safe mode)
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365

# Execute deletion with 15-month retention
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 456 -Execute

# Network share with saved credentials
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095 -Execute
```

#### Progress Monitoring

```powershell
# Show all progress indicators
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 `
    -ShowScanProgress -ShowDeleteProgress -ProgressInterval 10

# Quiet mode for scheduled tasks
.\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 456 `
    -QuietMode -Execute
```

#### Performance Optimization

```powershell
# Enable parallel processing (4-8x faster on network shares)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 365 `
    -ParallelProcessing -ThreadCount 8 -BatchSize 200 -Execute

# Process multiple file types
.\ArchiveRetention.ps1 -ArchivePath "D:\Logs" -RetentionDays 180 `
    -IncludeFileTypes "*.lca","*.log","*.bak" -Execute
```

### Common Retention Periods

| Period | Days | Example Cutoff (from 2025-07-24) |
|--------|------|----------------------------------|
| 3 months | 90 | 2025-04-25 |
| 6 months | 180 | 2025-01-24 |
| 1 year | 365 | 2024-07-24 |
| 15 months | 456 | 2024-04-24 |
| 2 years | 730 | 2023-07-24 |
| 3 years | 1095 | 2022-07-24 |

## Save-Credential.ps1

Securely stores network credentials for automated access to network shares.

### Syntax

```powershell
.\Save-Credential.ps1 -Target <String> 
                     -SharePath <String>
                     [-UserName <String>]
                     [-UseStdin]
                     [-Quiet]
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Target` | String | Yes | Credential identifier name |
| `-SharePath` | String | Yes | UNC path to network share |
| `-UserName` | String | No | Username (prompts if not provided) |
| `-UseStdin` | Switch | No | Read password from stdin |
| `-Quiet` | Switch | No | Suppress output messages |

### Examples

```powershell
# Interactive mode (recommended)
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\nas01\archives"

# Specify username
.\Save-Credential.ps1 -Target "NAS_DEV" -SharePath "\\nas02\test" -UserName "domain\svc_account"

# Automated mode (for scripts)
echo "password" | .\Save-Credential.ps1 -Target "NAS_BACKUP" `
    -SharePath "\\backup\archives" -UserName "backup\admin" -UseStdin -Quiet
```

## CreateScheduledTask.ps1

Creates Windows scheduled tasks for automated archive cleanup.

### Syntax

```powershell
.\CreateScheduledTask.ps1 -TaskName <String>
                         -TaskDescription <String>
                         -ScriptPath <String>
                         [-ArchivePath <String>] | [-CredentialTarget <String>]
                         -RetentionDays <Int32>
                         [-ServiceAccount <String>]
                         [-TriggerType <String>]
                         [-DaysOfWeek <String[]>]
                         [-StartTime <DateTime>]
                         [-Execute]
```

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TaskName` | String | Required | Name for scheduled task |
| `-TaskDescription` | String | Required | Task description |
| `-ScriptPath` | String | Required | Full path to ArchiveRetention.ps1 |
| `-ServiceAccount` | String | Current user | Account to run task as |
| `-TriggerType` | String | "Weekly" | Schedule type (Daily/Weekly) |
| `-DaysOfWeek` | String[] | @("Sunday") | Days for weekly trigger |
| `-StartTime` | DateTime | 2:00 AM | Task start time |
| `-Execute` | Switch | False | Apply additional parameters |

### Examples

```powershell
# Weekly cleanup task
.\CreateScheduledTask.ps1 `
    -TaskName "LogRhythm Archive Cleanup" `
    -TaskDescription "Weekly cleanup of archives older than 15 months" `
    -ScriptPath "C:\Scripts\LRArchiveRetention\ArchiveRetention.ps1" `
    -CredentialTarget "NAS_PROD" `
    -RetentionDays 456 `
    -ServiceAccount "DOMAIN\svc_logrhythm" `
    -Execute

# Daily task with specific time
.\CreateScheduledTask.ps1 `
    -TaskName "Daily Archive Check" `
    -TaskDescription "Daily archive cleanup" `
    -ScriptPath "C:\Scripts\ArchiveRetention.ps1" `
    -ArchivePath "D:\Archives" `
    -RetentionDays 90 `
    -TriggerType "Daily" `
    -StartTime "03:30:00" `
    -Execute
```

## Module Commands

Commands available after importing the ShareCredentialHelper module.

### Import Module

```powershell
Import-Module .\modules\ShareCredentialHelper.psm1
```

### Available Commands

#### Get-SavedCredentials
Lists all saved credentials.

```powershell
# List all credentials
Get-SavedCredentials

# Format output
Get-SavedCredentials | Format-Table Target, SharePath, UserName, LastUsed -AutoSize

# Filter by target
Get-SavedCredentials | Where-Object { $_.Target -like "*PROD*" }
```

#### Test-SavedCredential
Tests if a saved credential can connect to its share.

```powershell
# Test specific credential
Test-SavedCredential -Target "NAS_PROD"

# Test all credentials
Get-SavedCredentials | ForEach-Object {
    Test-SavedCredential -Target $_.Target
}
```

#### Remove-SavedCredential
Removes a saved credential.

```powershell
# Remove specific credential
Remove-SavedCredential -Target "OLD_NAS"

# Remove with confirmation
Remove-SavedCredential -Target "NAS_TEST" -Confirm
```

## Remote Operations (winrm_helper.py)

Python utility for managing retention operations remotely.

### Setup

```bash
# Activate virtual environment
source winrm_env/bin/activate

# Basic usage
python3 tools/winrm_helper.py <command> [retention_days]
```

### Available Commands

| Command | Description | Example |
|---------|-------------|---------|
| `test` | Test WinRM connection | `python3 tools/winrm_helper.py test` |
| `local` | Run on local test path | `python3 tools/winrm_helper.py local` |
| `nas` | Test NAS with default retention | `python3 tools/winrm_helper.py nas` |
| `nas_dry_run` | NAS dry-run with custom days | `python3 tools/winrm_helper.py nas_dry_run 456` |
| `nas_execute` | NAS execution with custom days | `python3 tools/winrm_helper.py nas_execute 456` |
| `parameters` | Test v1.2.0+ parameters | `python3 tools/winrm_helper.py parameters` |
| `cleanup` | Remove stale lock files | `python3 tools/winrm_helper.py cleanup` |

### Examples

```bash
# Test connection
python3 tools/winrm_helper.py test

# Production dry-run (15 months)
python3 tools/winrm_helper.py nas_dry_run 456

# Production execution (3 years)
python3 tools/winrm_helper.py nas_execute 1095

# Clean up lock files
python3 tools/winrm_helper.py cleanup
```

## Test Commands

### Generate Test Data

```powershell
# Generate test dataset
.\tests\GenerateTestData.ps1 -RootPath "D:\TestArchives" `
    -TotalSizeGB 10 `
    -FileCount 1000 `
    -DateRangeYears 3

# Quick test dataset
.\tests\GenerateTestData.ps1 -RootPath "C:\temp\test" -QuickTest
```

### Run Test Suite

```bash
# From Mac/Linux
cd tests
bash RunArchiveRetentionTests.sh

# Specific test categories
bash RunArchiveRetentionTests.sh --dry-run-only
bash RunArchiveRetentionTests.sh --execute-only
bash RunArchiveRetentionTests.sh --edge-cases
```

### Manual Testing

```powershell
# Test credential handling
.\tests\TestCredentialHandling.ps1

# Test file operations
.\tests\TestFileOperations.ps1 -TestPath "D:\TestArchives"

# Performance testing
.\tests\TestPerformance.ps1 -ArchivePath "\\nas\test" -FileCount 10000
```

## Quick Reference Card

### Most Common Operations

```powershell
# Production 15-month cleanup (dry-run first!)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 456
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 456 -Execute

# Scheduled task quiet mode
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 456 -QuietMode -Execute

# Performance mode for large datasets
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 365 `
    -ParallelProcessing -ThreadCount 8 -Execute

# Save new credentials
.\Save-Credential.ps1 -Target "NEW_NAS" -SharePath "\\newnas\share"

# Remote execution
python3 tools/winrm_helper.py nas_execute 456
```

### Troubleshooting Commands

```powershell
# Check logs for errors
Select-String -Path .\script_logs\*.log -Pattern "ERROR" -Context 2

# Test credential access
Import-Module .\modules\ShareCredentialHelper.psm1
Test-SavedCredential -Target "NAS_PROD"

# Clean up lock files
Remove-Item ".\script_logs\*.lock" -Force

# Verbose mode for debugging
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 90 -Verbose
```