# LogRhythm Archive Retention Manager (v2.1)

A high-performance PowerShell script for managing LogRhythm archive retention policies. This script helps automate the cleanup of old archive files while providing detailed logging and reporting. The latest version includes performance optimizations and enhanced logging capabilities.

## Features

- **Safe Execution**: Dry-run mode by default, requires `-Execute` flag for actual deletions
- **High Performance**: Efficient processing of large numbers of archive files
- **Detailed Logging**: Comprehensive logging with timestamps and operation details
- **Progress Tracking**: Real-time progress updates during execution
- **Error Handling**: Robust error handling and recovery mechanisms
- **Flexible Configuration**: Customize retention periods and archive locations
- **Verbose Output**: Detailed console output with `-Verbose` flag
- **Performance Optimized**: Efficient file scanning and processing
- **Enhanced Logging**: Detailed file statistics and progress tracking
- **Safe Execution**: Comprehensive dry-run functionality

## Requirements

- Windows Server with LogRhythm Archive Manager
- PowerShell 5.1 or later
- Appropriate permissions on LogRhythm archive directories
- Sufficient disk space for log files

## Installation

1. Copy the `ArchiveRetention.ps1` script to your LogRhythm server
2. Place it in a secure directory (e.g., `C:\LogRhythm\Scripts\ArchiveV2\`)
3. Ensure the script has read/write permissions to the archive directories

## Usage

### Basic Usage

```powershell
# Show help and available parameters
.\ArchiveRetention.ps1 -Help

# Dry run (shows what would be deleted)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\InactiveTest" -RetentionDays 88 -Verbose

# Actual execution (deletes files)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\InactiveTest" -RetentionDays 88 -Execute -Verbose

# Example output from dry run:
# Found 6,484 files (2.3 GB) that would be processed (older than 88 days)
# Oldest file: 20250303_1_1_1_638765599202720081.lca (Last modified: 03/02/2025)
# Newest file: 20250314_1_1_1_638775155530957788.lca (Last modified: 03/13/2025)
```

### Advanced Examples

```powershell
# Process a specific archive directory
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\InactiveTest" -RetentionDays 90 -Execute -Verbose

# Process with custom log location
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives" -RetentionDays 60 -LogPath "C:\Logs\archive_retention.log" -Execute
```

### Scheduled Task Example

Create a scheduled task to run the script weekly:

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\LogRhythm\Scripts\ArchiveV2\ArchiveRetention.ps1" -ArchivePath "D:\LogRhythmArchives" -RetentionDays 120 -Execute -Verbose'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -RunOnlyIfNetworkAvailable
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "LogRhythm Archive Retention" -Description "Runs LogRhythm archive retention weekly" -User "SYSTEM" -RunLevel Highest
```

> **Note**: Run the scheduled task as SYSTEM or a service account with appropriate permissions.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ArchivePath` | Path to LogRhythm archive directory (e.g., `D:\LogRhythmArchives\InactiveTest`) | Required |
| `-RetentionDays` | Number of days to retain archive files (e.g., `88` for ~3 months) | Required |
| `-Execute` | Perform actual file deletions (without this, runs in dry-run mode) | `$false` |
| `-LogPath` | Path to log file | `./ArchiveRetention.log` |
| `-MaxConcurrency` | Maximum number of concurrent operations | `8` |
| `-BatchSize` | Number of files to process in each batch | `100` |
| `-Verbose` | Show detailed output during execution | `$false` |

## Best Practices

1. **Always test first**: Run without `-Execute` to verify which files will be deleted
2. **Check disk space**: Ensure you have sufficient space before running with `-Execute`
3. **Start with a subset**: Test with a smaller directory first
4. **Review logs**: Check the log file after each run for any warnings or errors
5. **Schedule during off-peak**: Run during maintenance windows to minimize impact
6. **Monitor progress**: The script provides real-time progress updates
7. **Keep logs**: Archive logs for compliance and troubleshooting

## Performance Considerations

- Processing approximately 6,500 files (~2.3GB) takes about 3-5 minutes in dry-run mode
- Actual deletion time depends on storage performance
- Memory usage is optimized to handle large numbers of files
- Network paths are supported but may be slower than local storage

> **Note**: The script automatically handles LogRhythm archive files (`.lca`). Other file types are ignored by default.

## Logging

The script generates detailed logs in the following format:
```
2025-06-01 12:00:00.123 [INFO] - Starting archive retention process
2025-06-01 12:00:01.234 [DEBUG] - Processing file: D:\LogRhythmArchives\archive1.lca
2025-06-01 12:00:02.345 [WARNING] - File is newer than retention period, skipping
2025-06-01 12:00:03.456 [ERROR] - Error processing file: Access denied
```

By default, logs are written to `ArchiveRetention.log` in the same directory as the script. You can specify a custom log path using the `-LogPath` parameter.

## Best Practices

1. **Always test first**: Run without `-Execute` to verify which files will be deleted
2. **Start with higher retention**: Begin with a longer retention period and gradually reduce
3. **Monitor initial runs**: Check system resources during the first few executions
4. **Schedule during off-peak**: Run during maintenance windows to minimize impact
5. **Review logs**: Check the log file after each run for any warnings or errors
6. **Regular maintenance**: Run the script regularly to prevent archive directory growth
7. **Backup first**: Ensure you have backups before running with `-Execute`

## Troubleshooting

### Common Issues

1. **Access Denied**
   - Ensure the script is run with administrative privileges
   - Verify the account has Full Control permissions on the archive directory

2. **Files Not Being Deleted**
   - Check if the files are older than the specified retention period
   - Verify the path is correct and accessible
   - Ensure no other processes have the files locked

3. **Performance Issues**
   - For large directories, consider increasing `-BatchSize`
   - Reduce `-MaxConcurrency` if system resources are constrained
   - Avoid running during peak hours

4. **Log File Growth**
   - Logs automatically rotate when they reach 10MB
   - Up to 5 log files are kept by default

## Version History

### v2.1 (2025-06-09)
- Added detailed file statistics in dry-run mode
- Improved logging of file counts and sizes
- Added progress tracking and ETA calculations
- Fixed thread safety issues in counter variables
- Enhanced error handling and recovery

### v2.0 (2025-06-01)
- Initial release with basic retention management
- Support for dry-run and execute modes
- Basic logging functionality

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

- **Access Denied**: Ensure the script runs with appropriate permissions
- **No files processed**: Verify the `-ArchivePath` is correct and contains `.lca` files
- **Unexpected deletions**: Always test with `-Verbose` first to review actions
- **Log file issues**: Check disk space and permissions for the log directory

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

Contributions are welcome! Please follow the standard GitHub fork and pull request workflow.

## Author

Nathan Church  
nathan.church@exabeam.com  
Exabeam Professional Services

## Version

v2.0 - June 2025  
- Complete rewrite with improved error handling and logging
- Fixed empty message parameter binding issues
- Enhanced logging and progress tracking
- Optimized for LogRhythm archive management
