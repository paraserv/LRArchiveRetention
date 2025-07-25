# LogRhythm Archive Retention Manager v2.3.21

![Version](https://img.shields.io/badge/version-2.3.21-blue.svg)
![Platform](https://img.shields.io/badge/platform-windows-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**Release Date**: July 24, 2025  
**Production Ready**: ✅ Fully tested and validated

## 🚀 What's New in v2.3.21

### 🔧 Critical Fixes
- **Fixed timestamp regression in test data generation** - Files now properly aged for retention testing
- **Enhanced credential workflow** - Streamlined setup process for network shares
- **Improved documentation** - Comprehensive guides for quick deployment

### ✨ Key Improvements
- **5-minute Quick Start** - New streamlined setup process
- **Production packages** - Clean, minimal downloads for end users
- **Enhanced testing** - Proper test data generation with backdated timestamps

## 📦 Download Options

### 🎯 **Production Package** (Recommended for most users)
**File**: `LRArchiveRetention-v2.3.21-Production.zip`  
**Size**: ~150 KB  
**Contents**: Essential files only - ready to deploy

- ✅ Main retention script
- ✅ Credential management
- ✅ Scheduled task creation
- ✅ Essential documentation
- ✅ Quick Start guide

**Perfect for**: Production deployments, end users, quick setup

### 🛠️ **Complete Package** (For developers and advanced users)
**File**: `LRArchiveRetention-v2.3.21-Complete.zip`  
**Size**: ~2 MB  
**Contents**: All files including development tools

- ✅ Everything in Production Package
- ✅ Full test suite and generation tools
- ✅ Development documentation
- ✅ CI/CD integration files
- ✅ Performance benchmarking tools

**Perfect for**: Developers, contributors, advanced customization

## ⚡ Quick Setup (5 Minutes)

### Step 1: Download & Extract
```powershell
# Download Production Package and extract to:
C:\LogRhythm\Scripts\LRArchiveRetention\
```

### Step 2: Save Credentials
```powershell
.\Save-Credential.ps1 -CredentialTarget "PROD_NAS" -SharePath "\\server\share"
```

### Step 3: Test & Execute
```powershell
# Test first (safe)
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456

# Execute when ready
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -Execute
```

**📖 Complete guide**: See [Quick Start Guide](QUICK_START.md)

## 🔒 Security & Safety

- **Dry-run by default** - No files deleted without explicit `-Execute` flag
- **90-day minimum retention** - Hardcoded safety limit prevents accidental deletion
- **Secure credential storage** - AES-256/DPAPI encryption with machine binding
- **Comprehensive audit logging** - Complete deletion records for compliance
- **Single instance protection** - Prevents concurrent execution conflicts

## 📊 Production Performance

**Validated in production environments:**

| Metric | Performance | Environment |
|--------|-------------|-------------|
| **Files Processed** | 95,558 files (4.67 TB) | Production validation |
| **Error Rate** | 0% | Zero errors in testing |
| **Scan Rate** | 1,600+ files/sec | Network shares |
| **Delete Rate** | 35+ files/sec | Network operations |
| **Memory Usage** | ~10 MB constant | Large datasets |
| **Parallel Speedup** | 4-8x improvement | Multi-threaded mode |

## 🎯 Common Use Cases

### Standard Production Deployment
```powershell
# 15-month retention (common compliance requirement)
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -Execute
```

### High-Performance Mode
```powershell
# Enable parallel processing for large datasets
.\ArchiveRetention.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -ParallelProcessing -Execute
```

### Automated Scheduling
```powershell
# Create monthly scheduled task
.\CreateScheduledTask.ps1 -CredentialTarget "PROD_NAS" -RetentionDays 456 -ScheduleType Monthly
```

## 📋 System Requirements

### Minimum Requirements
- **OS**: Windows Server 2016+ or Windows 10+
- **PowerShell**: 5.1+ (PowerShell 7+ recommended)
- **Permissions**: Administrative access to archive directories
- **Network**: Access to target shares (if using network storage)

### Recommended Specifications
- **RAM**: 4+ GB available
- **Storage**: 100+ MB free space for logs
- **Network**: Gigabit connection for large datasets
- **CPU**: Multi-core for parallel processing

## 🔄 Upgrade Instructions

### From v2.3.x
1. **Backup** existing configuration and logs
2. **Download** new Production Package
3. **Extract** over existing installation
4. **Test** with existing credentials
5. **Resume** normal operations

### From v2.2.x or earlier
1. **Review** [Migration Guide](installation.md#migration)
2. **Update** credential storage format
3. **Test** thoroughly before production use

## 🐛 Bug Fixes in v2.3.21

### Critical Fixes
- **Timestamp regression**: Fixed test data generation creating files with current dates instead of backdated timestamps
- **Credential workflow**: Improved error handling in network share authentication
- **Documentation gaps**: Added missing setup steps and troubleshooting guides

### Performance Improvements
- **Memory optimization**: Reduced memory footprint for large file operations
- **Network efficiency**: Improved batch processing for remote shares
- **Error recovery**: Enhanced retry logic for transient network issues

## 🔗 Documentation & Support

### Essential Documentation
- **[Quick Start Guide](QUICK_START.md)** - 5-minute setup
- **[Installation Guide](installation.md)** - Comprehensive setup
- **[Command Reference](command-reference.md)** - All parameters and examples
- **[Performance Guide](performance-benchmarks.md)** - Optimization tips

### Getting Help
- **GitHub Issues**: Report bugs and request features
- **Documentation**: Comprehensive guides and examples
- **Logs**: Detailed logging in `script_logs/ArchiveRetention.log`
- **Verbose Mode**: Add `-Verbose` to any command for detailed output

## 🏆 Production Validation

This release has been thoroughly tested in production environments:

- ✅ **95,558 files processed** without errors
- ✅ **4.67 TB of data** successfully managed
- ✅ **Zero data loss** incidents
- ✅ **Comprehensive audit trails** maintained
- ✅ **Performance benchmarks** exceeded expectations

## 📈 Retention Period Reference

| Business Need | Days | Command Example |
|---------------|------|-----------------|
| **Minimum Compliance** | 90 | `-RetentionDays 90` |
| **Standard Production** | 456 | `-RetentionDays 456` |
| **Extended Compliance** | 730 | `-RetentionDays 730` |
| **Long-term Archive** | 1095 | `-RetentionDays 1095` |

## 🔮 What's Next

### Planned for v2.4.0
- **Enhanced monitoring** - Real-time performance dashboards
- **Multi-tenant support** - Isolated credential management
- **REST API integration** - Programmatic access and monitoring
- **Advanced scheduling** - Custom retention policies per directory

### Community Contributions
- **Feature requests** welcome via GitHub Issues
- **Pull requests** encouraged for improvements
- **Documentation** contributions appreciated

## 📜 License & Legal

**License**: MIT License - See [LICENSE](../LICENSE) file  
**Copyright**: 2025 LogRhythm Archive Retention Manager Contributors  
**Warranty**: Provided "as-is" without warranty of any kind

## 🎉 Thank You

Special thanks to all contributors, testers, and users who helped make this release possible. Your feedback and testing have been invaluable in ensuring production readiness.

---

**Download**: [GitHub Releases](https://github.com/paraserv/LRArchiveRetention/releases/tag/v2.3.21)  
**Documentation**: [Project Documentation](../README.md)  
**Support**: [GitHub Issues](https://github.com/paraserv/LRArchiveRetention/issues)

**Version**: 2.3.21 | **Release Date**: July 24, 2025
