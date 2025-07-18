# Pre-Commit Security Setup

This document explains how to set up pre-commit hooks to prevent credential exposure and maintain security standards in the LRArchiveRetention project.

## 🔐 Overview

The pre-commit security system includes:
- **General credential scanner** - Detects hardcoded passwords, API keys, and secrets
- **PowerShell-specific scanner** - Identifies PowerShell credential anti-patterns
- **Documentation scanner** - Prevents credential exposure in markdown files
- **detect-secrets integration** - Industry-standard secret detection

## 📋 Prerequisites

- Python 3.8 or later
- Git repository
- macOS (for keychain integration)

## 🚀 Setup Instructions

### 1. Install Pre-Commit

```bash
# Install pre-commit
pip install pre-commit

# Install detect-secrets for advanced secret detection
pip install detect-secrets
```

### 2. Initialize Pre-Commit in Repository

```bash
# Navigate to project root
cd /path/to/LRArchiveRetention

# Install the git hook scripts
pre-commit install

# Install commit-msg hook (optional, for commit message validation)
pre-commit install --hook-type commit-msg
```

### 3. Generate Secrets Baseline

```bash
# Generate initial secrets baseline (excludes known safe patterns)
detect-secrets scan --baseline .secrets.baseline

# Review and update baseline if needed
detect-secrets audit .secrets.baseline
```

### 4. Test the Setup

```bash
# Run pre-commit on all files to test
pre-commit run --all-files

# Test with a specific file
pre-commit run --files path/to/test-file.ps1
```

## 🛡️ Security Checks Performed

### General Credential Scanner (`check-credentials.sh`)
- Hardcoded passwords in various formats
- Windows/Active Directory credential patterns
- Connection strings with embedded passwords
- API keys and access tokens
- SSH/RSA private keys
- URLs with embedded credentials
- Environment variables with secrets

### PowerShell Scanner (`check-powershell-secrets.sh`)
- `New-Object PSCredential` with hardcoded passwords
- `ConvertTo-SecureString -AsPlainText -Force` usage
- Direct `-Password` parameter usage
- Insecure credential storage patterns
- WinRM/PSSession credential embedding
- Registry credential storage

### Documentation Scanner (`check-docs-credentials.sh`)
- Credential examples that might be real
- Connection strings in documentation
- API keys in code examples
- SSH keys in markdown
- Command-line examples with passwords
- Forbidden credential strings

### Detect-Secrets Integration
- Entropy-based detection
- Keyword-based detection
- Regular expression patterns
- Base64 encoded secrets
- Custom plugin support

## 🔧 Configuration

### Excluded Files and Patterns

The pre-commit configuration excludes:
- `.git/` directories
- `node_modules/` directories
- `.venv/` virtual environments
- `.secrets.baseline` file itself
- Test expected output files
- Lock files

### Custom Configuration

Edit `.pre-commit-config.yaml` to:
- Add new file patterns
- Exclude additional directories
- Modify security check parameters
- Add new security hooks

## ⚠️ Common Issues and Solutions

### False Positives

If legitimate code triggers false positives:

1. **For detect-secrets:**
   ```bash
   # Add to baseline after verification it's safe
   detect-secrets scan --baseline .secrets.baseline --update
   ```

2. **For custom scanners:**
   - Update the acceptable patterns in the respective script
   - Add `# nosec` comments for specific lines (if implemented)

### Script Permissions

If you get permission errors:
```bash
chmod +x scripts/*.sh
```

### Missing Dependencies

If pre-commit fails:
```bash
# Reinstall pre-commit environment
pre-commit clean
pre-commit install
```

## 🎯 Best Practices

### Credential Management
1. **Use macOS Keychain:**
   ```bash
   security add-internet-password -s "server.domain.com" -a "username" -w
   ```

2. **Reference keychain in scripts:**
   ```bash
   PASSWORD=$(security find-internet-password -s "server" -a "user" -w)
   ```

3. **PowerShell credential patterns:**
   ```powershell
   # Good: Use Save-Credential.ps1 with -UseStdin
   echo "password" | .\Save-Credential.ps1 -Target "NAS" -UseStdin

   # Bad: Hardcoded credentials
   $credential = New-Object PSCredential("user", "password")
   ```

### Documentation Practices
1. Use placeholder values: `YOUR_PASSWORD`, `<PASSWORD>`
2. Reference keychain retrieval methods
3. Include security warnings
4. Use example domains: `example.com`

### Development Workflow
1. Always run `pre-commit run --all-files` before major commits
2. Update `.secrets.baseline` when adding legitimate patterns
3. Review security violations carefully before bypassing
4. Rotate any accidentally committed credentials

## 🔍 Manual Security Audits

### Periodic Reviews
```bash
# Full repository scan
pre-commit run --all-files

# Specific file type scan
find . -name "*.ps1" -exec scripts/check-powershell-secrets.sh {} \;

# Update secrets baseline
detect-secrets scan --baseline .secrets.baseline --update
```

### Credential Rotation Schedule
- Review exposed credentials monthly
- Rotate service account passwords quarterly
- Update keychain entries as needed
- Audit baseline file for new patterns

## 📞 Support

If you encounter issues:
1. Check the specific script output for detailed error messages
2. Verify file permissions on scripts
3. Ensure all dependencies are installed
4. Review the `.pre-commit-config.yaml` configuration

For PowerShell-specific issues, refer to the secure credential patterns documented in the main project README.
