# Project Structure

This document outlines the organization and structure of the LogRhythm Archive Retention Manager project.

## 📁 Repository Layout

```
LRArchiveRetention/
├── README.md                    # Main project documentation
├── CHANGELOG.md                 # Version history and release notes
├── VERSION                      # Current version (semantic versioning)
├── CLAUDE.md                    # Claude Code AI guidance
├── IMPROVEMENTS_TODO.md         # Development roadmap and status
│
├── ArchiveRetention.ps1         # Main retention script
├── Save-Credential.ps1          # Credential management utility
├── CreateScheduledTask.ps1      # Task automation helper
├── winrm_helper.py             # Remote operations utility
├── requirements.txt            # Python dependencies
│
├── modules/                     # PowerShell modules
│   └── ShareCredentialHelper.psm1
│
├── docs/                       # Comprehensive documentation
│   ├── PROJECT_STRUCTURE.md    # This file
│   ├── credentials.md          # Credential management guide
│   ├── scheduled-task-setup.md # Automation setup
│   ├── WINRM_SETUP.md         # Remote access configuration
│   ├── pre-commit-security-setup.md # Security framework
│   ├── windows-vm-connectivity.md   # Network setup
│   ├── LEGACY_README.md        # Historical documentation
│   └── LICENSE                 # License information
│
├── tests/                      # Testing framework
│   ├── GenerateTestData.ps1
│   └── RunArchiveRetentionTests.sh
│
├── script_logs/               # Runtime logs (auto-created)
├── retention_actions/         # Audit logs (auto-created)
├── CredentialStore/          # Encrypted credentials (auto-created)
│
└── winrm_env/                # Python virtual environment
    ├── bin/
    ├── lib/
    └── ...
```

## 📚 Documentation Hierarchy

### Primary Documentation
1. **[README.md](../README.md)** - Main entry point for users
2. **[CHANGELOG.md](../CHANGELOG.md)** - Version history and migration notes
3. **[CLAUDE.md](../CLAUDE.md)** - AI-assisted development guidance

### Technical Guides
4. **[credentials.md](credentials.md)** - Secure credential management
5. **[scheduled-task-setup.md](scheduled-task-setup.md)** - Automation configuration
6. **[WINRM_SETUP.md](WINRM_SETUP.md)** - Remote access setup
7. **[pre-commit-security-setup.md](pre-commit-security-setup.md)** - Security framework

### Utility Documentation
8. **[README_winrm_helper.md](../README_winrm_helper.md)** - Remote operations utility
9. **[IMPROVEMENTS_TODO.md](../IMPROVEMENTS_TODO.md)** - Development roadmap

### Legacy Documentation
10. **[LEGACY_README.md](LEGACY_README.md)** - Historical reference

## 🏗️ Core Components

### Primary Scripts
- **ArchiveRetention.ps1**: Main retention engine with enterprise features
- **Save-Credential.ps1**: Secure credential storage and management
- **CreateScheduledTask.ps1**: Automated task creation and configuration

### Support Utilities
- **winrm_helper.py**: Python utility for reliable remote operations
- **ShareCredentialHelper.psm1**: PowerShell module for credential management

### Testing Framework
- **GenerateTestData.ps1**: Test data creation for validation
- **RunArchiveRetentionTests.sh**: Automated test execution suite

## 📋 File Naming Conventions

### PowerShell Scripts
- **PascalCase** for main scripts (e.g., `ArchiveRetention.ps1`)
- **Descriptive names** indicating primary function
- **.ps1** extension for executable scripts
- **.psm1** extension for modules

### Documentation
- **UPPERCASE** for primary documentation (e.g., `README.md`, `CHANGELOG.md`)
- **kebab-case** for technical guides (e.g., `scheduled-task-setup.md`)
- **.md** extension for Markdown files

### Python Files
- **snake_case** for Python utilities (e.g., `winrm_helper.py`)
- **Descriptive names** indicating functionality

