# IDE Quick Reference: LogRhythm Archive Retention

## 🔐 Server Connection
```bash
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200
```

---

## 📂 File Operations

### Copy Script to Server
```bash
scp -i ~/.ssh/id_rsa_windows ArchiveRetention.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/'
```

### Run Script

#### 🧪 Dry Run (no deletion)
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 20 -Verbose }"'
```

#### 🔥 Execute (deletion enforced)
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -ArchivePath ''D:\LogRhythmArchives\InactiveTest'' -RetentionDays 20 -Execute -Verbose }"'
```
> ❗ If `RetentionDays < 90`, the script enforces 90 days and logs a warning.

---

## 📁 Network Share with Credential Target

### 1️⃣ Save Credentials (interactive)
```powershell
.\Save-Credential.ps1 -Target "NAS" -SharePath "\\10.20.1.7\LRArchives"
```

### 2️⃣ Use Credentials
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd ''C:\LogRhythm\Scripts\ArchiveV2''; .\ArchiveRetention.ps1 -CredentialTarget ''10.20.1.7'' -RetentionDays 180 -Execute }"'
```

---

## 🛠 Common Tasks

### List Oldest Files (Top 5)
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -Command "Get-ChildItem -Path ''D:\LogRhythmArchives\InactiveTest'' -Recurse -File | Sort-Object LastWriteTime | Select-Object -First 5 FullName, LastWriteTime, @{Name=''DaysOld'';Expression={[math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 2)}} | Format-Table -AutoSize"'
```

### View Recent Log Entries
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 \
  'powershell -Command "Get-Content -Tail 20 ''C:\LogRhythm\Scripts\ArchiveV2\ArchiveRetention.log''"'
```

---

## 🧯 Troubleshooting

### Connectivity
```bash
ping 10.20.1.200
ssh -i ~/.ssh/id_rsa_windows administrator@10.20.1.200 'hostname'
chmod 600 ~/.ssh/id_rsa_windows  # Ensure key has correct permissions
```

### Common Errors
- `Ampersand not allowed` → Fix quoting
- `Unexpected token` → Check special characters
- `Cannot bind parameter` → Validate names/values

---

## 🔧 Git Operations
```bash
git add .
git commit -m "Update script with improved error handling"
git status
```

---

## 🧾 Naming Conventions

- **Markdown**: `lower-case-with-dashes.md` (e.g., `system-overview.md`)  
  _Exception_: `README.md` in project root

- **Bash**: `lower_case_with_underscores.sh` (e.g., `sync_files.sh`)  
- **PowerShell**: `PascalCase.ps1` (e.g., `StartBackup.ps1`)  
  ➤ Rename existing `.ps1` files to match PascalCase