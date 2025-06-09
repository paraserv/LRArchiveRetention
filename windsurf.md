# Windows Server Interaction Guide (v2)

This document outlines how to interact with the Windows server from the Mac environment. The v2 version of the script includes improved error handling, better logging, and more reliable file processing.

## Connection Details

- **Server IP**: 10.20.1.200
- **SSH Key**: `~/.ssh/id_rsa_windows`
- **Username**: administrator
- **PowerShell Path**: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
- **Script Location**: `C:\LogRhythm\Scripts\ArchiveV2\`

## SSH Command Format

### Basic Structure
```bash
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { <commands> }"'
```

### Key Points
1. Use single quotes around the entire command
2. Escape inner single quotes by doubling them: `''`
3. For PowerShell commands, use `-Command` with double quotes
4. For complex commands, use `& { }` to group them

## Common Commands

### 1. Copy Files to Windows Server
```bash
# Copy a file to the server
scp -i ~/.ssh/id_rsa_windows /local/path/to/file administrator@10.20.1.200:'C:/destination/path/'

# Example: Copy the script
scp -i ~/.ssh/id_rsa_windows ArchiveRetention.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/'
```

### 2. Execute PowerShell Commands
```bash
# Basic PowerShell command
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Write-Output ''Hello World''"'

# Run script with parameters (v2 Format)
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 120 -Execute -Verbose }"'
```

### 3. Check File System
```bash
# List files in a directory
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' | Select-Object Name, Length, LastWriteTime"'

# List files with full details (simplified)
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' -Recurse -File | Sort-Object LastWriteTime | Select-Object -First 5 | Format-List FullName, LastWriteTime"'
```

### 4. Check File Timestamps
```bash
# Find files older than X days
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "$cutoff = (Get-Date).AddDays(-120); Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' -Recurse -File | Where-Object { $_.LastWriteTime -lt $cutoff } | Select-Object -First 5 FullName, LastWriteTime, @{Name=''DaysOld'';Expression={[math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 2)}} | Format-Table -AutoSize"'
```

## Troubleshooting

1. **SSH Connection Issues**
   - Verify the server is reachable: `ping 10.20.1.200`
   - Check SSH key permissions: `chmod 600 ~/.ssh/id_rsa_windows`
   - Test basic SSH connection: `ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'hostname'`

2. **PowerShell Execution Issues**
   - Always use `-NoProfile` to avoid profile loading issues
   - Use `-ExecutionPolicy Bypass` to avoid execution policy restrictions
   - For complex commands, test with simple commands first

3. **Common Errors**
   - `Ampersand not allowed`: Ensure proper quoting around commands
   - `Unexpected token`: Check for unescaped special characters
   - `Cannot bind parameter`: Verify parameter names and values are correct

4. **Date/Time Issues**
   - Check server time: `ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-Date; [DateTime]::UtcNow"'`
   - Verify timezone: `ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'powershell -Command "Get-TimeZone"'`

## Best Practices

1. Always test commands without `-Execute` first to see what would be deleted
2. Use `-Verbose` for detailed logging
3. The script now handles empty log messages gracefully
4. Improved error handling and progress reporting
5. All file operations are logged with timestamps
3. For long-running commands, consider using `screen` or `tmux`
4. Keep the SSH key secure and never share it
5. Document any custom commands in this file for future reference
   - Use full path to PowerShell if needed
   - Add `-NoProfile` to avoid loading profile scripts
   - Use `-ExecutionPolicy Bypass` to avoid execution policy restrictions

3. **Path Issues**
   - Use double backslashes (`\\`) for Windows paths in commands
   - Enclose paths with spaces in single quotes within the PowerShell command

## Example: Full Script Execution (v2)

```bash
# 1. Switch to the v2 branch
git checkout v2

# 2. Copy the script to the server
scp -i ~/.ssh/id_rsa_windows ArchiveRetention.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/'

# 3. Dry run (no changes)
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 120 -Verbose }"'

# 4. Actual execution (with -Execute parameter)
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 120 -Execute -Verbose }"'
```

## Notes

- The server uses Windows authentication with SSH keys
- PowerShell commands need to be properly escaped when run through SSH
- For complex commands, consider creating a script on the server and executing it
- Logs are typically written to the script's directory or the Windows Event Log
