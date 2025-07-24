# LogRhythm Archive Retention Manager

![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)
![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-windows-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

Enterprise-grade PowerShell solution for automated cleanup of LogRhythm Inactive Archive files (.lca) with secure credential management and production-validated reliability.

## 🚀 Quick Start

```powershell
# Dry-run (safe preview mode)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456

# Execute deletion (15-month retention)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 456 -Execute

# Network share with saved credentials
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095 -Execute
```

## ✨ Key Features

- **Production-Tested**: 95,558 files (4.67 TB) processed with 0% error rate
- **High Performance**: O(1) memory usage with streaming mode, 10-20x faster scanning
- **Secure Credentials**: AES-256/DPAPI encryption with machine binding
- **Safety First**: Dry-run by default, minimum 90-day retention enforcement
- **Enterprise Ready**: Comprehensive logging, scheduled task support, parallel processing

## 📋 Requirements

- Windows Server 2016+ or Windows 10+
- PowerShell 5.1+ (PowerShell 7+ recommended)
- Administrative access to archive directories

## 🛠️ Installation

```bash
# Clone repository
git clone <repository-url>
cd LRArchiveRetention

# For production deployment
Copy-Item -Path ".\*" -Destination "C:\LogRhythm\Scripts\LRArchiveRetention\" -Recurse
```

For detailed setup instructions, see [Installation Guide](docs/installation.md).

## 📊 Performance

| Metric | Value | Version |
|--------|-------|---------|
| **Files Processed** | 95,558 (4.67 TB) | v2.2.0 |
| **Scan Rate** | 1,600 files/sec | v2.1.0+ |
| **Delete Rate** | 35 files/sec (network) | All |
| **Memory Usage** | 10 MB constant | v2.2.0+ |
| **Parallel Speedup** | 4-8x | v1.2.0+ |

See [Performance Benchmarks](docs/performance-benchmarks.md) for detailed metrics.

## 🔧 Common Usage

### Basic Operations

```powershell
# Local path with progress
.\ArchiveRetention.ps1 -ArchivePath "C:\Archives" -RetentionDays 730 -ShowDeleteProgress

# Quiet mode for scheduled tasks
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 456 -QuietMode -Execute
```

### Network Performance

```powershell
# Enable parallel processing (4-8x faster)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 365 `
  -ParallelProcessing -ThreadCount 8 -Execute
```

### Save Credentials

```powershell
# Interactive credential setup
.\Save-Credential.ps1 -Target "NAS_PROD" -SharePath "\\server\share"
```

For complete command reference, see [Command Reference](docs/command-reference.md).

## 📖 Documentation

| Guide | Description |
|-------|-------------|
| [Installation](docs/installation.md) | Complete setup and deployment guide |
| [Command Reference](docs/command-reference.md) | All commands and parameters |
| [Performance](docs/performance-benchmarks.md) | Benchmarks and optimization |
| [Credentials](docs/credentials.md) | Secure credential management |
| [Scheduled Tasks](docs/scheduled-task-setup.md) | Automation configuration |
| [CLAUDE.md](CLAUDE.md) | AI assistant context |

### Additional Resources

- [CHANGELOG.md](CHANGELOG.md) - Version history
- [IMPROVEMENTS_TODO.md](IMPROVEMENTS_TODO.md) - Roadmap and known issues
- [Technical Architecture](docs/PROJECT_STRUCTURE.md) - Codebase organization

## 🚨 Safety Features

- **Dry-Run Default**: Preview changes before execution
- **Minimum Retention**: 90-day hardcoded safety limit
- **Single Instance**: Prevents concurrent execution
- **Audit Logging**: Complete deletion records for compliance

## 🏗️ Architecture Overview

```
ArchiveRetention.ps1          # Main retention engine
├── Save-Credential.ps1       # Credential management
├── ShareCredentialHelper.psm1 # Credential module
├── CreateScheduledTask.ps1   # Task automation
└── winrm_helper.py          # Remote operations
```

## 🔒 Security

- Pre-commit hooks for credential detection
- Machine-bound encryption keys
- Secure credential storage (DPAPI/AES-256)
- Comprehensive audit logging

See [Security Setup](docs/pre-commit-security-setup.md) for details.

## 📈 Common Retention Periods

| Period | Days | Use Case |
|--------|------|----------|
| 3 months | 90 | Minimum allowed |
| 15 months | 456 | Common production |
| 2 years | 730 | Compliance standard |
| 3 years | 1095 | Long-term retention |

## 🤝 Support

1. Check [CLAUDE.md](CLAUDE.md) for detailed examples
2. Review logs in `script_logs/ArchiveRetention.log`
3. See [Troubleshooting](docs/installation.md#troubleshooting)
4. Use `-Verbose` flag for detailed output

## 📜 License

MIT License - See [LICENSE](LICENSE) file

---

**Current Version**: 2.2.0 | **Updated**: July 2025