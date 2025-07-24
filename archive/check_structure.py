#!/usr/bin/env python3
"""Check actual file structure"""
import winrm
import subprocess

def get_windows_password():
    result = subprocess.run(
        ['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
         '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def decode_output(output):
    try:
        return output.decode('utf-8')
    except:
        try:
            return output.decode('latin-1')
        except:
            return output.decode('utf-8', errors='ignore')

session = winrm.Session(
    'https://windev01.lab.paraserv.com:5986/wsman',
    auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
    transport='ntlm',
    server_cert_validation='ignore'
)

cmd = '''
Write-Host "=== Checking directory structure ==="

# Check both possible locations
$locations = @(
    "C:\\lr\\LRArchiveRetention",
    "C:\\LR\\Scripts\\LRArchiveRetention"
)

foreach ($loc in $locations) {
    Write-Host "`nChecking: $loc"
    if (Test-Path $loc) {
        Write-Host "EXISTS - Contents:"
        Get-ChildItem $loc -Name | Select-Object -First 10
        
        # Check for key files
        $keyFiles = @(
            "ArchiveRetention.ps1",
            "modules\\ShareCredentialHelper.psm1",
            "tests\\GenerateTestData.ps1"
        )
        
        foreach ($file in $keyFiles) {
            $fullPath = Join-Path $loc $file
            if (Test-Path $fullPath) {
                Write-Host "  ✓ $file"
            } else {
                Write-Host "  ✗ $file"
            }
        }
        
        # Check credential store
        $credPath = Join-Path $loc "modules\\CredentialStore"
        if (Test-Path $credPath) {
            Write-Host "`n  Credential Store:"
            Get-ChildItem $credPath -Name
        }
    } else {
        Write-Host "DOES NOT EXIST"
    }
}
'''

result = session.run_ps(cmd)
print(decode_output(result.std_out))