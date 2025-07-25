# Quick Start Guide - 5 Minutes to Production

![Version](https://img.shields.io/badge/version-2.3.21-blue.svg)
![Platform](https://img.shields.io/badge/platform-windows-lightgrey.svg)

Get the LogRhythm Archive Retention Manager running in production in just 5 minutes.

## 📋 Prerequisites

- Windows Server 2016+ or Windows 10+
- PowerShell 5.1+ (Administrator access)
- Access to LogRhythm archive directories

## ⚡ 5-Minute Setup

### Step 1: Install (2 minutes)

1. **Download** the Production Package from [GitHub Releases](https://github.com/paraserv/LRArchiveRetention/releases)
2. **Extract** to `C:\LogRhythm\Scripts\LRArchiveRetention\`
3. **Open PowerShell as Administrator**
4. **Navigate** to the installation directory:
   ```powershell
   cd "C:\LogRhythm\Scripts\LRArchiveRetention"
   ```

### Step 2: Save Credentials (1 minute)

For network shares, save credentials once:

```powershell
# Replace with your actual server and share path
.\Save-Credential.ps1 -CredentialTarget "PROD_NAS" -SharePath "\\server\share"
```

**Enter your credentials when prompted.** They'll be securely encrypted and stored.

### Step 3: Test Run (1 minute)

**Always test first** with a dry run:

```powershell
# Test 15-month retention (456 days) - SAFE, no files deleted
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456
```

**Review the output** to ensure it finds the expected files.

### Step 4: Execute (1 minute)

If the test looks correct, **execute the deletion**:

```powershell
# Actually delete files older than 456 days
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -Execute
```

## 🎯 Common Use Cases

### Local Archives
```powershell
# Local directory - 2 year retention
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 730 -Execute
```

### Scheduled Automation
```powershell
# Create scheduled task (monthly execution)
.\CreateScheduledTask.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -ScheduleType Monthly
```

### High-Performance Mode
```powershell
# Enable parallel processing for large datasets
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -ParallelProcessing -Execute
```

## 📊 Common Retention Periods

| Business Need | Days | Command |
|---------------|------|---------|
| **Minimum Compliance** | 90 | `-RetentionDays 90` |
| **Standard Production** | 456 | `-RetentionDays 456` |
| **Extended Compliance** | 730 | `-RetentionDays 730` |
| **Long-term Archive** | 1095 | `-RetentionDays 1095` |

## 🔒 Safety Features

- **Dry-run by default** - No files deleted without `-Execute`
- **90-day minimum** - Cannot delete files newer than 90 days
- **Single instance** - Prevents multiple scripts running simultaneously
- **Comprehensive logging** - All actions logged to `script_logs/`

## 🚨 Important Notes

### Before First Use
1. **Always run without `-Execute` first** to preview changes
2. **Verify the file list** matches your expectations
3. **Check available disk space** if processing large datasets
4. **Review logs** in `script_logs/ArchiveRetention.log`

### Production Deployment
- **Test in non-production** environment first
- **Schedule during maintenance windows** for large deletions
- **Monitor disk space** during execution
- **Keep audit logs** for compliance requirements

## 📈 Expected Performance

| Environment | Scan Rate | Delete Rate | Memory Usage |
|-------------|-----------|-------------|--------------|
| **Local SSD** | 5,000+ files/sec | 100+ files/sec | ~10 MB |
| **Network Share** | 1,600+ files/sec | 35+ files/sec | ~10 MB |
| **Large Dataset** | Constant rate | Parallel processing | Constant |

## 🔧 Troubleshooting

### Common Issues

**"Another instance is running"**
```powershell
# Clear orphaned lock file
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -ForceClearLock
```

**"No credential found"**
```powershell
# Re-save credentials
.\Save-Credential.ps1 -CredentialTarget "PROD_NAS" -SharePath "\\server\share"
```

**"Access denied"**
- Ensure PowerShell is running as Administrator
- Verify account has delete permissions on target directories
- Check network connectivity to shares

### Get Help

1. **Verbose output**: Add `-Verbose` to any command
2. **Check logs**: Review `script_logs/ArchiveRetention.log`
3. **Documentation**: See [Installation Guide](installation.md) for detailed setup
4. **Command reference**: See [Command Reference](command-reference.md) for all options

## ✅ Success Checklist

- [ ] Downloaded and extracted Production Package
- [ ] Saved credentials (if using network shares)
- [ ] Ran successful dry-run test
- [ ] Reviewed output and logs
- [ ] Executed with `-Execute` flag
- [ ] Verified expected files were deleted
- [ ] Set up scheduled task (optional)

## 🚀 Next Steps

- **Automate**: Set up scheduled tasks for regular execution
- **Monitor**: Review logs regularly for any issues
- **Optimize**: Enable parallel processing for large datasets
- **Scale**: Deploy to multiple servers as needed

---

**Need more help?** See the complete [Installation Guide](installation.md) or [Command Reference](command-reference.md).

**Version**: 2.3.21 | **Updated**: July 2025
