# Windows VM Connectivity Guide

## Overview

This document provides step-by-step instructions for connecting to Windows Server VMs in the lab environment for testing the LRArchiveRetention tools.

## Lab Environment Details

### Network Configuration
- **Domain**: `lab.paraserv.com`
- **Domain Controller**: `addc.lab.paraserv.com (10.20.1.25)`
- **Development Server Range**: `10.20.1.20-49`
- **Production Server Range**: `10.20.1.150-199`

### Naming Convention
- **Development**: `windev{XX}` (e.g., windev01, windev02)
- **Production**: `winsrv{XX}` (e.g., winsrv01, winsrv02)

### Credentials
- **Service Account**: `svc_logrhythm@LAB.PARASERV.COM` (password stored in macOS keychain)
- **Local Administrator**: `Administrator` (password stored in macOS keychain)

> **Security Note**: Passwords are stored securely in macOS keychain. Use the following commands to store them:
> ```bash
> # Store service account password (run once)
> security add-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w
>
> # Store administrator password (run once)
> security add-internet-password -s "windev01.lab.paraserv.com" -a "Administrator" -w
> ```

## SSH Connectivity (Recommended)

### Prerequisites
- SSH key: `~/.ssh/windows_server` (should already exist)
- SSH service enabled on Windows Server

### SSH Configuration

Add this entry to `~/.ssh/config`:

```
Host windev01
    HostName 10.20.1.20
    User Administrator
    IdentityFile /Users/nathan/.ssh/windows_server
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel QUIET
```

### Testing SSH Connection

```bash
# Test basic connectivity
ssh windev01 "hostname"

# Test PowerShell execution
ssh windev01 'powershell -Command "Get-Host | Select-Object Name, Version"'

# Test directory access
ssh windev01 'powershell -Command "Get-ChildItem -Path C:\ -Directory | Select-Object Name"'
```

### Expected Results

```
# hostname command
windev01

# PowerShell version
Name        Version
----        -------
ConsoleHost 5.1.20348.3932

# Directory listing should show folders like: inetpub, LR, PerfLogs, etc.
```

## WinRM Connectivity (Recommended for Complex Operations)

### Prerequisites ✅ CONFIRMED WORKING
- Python virtual environment with pywinrm and pykerberos
- Kerberos configuration in `/etc/krb5.conf`
- Valid Kerberos ticket for `svc_logrhythm@LAB.PARASERV.COM`
- WinRM HTTPS service configured on Windows Server

### Setup Python Environment

```bash
# Create virtual environment
python3 -m venv winrm_env
source winrm_env/bin/activate
pip install pywinrm pykerberos
```

### Get Kerberos Ticket

```bash
# Get authentication ticket (password from keychain)
echo "$(security find-internet-password -s "windev01.lab.paraserv.com" -a "svc_logrhythm@LAB.PARASERV.COM" -w)" | kinit svc_logrhythm@LAB.PARASERV.COM

# Verify ticket
klist
```

### Test WinRM Connection

```python
import winrm
import subprocess

# Get password from keychain
def get_windows_password():
    result = subprocess.run([
        'security', 'find-internet-password',
        '-s', 'windev01.lab.paraserv.com',
        '-a', 'svc_logrhythm@LAB.PARASERV.COM',
        '-w'
    ], capture_output=True, text=True, check=True)
    return result.stdout.strip()

# HTTPS connection with Kerberos authentication
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                       transport='kerberos',
                       server_cert_validation='ignore')

# Test basic command
result = session.run_cmd('hostname')
print(f'Connected to: {result.std_out.decode().strip()}')

# Test session persistence (major advantage over SSH)
session.run_ps('$testVar = "Hello from WinRM"')
result = session.run_ps('$testVar')
print(f'Session test: {result.std_out.decode().strip()}')

# Test complex PowerShell
result = session.run_ps('Get-ChildItem C:\ -Directory | Select-Object Name -First 3')
print(result.std_out.decode().strip())
```

### WinRM Advantages

- **Session Persistence**: Variables and state maintained between commands
- **Clean PowerShell Syntax**: No SSH escaping issues
- **Complex Operations**: Better for multi-step PowerShell workflows
- **Enterprise Authentication**: Uses Kerberos for secure domain authentication
- **Persistent Sessions**: One session object handles multiple commands efficiently

## Adding New Servers

### For Development Servers (10.20.1.20-49)

1. **Update SSH Config**: Add new entry following the pattern:
   ```
   Host windev02
       HostName 10.20.1.21
       User Administrator
       IdentityFile /Users/nathan/.ssh/windows_server
       StrictHostKeyChecking no
       UserKnownHostsFile /dev/null
       LogLevel QUIET
   ```

2. **Test Connectivity**:
   ```bash
   ssh windev02 "hostname"
   ```

### For Production Servers (10.20.1.150-199)

