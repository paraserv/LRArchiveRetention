# IDE Quick Reference: LogRhythm Archive Retention (v2)

## Server Connection
```bash
# Basic SSH
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200
```

## File Operations

### Copy Files
```bash
# Single file
scp -i ~/.ssh/id_rsa_windows file.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/'
```

### Run Script
```bash
# Dry run (no changes)
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 120 -Verbose }"'

# With execute (delete files)
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 120 -Execute -Verbose }"'
```

## Common Tasks

### Check Files
```bash
# List files with details
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' -Recurse -File | Sort-Object LastWriteTime | Select-Object -First 5 FullName, LastWriteTime, @{Name=''DaysOld'';Expression={[math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 2)}} | Format-Table -AutoSize"'
```

### Check Logs
```bash
# View recent log entries
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-Content -Tail 20 ''C:\LogRhythm\Scripts\ArchiveV2\ArchiveRetention_*.log''"'
```

## Quick Troubleshooting

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

git checkout v2  # Switch to v2 branch
git status      # Check status
```

> **Note**: Always test with `-Verbose` before using `-Execute`
