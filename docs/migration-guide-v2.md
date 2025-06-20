# Migration Guide: ArchiveRetention v1.x to v2.0

## Overview

Version 2.0 of the ArchiveRetention suite represents a major refactoring with significant improvements in performance, maintainability, and reliability. This guide will help you migrate from v1.x to v2.0.

## Key Changes

### 1. Modular Architecture

The monolithic script has been broken down into specialized modules:

- **Configuration.psm1** - Configuration management and validation
- **LoggingModule.psm1** - Centralized logging with multiple streams
- **FileOperations.psm1** - File discovery and deletion with parallel processing
- **ProgressTracking.psm1** - Enhanced progress reporting and metrics
- **LockManager.psm1** - Single-instance lock management
- **ShareCredentialHelper.psm1** - Network credential management (existing)

### 2. Performance Improvements

- **Parallel File Enumeration**: Significantly faster file discovery using runspace pools
- **Batch Processing**: Files are processed in configurable batches
- **Optimized Memory Usage**: Better handling of large file sets
- **Progress Throttling**: Reduced overhead from progress updates

### 3. New Features

- **Configuration Files**: Support for JSON configuration files
- **Enhanced Scheduled Tasks**: More flexible scheduling options
- **Better Error Handling**: Detailed error reporting and recovery
- **Improved Credential Management**: Enhanced security and validation

## Breaking Changes

### Script Parameters

Some parameters have been renamed or modified:

| v1.x Parameter | v2.0 Parameter | Notes |
|---|---|---|
| N/A | `-ParallelThreads` | New: Control parallel processing (1-16) |
| N/A | `-ConfigFile` | New: Path to JSON configuration |
| N/A | `-ExcludeFileTypes` | New: File types to exclude |
| `-LogPath` | `-LogPath` | Now supports directory paths |

### Scheduled Task Changes

The `CreateScheduledTask.ps1` script now supports:
- Daily, Weekly, and Monthly schedules
- Multiple days of week for weekly schedules
- Specific day of month for monthly schedules
- Parallel thread configuration

## Migration Steps

### Step 1: Backup Current Configuration

Before upgrading, backup your current setup:

```powershell
# Backup current scripts and logs
$backupPath = "C:\Backup\ArchiveRetention_v1_$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $backupPath -Force

# Copy current installation
Copy-Item -Path "C:\LogRhythm\Scripts\ArchiveV2\*" -Destination $backupPath -Recurse
```

### Step 2: Install v2.0

1. Download the v2.0 release
2. Extract to your scripts directory
3. Ensure the `modules` subdirectory is present with all module files

### Step 3: Update Credentials (if using network shares)

Re-save your credentials with the enhanced Save-Credential.ps1:

```powershell
# Re-save existing credentials with validation
.\Save-Credential.ps1 -CredentialTarget "YourTarget" -SharePath "\\server\share" -Force
```

### Step 4: Test with Dry Run

Always test with a dry run first:

```powershell
# Test with your typical parameters
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -Verbose

# Or with network share
.\ArchiveRetention.ps1 -CredentialTarget "YourTarget" -RetentionDays 365 -Verbose
```

### Step 5: Update Scheduled Tasks

Recreate your scheduled tasks with the new script:

```powershell
# Remove old task
Unregister-ScheduledTask -TaskName "LogRhythm Archive Retention" -Confirm:$false

# Create new task with enhanced features
.\CreateScheduledTask.ps1 `
    -ArchivePath "D:\Archives" `
    -RetentionDays 365 `
    -Schedule Weekly `
    -DaysOfWeek Sunday `
    -StartTime "03:00" `
    -ParallelThreads 4
```

## Configuration File Usage (Optional)

Create a configuration file for consistent settings:

```json
{
    "MinimumRetentionDays": 90,
    "ParallelThreads": 4,
    "BatchSize": 1000,
    "MaxRetries": 3,
    "ProgressUpdateIntervalSeconds": 30
}
```

Use with:

```powershell
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -ConfigFile ".\config\my-config.json" -Execute
```

## Performance Tuning

### Parallel Threads

Adjust based on your system:
- **Small archives (<100GB)**: 2-4 threads
- **Medium archives (100GB-1TB)**: 4-8 threads  
- **Large archives (>1TB)**: 8-16 threads

### Batch Size

Controls how many files are processed at once:
- **Default**: 1000 files
- **Network shares**: Consider reducing to 500
- **Local fast storage**: Can increase to 2000-5000

## Troubleshooting

### Common Issues

1. **Module Import Errors**
   - Ensure all module files are in the `modules` subdirectory
   - Check PowerShell execution policy: `Get-ExecutionPolicy`

2. **Performance Not Improved**
   - Verify parallel threads setting
   - Check if antivirus is scanning operations
   - Monitor with `-Verbose` flag

3. **Scheduled Task Failures**
   - Check Event Viewer for detailed errors
   - Verify service account permissions
   - Test manually first

### Getting Help

- Use `-Verbose` for detailed logging
- Check logs in `script_logs` directory
- Review retention action logs in `script_logs\retention_actions`

## Rollback Procedure

If you need to rollback to v1.x:

1. Stop any running scheduled tasks
2. Restore from your backup:
   ```powershell
   Copy-Item -Path "$backupPath\*" -Destination "C:\LogRhythm\Scripts\ArchiveV2\" -Force -Recurse
   ```
3. Recreate scheduled tasks with old script

## Best Practices

1. **Always Test First**: Use dry-run mode before executing
2. **Monitor Initial Runs**: Watch the first few automated runs closely
3. **Review Logs**: Check both main and retention action logs
4. **Start Conservative**: Begin with fewer parallel threads and increase gradually
5. **Keep Backups**: Maintain backups of your v1.x setup until confident

## Support

For issues or questions:
1. Review the comprehensive help: `Get-Help .\ArchiveRetention.ps1 -Full`
2. Check the [README.md](README.md) for detailed documentation
3. Enable verbose logging for troubleshooting

---

**Important**: This version includes significant architectural changes. While we've maintained backward compatibility where possible, please test thoroughly in your environment before deploying to production. 