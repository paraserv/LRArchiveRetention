# Archive Retention Manager

A high-performance PowerShell script for managing file retention policies in archive directories. This script helps automate the cleanup of old files while providing detailed logging and reporting.

## Features

- **Flexible Retention Policies**: Define retention periods in days (1-3650)
- **Safe Execution**: Dry-run mode by default, requires `-Execute` flag for actual deletions
- **High Performance**: Multi-threaded processing with configurable concurrency
- **Network Optimized**: Handles UNC paths efficiently with connection pooling
- **Smart Caching**: Caches directory scans for faster subsequent runs
- **Detailed Logging**: Comprehensive logging with rotation and compression
- **File Type Filtering**: Include/exclude specific file types
- **Progress Tracking**: Real-time progress with ETA and processing rates

## Requirements

- Windows PowerShell 5.1 or later
- .NET Framework 4.7.2 or later
- Appropriate permissions on target directories

## Installation

1. Clone this repository:
   ```powershell
   git clone https://your-repository-url/ArchiveRetention.git
   cd ArchiveRetention
   ```

2. (Optional) Add the script to your system PATH or use it directly from the repository.

## Usage

### Basic Usage

```powershell
# Show help
.\ArchiveRetention.ps1 -Help

# Dry run (shows what would be deleted)
.\ArchiveRetention.ps1 -ArchivePath "C:\Archive" -RetentionDays 90

# Actual execution (deletes files)
.\ArchiveRetention.ps1 -ArchivePath "C:\Archive" -RetentionDays 90 -Execute
```

### Advanced Examples

```powershell
# Process network share with custom concurrency
.\ArchiveRetention.ps1 -ArchivePath "\\server\share\archive" -RetentionDays 180 -MaxConcurrency 4 -Execute

# Process specific file types only
.\ArchiveRetention.ps1 -ArchivePath "D:\Logs" -RetentionDays 30 -IncludeFileTypes @('.log','.txt') -Execute

# Exclude certain file types
.\ArchiveRetention.ps1 -ArchivePath "E:\Backups" -RetentionDays 365 -ExcludeFileTypes @('.bak','.tmp') -Execute

# Custom log location and verbosity
.\ArchiveRetention.ps1 -ArchivePath "C:\Temp" -RetentionDays 7 -LogPath "C:\Logs\archive_cleanup.log" -Verbose -Execute
```

### Scheduled Task Example

Create a scheduled task to run the script weekly:

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\ArchiveRetention.ps1" -ArchivePath "C:\Archive" -RetentionDays 90 -Execute -LogPath "C:\Logs\archive_cleanup.log"'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Weekly Archive Cleanup" -Description "Runs weekly archive cleanup"
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ArchivePath` | Path to archive directory (required) | |
| `-RetentionDays` | Number of days to retain files (1-3650) (required) | |
| `-Execute` | Perform actual file deletions (without this, runs in dry-run mode) | $false |
| `-LogPath` | Path to log file | `./ArchiveRetention.log` |
| `-MaxConcurrency` | Maximum concurrent operations (1-32) | 8 |
| `-IncludeFileTypes` | Process only these file extensions | `@('.lca')` |
| `-ExcludeFileTypes` | Exclude these file extensions | `@()` |
| `-MaxRetries` | Maximum retry attempts for failed operations | 3 |
| `-RetryDelaySeconds` | Delay between retry attempts | 5 |
| `-BatchSize` | Number of files to process in each batch | 1000 |
| `-UseCache` | Enable directory scan caching | $true |
| `-CacheValidityHours` | Hours before cache is considered stale | 12 |

## Logging

The script generates detailed logs with the following format:
```
[2023-01-01 12:00:00] [INFO] - Message
[2023-01-01 12:00:01] [WARNING] - Warning message
[2023-01-01 12:00:02] [ERROR] - Error message
```

Logs are automatically rotated when they reach 10MB, keeping up to 5 compressed backups.

## Performance Considerations

- **Memory Usage**: Processes files in batches to control memory consumption
- **Network**: Optimized for WAN operations with connection pooling
- **CPU**: Multi-threaded processing with configurable concurrency
- **Storage**: Caches directory scans to improve performance

## Best Practices

1. Always test with `-Verbose` and without `-Execute` first
2. Start with a small retention period and gradually increase
3. Monitor system resources during initial runs
4. Schedule during off-peak hours for production systems
5. Review logs after each run

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please follow the standard GitHub fork and pull request workflow.

## Author

Nathan Church  
Nathan.Church@exabeam.com  
Exabeam Professional Services
