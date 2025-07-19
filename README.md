# LogRhythm Archive Retention Manager

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-windows-lightgrey.svg)
![License](https://img.shields.io/badge/license-proprietary-red.svg)

Enterprise-grade PowerShell solution for automated cleanup of LogRhythm Inactive Archive files (.lca) with comprehensive network share support, secure credential management, and production-validated reliability.

## 🚀 Quick Start

```powershell
# Dry-run (safe preview mode)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456

# Execute actual deletion (15-month retention)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456 -Execute

# Network share with saved credentials
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095 -Execute
```

## ✨ Key Features

### Production-Validated Performance
- **Large-Scale Tested**: 95,558 files (4.67 TB) processed with 0% error rate
- **High Performance**: 2,074 files/sec scanning, 35 files/sec deletion
- **Enterprise Reliability**: Production-validated on network shares

### Advanced Operations
- 🔒 **Secure Credential Management**: AES-256/DPAPI encryption with machine binding
- 📊 **Real-Time Monitoring**: Configurable progress intervals and live counters
- 🔄 **Automatic Recovery**: Lock file cleanup and stale process detection
- 📝 **Comprehensive Auditing**: Complete retention action logs for compliance

### Safety & Compliance
- 🛡️ **Dry-Run Mode**: Default safe preview before any deletions
- ⏰ **Minimum Retention**: Hardcoded 90+ day safety enforcement
- 🔐 **Single-Instance Lock**: Prevents concurrent execution conflicts
- 📋 **Audit Logging**: Complete trail of all retention actions

## 📊 Performance Benchmarks

| Operation | Rate | Notes |
|-----------|------|-------|
| **File Scanning** | 2,074 files/sec | Metadata enumeration |
| **File Deletion** | 35 files/sec | Network operations |
| **Large Dataset** | 4.67 TB in 45 min | Production validated |
| **Error Rate** | 0% | 95,558+ operations |

## 🛠️ Installation & Setup

### Prerequisites
- Windows Server 2016+ or Windows 10+
- PowerShell 5.1+ (PowerShell 7+ recommended)
- Network access to target archive locations
- Appropriate permissions on archive directories

### Quick Setup
```bash
# Clone repository
git clone <repository-url>
cd LRArchiveRetention

# For remote operations, setup WinRM helper
source winrm_env/bin/activate
python3 -m pip install -r requirements.txt
```

### Network Credentials (Optional)
```powershell
# Save network credentials securely
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share"

# Verify saved credentials
Import-Module .\modules\ShareCredentialHelper.psm1
Get-SavedCredentials
```

## 📖 Documentation

### Core Documentation
- **[CLAUDE.md](CLAUDE.md)** - Comprehensive setup and operation guide
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and migration notes
- **[docs/](docs/)** - Detailed technical documentation

### Quick References
- **[winrm_helper.py Guide](README_winrm_helper.md)** - Remote operations utility
- **[Improvements Roadmap](IMPROVEMENTS_TODO.md)** - Feature development status

### Technical Guides
- **[Network Credentials](docs/credentials.md)** - Secure credential management
- **[Scheduled Tasks](docs/scheduled-task-setup.md)** - Automation setup
- **[WinRM Setup](docs/WINRM_SETUP.md)** - Remote access configuration

## 🔧 Usage Examples

### Basic Operations
```powershell
# Local path dry-run with progress monitoring
.\ArchiveRetention.ps1 -ArchivePath "C:\Archives" -RetentionDays 730 -ShowScanProgress

# Network share with quiet mode (ideal for automation)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" -RetentionDays 456 -QuietMode -Execute
```

### Advanced Monitoring
```powershell
# Real-time progress with custom intervals
.\ArchiveRetention.ps1 -ArchivePath "\\nas\archives" -RetentionDays 1095 `
  -ShowScanProgress -ShowDeleteProgress -ProgressInterval 10
```

### Remote Operations (Recommended)
```bash
# Using WinRM helper for reliable remote execution
source winrm_env/bin/activate

# Dry-run test
python3 winrm_helper.py nas_dry_run 456

# Production execution
python3 winrm_helper.py nas_execute 456
```

## 🏗️ Architecture

### Core Components
- **ArchiveRetention.ps1** - Main retention engine
- **Save-Credential.ps1** - Secure credential storage
- **ShareCredentialHelper.psm1** - Credential management module
- **winrm_helper.py** - Remote operations utility

### Security Model
- **Credential Encryption**: AES-256 (cross-platform) or DPAPI (Windows)
- **Machine Binding**: Hardware-derived encryption keys
- **Access Control**: Restricted permissions on credential storage
- **Audit Trail**: Complete logging of all operations

### Safety Features
- **Default Dry-Run**: Requires explicit `-Execute` flag
- **Minimum Retention**: 90+ day hardcoded enforcement
- **Parameter Validation**: Comprehensive input validation
- **Single Instance**: Prevents concurrent execution conflicts

## 📈 Production Deployment

### Recommended Setup
1. **Deploy Scripts**: Place in secure directory (e.g., `C:\LogRhythm\Scripts\`)
2. **Configure Credentials**: Use `Save-Credential.ps1` for network shares
3. **Test Thoroughly**: Always test with dry-run mode first
4. **Schedule Tasks**: Use `CreateScheduledTask.ps1` for automation
5. **Monitor Operations**: Review logs and performance metrics

### Monitoring & Maintenance
- **Log Location**: `script_logs/ArchiveRetention.log` (auto-rotating)
- **Audit Trail**: `retention_actions/retention_*.log` (compliance logs)
- **Performance**: Built-in timing and throughput metrics
- **Health Checks**: Automatic credential validation and testing

## 🔒 Security & Compliance

### Security Features
- **Pre-commit Hooks**: Automatic credential detection and blocking
- **Secure Storage**: Machine-bound credential encryption
- **Audit Logging**: Complete operation tracking
- **Permission Validation**: Automatic security verification

### Compliance Support
- **Retention Records**: Complete audit trail of deleted files
- **Date Validation**: Accurate retention period calculations
- **Error Tracking**: Detailed failure analysis and reporting
- **Configuration Logging**: All script parameters recorded

## 🤝 Contributing

This is a production system with rigorous testing requirements:

1. **All changes must pass pre-commit security hooks**
2. **Test thoroughly in non-production environment**
3. **Update documentation for any new features**
4. **Follow semantic versioning for releases**

## 📞 Support

### Troubleshooting
1. Check [CLAUDE.md](CLAUDE.md) for comprehensive setup instructions
2. Review [IMPROVEMENTS_TODO.md](IMPROVEMENTS_TODO.md) for known issues
3. Examine script logs for detailed error information
4. Use `winrm_helper.py` for reliable remote operations

### Performance Issues
- **Slow Operations**: Check network connectivity and share performance
- **Lock File Errors**: Use automatic cleanup in `winrm_helper.py`
- **Authentication Failures**: Verify credentials with `Get-SavedCredentials`

---

## 📜 Version Information

**Current Version**: 2.0.0
**Release Date**: July 19, 2025
**Compatibility**: PowerShell 5.1+, Windows Server 2016+

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and migration notes.