1. **Update SSH Config**: Use `winsrv` prefix:
   ```
   Host winsrv01
       HostName 10.20.1.150
       User Administrator
       IdentityFile /Users/nathan/.ssh/windows_server
       StrictHostKeyChecking no
       UserKnownHostsFile /dev/null
       LogLevel QUIET
   ```

## Common Commands for Testing

### Remote PowerShell Commands

#### Via SSH
```bash
# Check PowerShell version
ssh windev01 'powershell -Command "\\$PSVersionTable.PSVersion"'

# List services
ssh windev01 'powershell -Command "Get-Service | Where-Object {\\$_.Status -eq \"Running\"} | Select-Object -First 5"'

# Check disk space
ssh windev01 'powershell -Command "Get-WmiObject -Class Win32_LogicalDisk | Select-Object DeviceID, Size, FreeSpace"'

# Test network connectivity
ssh windev01 'powershell -Command "Test-NetConnection -ComputerName 10.20.1.7 -Port 445"'
```

#### Via WinRM (Recommended for Complex Operations)
```python
import winrm

# Create session once, reuse for multiple commands
session = winrm.Session('https://windev01.lab.paraserv.com:5986/wsman',
                       auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
                       transport='kerberos',
                       server_cert_validation='ignore')

# Check PowerShell version
result = session.run_ps('$PSVersionTable.PSVersion')
print(f'PowerShell version: {result.std_out.decode().strip()}')

# List services (clean syntax, no escaping)
result = session.run_ps('Get-Service | Where-Object {$_.Status -eq "Running"} | Select-Object -First 5')
print(result.std_out.decode().strip())

# Check disk space
result = session.run_ps('Get-WmiObject -Class Win32_LogicalDisk | Select-Object DeviceID, Size, FreeSpace')
print(result.std_out.decode().strip())

# Test network connectivity
result = session.run_ps('Test-NetConnection -ComputerName 10.20.1.7 -Port 445')
print(result.std_out.decode().strip())
```

### File Transfer

```bash
# Copy single file to server
scp -i ~/.ssh/windows_server file.txt Administrator@10.20.1.20:C:/temp/

# Copy entire directory
scp -i ~/.ssh/windows_server -r ./directory Administrator@10.20.1.20:C:/temp/

# Copy using SSH config alias
scp file.txt windev01:C:/temp/
```

## Troubleshooting

### SSH Connection Issues

1. **Permission Denied**:
   - Verify SSH key permissions: `chmod 600 ~/.ssh/windows_server`
   - Check if SSH service is running on Windows server

2. **Connection Timeout**:
   - Verify network connectivity: `ping 10.20.1.20`
   - Check firewall settings on Windows server

3. **PowerShell Command Failures**:
   - Escape special characters in commands
   - Use single quotes for complex PowerShell expressions
   - Check PowerShell execution policy on server

### WinRM Connection Issues

1. **Credential Rejection**:
   - Verify service account is in "Remote Management Users" group
   - Check if WinRM service is running
   - Verify firewall allows ports 5985 (HTTP) or 5986 (HTTPS)

2. **Certificate Errors**:
   - Use `server_cert_validation='ignore'` for self-signed certificates
   - Verify certificate is properly installed

## Best Practices

1. **Use WinRM for Complex Operations**: Session persistence and clean PowerShell syntax make it ideal for LRArchiveRetention testing
2. **Use SSH for Simple Operations**: Quick commands and file transfers
3. **Always Test Basic Connectivity First**: Start with `hostname` command before complex operations
4. **Use SSH Config Aliases**: Simplifies commands and reduces errors
5. **Maintain Kerberos Tickets**: Run `kinit` when tickets expire (24h lifetime)
6. **Document Server-Specific Settings**: Each server may have unique configuration requirements

## Method Comparison

| Feature | SSH | WinRM |
|---------|-----|-------|
| **Setup Complexity** | Simple | Moderate |
| **Authentication** | Key-based | Kerberos |
| **Session Persistence** | No | Yes ✅ |
| **PowerShell Syntax** | Requires escaping | Clean ✅ |
| **Complex Operations** | Difficult | Easy ✅ |
| **File Transfer** | Native (scp) | Requires additional setup |
| **Security** | Key-based | Enterprise Kerberos ✅ |

**Recommendation**: Use WinRM for LRArchiveRetention testing and complex PowerShell operations, SSH for simple commands and file transfers.

## Security Considerations

- SSH keys are stored in `~/.ssh/windows_server` (private key)
- Keys provide Administrator access to Windows servers
- Use `StrictHostKeyChecking no` only in lab environments
- Production environments should use proper certificate validation
- Consider using service account (`svc_logrhythm`) for automated operations

## Related Documentation

- Main WinRM setup guide: `/Users/nathan/dev/xoa/windows/WinRM_Setup_AI_Guide.yml`
- SSH configuration: `~/.ssh/config`
- Project documentation: `docs/README.md`
