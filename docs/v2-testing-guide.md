# ArchiveRetention v2.0 Testing Guide

This guide provides step-by-step instructions for testing the v2.0 modular refactor.

## Prerequisites

- PowerShell 5.1 or later
- Windows environment (for full testing)
- Administrative privileges (for scheduled task tests)

## Quick Start Testing

### 1. Run Local Tests (macOS/Linux)

The test suite can partially run on non-Windows systems:

```bash
# Run all tests
pwsh ./run-tests.ps1

# Run only module tests
pwsh ./run-tests.ps1 -ModulesOnly

# Skip file operations tests (if no temp access)
pwsh ./run-tests.ps1 -SkipFileOperations
```

### 2. Test on Windows Server

Transfer files and test on your Windows server:

```bash
# Copy to Windows server
scp -r * administrator@10.20.1.200:C:/LogRhythm/Scripts/ArchiveV2/

# Connect and test
ssh administrator@10.20.1.200
cd C:\LogRhythm\Scripts\ArchiveV2
.\run-tests.ps1
```

## Manual Testing Steps

### Step 1: Module Testing

Test individual modules:

```powershell
# Test all modules
.\tests\test-v2-modules.ps1 -Verbose

# Test without file operations
.\tests\test-v2-modules.ps1 -SkipFileOperations
```

Expected output:
- All modules should import successfully
- All function tests should pass
- File operations create/cleanup test data

### Step 2: Integration Testing

Test the main script functionality:

```powershell
# Run integration tests with auto-generated test data
.\tests\test-integration.ps1 -UseDefaultTestPath -Verbose

# Test with your own test directory
.\tests\test-integration.ps1 -TestPath "C:\TestArchive"
```

Tests include:
- Dry run functionality
- Parallel processing performance
- File type filtering
- Configuration file support
- Single instance locking

### Step 3: Real-World Testing (Dry Run)

Test with actual archive directories:

```powershell
# Local path test
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 365 -Verbose

# Network share test (if credentials saved)
.\ArchiveRetention.ps1 -CredentialTarget "LR_NAS" -RetentionDays 365 -Verbose

# Test with different thread counts
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -ParallelThreads 8

# Test with configuration file
.\ArchiveRetention.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -ConfigFile ".\config\archive-retention-config.json"
```

### Step 4: Performance Testing

Compare v1.x vs v2.0 performance:

```powershell
# Measure v2.0 performance
Measure-Command {
    .\ArchiveRetention.ps1 -ArchivePath "D:\LargeArchive" -RetentionDays 365 -ParallelThreads 8
}

# Test different thread counts
1,2,4,8,16 | ForEach-Object {
    Write-Host "Testing with $_ threads..."
    Measure-Command {
        .\ArchiveRetention.ps1 -ArchivePath "D:\LargeArchive" -RetentionDays 365 -ParallelThreads $_
    }
}
```

### Step 5: Scheduled Task Testing

Test scheduled task creation:

```powershell
# Create test scheduled task
.\CreateScheduledTask.ps1 -ArchivePath "D:\TestArchive" -RetentionDays 180 -TaskName "TEST_ArchiveRetention" -WhatIf

# Create actual task (requires admin)
.\CreateScheduledTask.ps1 -ArchivePath "D:\Archives" -RetentionDays 365 -Schedule Weekly -DaysOfWeek Sunday,Wednesday

# Test immediate execution
Start-ScheduledTask -TaskName "LogRhythm Archive Retention"
```

## Test Scenarios

### Scenario 1: Small Archive (< 10GB)
```powershell
.\ArchiveRetention.ps1 -ArchivePath "C:\SmallArchive" -RetentionDays 90 -ParallelThreads 2 -Verbose
```

### Scenario 2: Large Archive (> 100GB)
```powershell
.\ArchiveRetention.ps1 -ArchivePath "D:\LargeArchive" -RetentionDays 365 -ParallelThreads 8 -Verbose
```

### Scenario 3: Network Share
```powershell
# Save credentials first
.\Save-Credential.ps1 -CredentialTarget "TestNAS" -SharePath "\\server\archive" -SkipValidation

# Test retention
.\ArchiveRetention.ps1 -CredentialTarget "TestNAS" -RetentionDays 180 -ParallelThreads 4
```

### Scenario 4: Mixed File Types
```powershell
# Only .lca files
.\ArchiveRetention.ps1 -ArchivePath "C:\MixedArchive" -RetentionDays 365 -IncludeFileTypes @('.lca')

# Multiple types
.\ArchiveRetention.ps1 -ArchivePath "C:\MixedArchive" -RetentionDays 365 -IncludeFileTypes @('.lca', '.log', '.txt')

# Exclude certain types
.\ArchiveRetention.ps1 -ArchivePath "C:\MixedArchive" -RetentionDays 365 -ExcludeFileTypes @('.tmp', '.temp')
```

## Troubleshooting

### Module Import Errors
```powershell
# Test module loading manually
Import-Module .\modules\Configuration.psm1 -Force -Verbose
Get-Command -Module Configuration
```

### Lock File Issues
```powershell
# Check for stale locks
Get-ChildItem $env:TEMP -Filter "*.lock"

# Remove stale lock
Remove-Item "$env:TEMP\ArchiveRetention.lock" -Force
```

### Performance Issues
```powershell
# Enable detailed timing
.\ArchiveRetention.ps1 -ArchivePath "D:\Archive" -RetentionDays 365 -Verbose

# Monitor memory usage
Get-Process powershell | Select-Object WS, CPU
```

## Validation Checklist

- [ ] All module tests pass
- [ ] Integration tests complete successfully
- [ ] Dry run shows expected files
- [ ] Parallel processing improves performance
- [ ] Configuration file loads correctly
- [ ] Single instance lock prevents duplicates
- [ ] Scheduled task creates successfully
- [ ] Network share access works (if applicable)
- [ ] Log files are created in correct locations
- [ ] No memory leaks during large operations

## Reporting Issues

When reporting issues, please include:

1. PowerShell version: `$PSVersionTable`
2. Error messages and stack traces
3. Log files from `script_logs` directory
4. Test command that failed
5. System specifications (OS, available memory)

## Next Steps

After successful testing:

1. Review logs in `script_logs` directory
2. Test with `-Execute` flag in a safe environment
3. Monitor first production run closely
4. Set up scheduled tasks for automation
5. Configure monitoring/alerting as needed 