# WinRM Setup for LRArchiveRetention Testing

## Overview

This document explains how to set up WinRM (Windows Remote Management) connectivity for testing the LRArchiveRetention tools on Windows Server VMs.

## 🔐 Security Setup (Required First)

**IMPORTANT**: Before using any WinRM connections, you must store the Windows service account credentials in your macOS keychain for security.

### Store Windows Credentials in Keychain

```bash
# Store Windows service account password in keychain (run once)
security add-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w

# You will be prompted to enter the password securely
# This credential will be used for all WinRM connections
```

### Verify Credential Storage

```bash
# Verify the credential is stored (will show account info but not password)
security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM"

# Test password retrieval (this should output the password)
security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w
```

> **Security Note**: This approach ensures passwords are never hardcoded in scripts or documentation and are stored securely in your system's keychain with proper encryption.

## Prerequisites

- Python 3.8 or later
- Access to Windows Server with WinRM enabled
- Kerberos configuration for domain authentication

## Python Environment Setup

### 1. Create Virtual Environment

```bash
# Create a dedicated virtual environment for WinRM
python3 -m venv winrm_env

# Activate the environment
source winrm_env/bin/activate  # On macOS/Linux
# or
winrm_env\Scripts\activate     # On Windows
```

### 2. Install Required Packages

```bash
# Install WinRM and Kerberos support
pip install pywinrm pykerberos

# Optional: Install additional packages for testing
pip install requests urllib3
```

### 3. Verify Installation

```bash
python3 -c "
import winrm
print('pywinrm version:', winrm.__version__)
print('WinRM support: OK')
"
```

## Kerberos Configuration

### 1. Create `/etc/krb5.conf`

```ini
[libdefaults]
    default_realm = LAB.PARASERV.COM
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    LAB.PARASERV.COM = {
        kdc = addc.lab.paraserv.com
        admin_server = addc.lab.paraserv.com
        default_domain = lab.paraserv.com
    }

[domain_realm]
    .lab.paraserv.com = LAB.PARASERV.COM
    lab.paraserv.com = LAB.PARASERV.COM
```

### 2. Get Kerberos Ticket

```bash
# Get authentication ticket (password retrieved from keychain)
echo "$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)" | kinit svc_logrhythm@LAB.PARASERV.COM

# Verify ticket
klist
```

## WinRM Connection Testing

### 1. Basic Connection Test

```python
import winrm
import os
import subprocess

# Get password from keychain
def get_windows_password():
    result = subprocess.run([
        'security', 'find-internet-password',
        '-s', 'windev01.lab.paraserv.com',
        '-a', 'svc_logrhythm@LAB.PARASERV.COM',
        '-w'
    ], capture_output=True, text=True)
    return result.stdout.strip()

# Create WinRM session
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                       transport='kerberos',
                       server_cert_validation='ignore')

# Test basic command
result = session.run_cmd('hostname')
print(f'Connected to: {result.std_out.decode().strip()}')
```

### 2. PowerShell Command Test

```python
# Test PowerShell execution
result = session.run_ps('$PSVersionTable.PSVersion')
print(f'PowerShell version: {result.std_out.decode().strip()}')

# Test session persistence
session.run_ps('$testVar = "Hello from WinRM"')
result = session.run_ps('$testVar')
print(f'Session test: {result.std_out.decode().strip()}')
```

## Environment Management

### 1. Activation Script

Create `activate_winrm.sh`:

```bash
#!/bin/bash
# Activate WinRM environment for LRArchiveRetention testing

echo "Activating WinRM environment..."
source winrm_env/bin/activate

echo "Getting Kerberos ticket..."
echo "$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)" | kinit svc_logrhythm@LAB.PARASERV.COM

echo "Verifying ticket..."
klist

echo "Ready for WinRM operations!"
```

### 2. Test Script

Create `test_winrm.py`:

```python
#!/usr/bin/env python3
"""
Test WinRM connectivity to Windows Server
"""
import winrm
import sys

def test_winrm_connection():
    try:
        # Create session
        session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                               auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                               transport='kerberos',
                               server_cert_validation='ignore')

        # Test basic command
        result = session.run_cmd('hostname')
        hostname = result.std_out.decode().strip()
        print(f"✅ Connected to: {hostname}")

        # Test PowerShell
        result = session.run_ps('$PSVersionTable.PSVersion')
        ps_version = result.std_out.decode().strip()
        print(f"✅ PowerShell version: {ps_version}")

        # Test session persistence
        session.run_ps('$testVar = "WinRM Session Test"')
        result = session.run_ps('$testVar')
        test_result = result.std_out.decode().strip()
        print(f"✅ Session persistence: {test_result}")

        print("✅ WinRM connection test successful!")
        return True

    except Exception as e:
        print(f"❌ WinRM connection test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_winrm_connection()
    sys.exit(0 if success else 1)
```

## Troubleshooting

### Common Issues

1. **Import Error: No module named 'winrm'**
   - Solution: Ensure virtual environment is activated and packages are installed

2. **Kerberos Authentication Failed**
   - Solution: Check `/etc/krb5.conf` configuration and get fresh ticket with `kinit`

3. **Certificate Validation Error**
   - Solution: Use `server_cert_validation='ignore'` for self-signed certificates

4. **Connection Timeout**
   - Solution: Verify Windows Server has WinRM enabled and firewall allows port 5986

### Debugging Commands

```bash
# Check virtual environment
which python3
pip list | grep winrm

# Check Kerberos ticket
klist

# Test network connectivity
nc -zv windev01.lab.paraserv.com 5986
```

## Notes

- The `winrm_env/` directory is excluded from git via `.gitignore`
- Virtual environment should be recreated on each development machine
- Kerberos tickets expire after 24 hours and need renewal
- WinRM sessions provide better performance than SSH for PowerShell operations

## Related Documentation

- [Windows VM Connectivity Guide](windows-vm-connectivity.md)
- [Testing Summary](../tests/TESTING_SUMMARY.md)
- [Execution Mode Explanation](../tests/EXECUTION_MODE_EXPLANATION.md)
