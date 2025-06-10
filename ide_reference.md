# IDE Quick Reference: LogRhythm Archive Retention

> **Versioning Note:** The authoritative version is defined in `ArchiveRetention.ps1` (`$SCRIPT_VERSION`).

## Server Connection
```bash
# Basic SSH
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200
```

## File Operations

### Copy Script to Server
```bash
scp -i ~/.ssh/id_rsa_windows ArchiveRetention.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/'
```

### Run Script

#### Dry Run (no changes, safe for any retention)
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 20 -Verbose }"'
```

#### Execute (deletes files, minimum retention enforced)
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 20 -Execute -Verbose }"'
# If RetentionDays < 90, the script will enforce 90 days for deletion and log a warning.
```

## Common Tasks

### List Files with Details
```bash
# List files with details
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' -Recurse -File | Sort-Object LastWriteTime | Select-Object -First 5 FullName, LastWriteTime, @{Name=''DaysOld'';Expression={[math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 2)}} | Format-Table -AutoSize"'
```

### View Recent Log Entries
```bash
# View recent log entries
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-Content -Tail 20 ''C:\LogRhythm\Scripts\ArchiveV2\ArchiveRetention.log''"'
```

## Troubleshooting

### Connection Issues
```bash
# Test basic connectivity
ping 10.20.1.200
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'hostname'

# Check key permissions
chmod 600 ~/.ssh/id_rsa_windows
```

### Common Errors
- `Ampersand not allowed`: Fix quoting
- `Unexpected token`: Check special characters
- `Cannot bind parameter`: Verify parameter names/values

## Git Operations
```bash
# Commit changes
git add .
git commit -m "Update script with improved error handling"
git status      # Check status
```

> **Note:**  
> - Always test with `-Verbose` before using `-Execute`.
> - The script enforces a minimum retention of 90 days for deletion. Dry-run will warn but proceed with any value; execute will enforce the minimum.