### Directories
- **lowercase** for generated directories (e.g., `script_logs/`)
- **PascalCase** for manually created directories (e.g., `CredentialStore/`)

## 🔄 Version Management

### Semantic Versioning
- **VERSION** file contains current version (e.g., `2.0.0`)
- **CHANGELOG.md** documents all changes with version history
- **Scripts dynamically read** version from VERSION file

### Version Format
- **MAJOR.MINOR.PATCH** (e.g., 2.0.0)
- **MAJOR**: Breaking changes or major feature additions
- **MINOR**: New features with backward compatibility
- **PATCH**: Bug fixes and minor improvements

### Release Process
1. Update VERSION file
2. Document changes in CHANGELOG.md
3. Update version references in documentation
4. Tag release in git
5. Update deployment documentation

## 🛡️ Security Structure

### Credential Storage
- **CredentialStore/**: Encrypted credential files (auto-created)
- **Machine-bound encryption**: AES-256 or DPAPI
- **Restricted permissions**: Automatic security validation

### Audit Logging
- **script_logs/**: Operational logs with rotation
- **retention_actions/**: Compliance audit trails
- **Complete traceability**: All operations logged

### Security Framework
- **Pre-commit hooks**: Automatic credential detection
- **Permission validation**: Secure directory creation
- **Access controls**: User and group restrictions

## 🔧 Runtime Directories

### Auto-Created Directories
These directories are created automatically during script execution:

- **script_logs/**: Main operational logs
  - `ArchiveRetention.log` (current log)
  - `ArchiveRetention_YYYYMMDD_HHMMSS.log` (archived logs)

- **retention_actions/**: Audit compliance logs
  - `retention_YYYYMMDD_HHMMSS.log` (deletion records)

- **CredentialStore/**: Encrypted credential storage
  - `{TargetName}.cred` (encrypted credential files)

### Virtual Environment
- **winrm_env/**: Python virtual environment for remote operations
  - Self-contained Python packages
  - Isolated from system Python installation

## 📊 Log Organization

### Log Types
1. **Operational Logs**: Day-to-day script execution
2. **Audit Logs**: Compliance and retention records
3. **Debug Logs**: Detailed troubleshooting information
4. **Performance Logs**: Timing and throughput metrics

### Log Rotation
- **Automatic rotation**: Prevents disk space issues
- **Timestamped archives**: Historical reference maintained
- **Configurable retention**: Customizable log retention periods

## 🤝 Development Workflow

### Code Organization
- **Single responsibility**: Each script has a clear, focused purpose
- **Modular design**: Reusable components in separate modules
- **Clear interfaces**: Well-defined parameters and return values

### Documentation Standards
- **Comprehensive README**: Clear setup and usage instructions
- **Inline documentation**: Well-commented code throughout
- **Change tracking**: Detailed CHANGELOG with migration notes
- **API documentation**: Parameter descriptions and examples

### Testing Strategy
- **Automated testing**: Comprehensive test suite
- **Production validation**: Real-world dataset testing
- **Performance benchmarking**: Metrics collection and analysis
- **Security validation**: Credential and permission testing

## 🎯 Design Principles

### Reliability
- **Error handling**: Comprehensive exception management
- **Recovery mechanisms**: Automatic retry and fallback logic
- **Validation**: Input and state validation throughout

### Security
- **Credential protection**: Encrypted storage with machine binding
- **Access control**: Restricted permissions and validation
- **Audit trails**: Complete operation logging

### Performance
- **Efficient algorithms**: Optimized file enumeration and processing
- **Progress monitoring**: Real-time feedback and ETA calculations
- **Resource management**: Memory and disk space optimization

### Maintainability
- **Clear structure**: Logical organization and naming
- **Documentation**: Comprehensive guides and references
- **Version control**: Semantic versioning and change tracking
- **Testing**: Automated validation and quality assurance
