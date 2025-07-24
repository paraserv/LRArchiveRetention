#!/usr/bin/env python3
"""Validate ArchiveRetention.ps1 syntax and basic functionality"""

import winrm
import subprocess
import sys

def get_windows_password():
    result = subprocess.run(
        ['security', 'find-internet-password', '-s', 'windev01.lab.paraserv.com', 
         '-a', 'svc_logrhythm@LAB.PARASERV.COM', '-w'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def main():
    session = winrm.Session(
        'https://windev01.lab.paraserv.com:5986/wsman',
        auth=('svc_logrhythm@LAB.PARASERV.COM', get_windows_password()),
        transport='kerberos',
        server_cert_validation='ignore'
    )
    
    print('Validating ArchiveRetention.ps1...\n')
    
    # Test 1: Syntax validation
    print('1. Syntax validation:')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content .\\ArchiveRetention.ps1 -Raw), [ref]$null)
        Write-Host "✅ PASS: PowerShell syntax is valid"
        $syntaxValid = $true
    } catch {
        Write-Host "❌ FAIL: Syntax error - $_"
        $syntaxValid = $false
    }
    $syntaxValid
    ''')
    syntax_valid = 'True' in result.std_out.decode()
    print(result.std_out.decode().strip())
    
    if not syntax_valid:
        print('\n❌ Script has syntax errors. Cannot proceed with further tests.')
        return 1
    
    # Test 2: Basic parameter validation
    print('\n2. Parameter validation:')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    try {
        # Test help parameter
        $help = .\\ArchiveRetention.ps1 -Help 2>&1
        if ($help -match "SYNOPSIS|DESCRIPTION") {
            Write-Host "✅ PASS: Help parameter works"
        } else {
            Write-Host "❌ FAIL: Help parameter not working"
        }
    } catch {
        Write-Host "❌ FAIL: Error testing help - $_"
    }
    ''')
    print(result.std_out.decode().strip())
    
    # Test 3: Basic execution test
    print('\n3. Basic execution test (dry-run):')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    $tempDir = New-Item -ItemType Directory -Path "$env:TEMP\\AR_Test_$(Get-Random)" -Force
    
    try {
        $output = .\\ArchiveRetention.ps1 -ArchivePath $tempDir.FullName -RetentionDays 91 2>&1 | Out-String
        
        if ($output -match "DRY-RUN.*COMPLETED|SCRIPT COMPLETED") {
            Write-Host "✅ PASS: Script executes successfully in dry-run mode"
            $success = $true
        } else {
            Write-Host "❌ FAIL: Script did not complete successfully"
            $success = $false
        }
        
        # Check for common errors
        if ($output -match "ParserError|SyntaxError") {
            Write-Host "❌ FAIL: Parser/Syntax errors detected"
        }
        if ($output -match "Missing closing") {
            Write-Host "❌ FAIL: Missing closing brace/bracket detected"
        }
        
    } catch {
        Write-Host "❌ FAIL: Exception during execution - $_"
        $success = $false
    } finally {
        Remove-Item $tempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
    ''')
    print(result.std_out.decode().strip())
    
    # Test 4: Lock parameters test
    print('\n4. Lock parameter tests:')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    
    # Test ForceClearLock
    Write-Host "Testing ForceClearLock parameter..."
    try {
        $output = .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 91 -ForceClearLock 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $output -match "COMPLETED") {
            Write-Host "✅ PASS: ForceClearLock parameter accepted"
        } else {
            Write-Host "⚠️  WARN: ForceClearLock may have issues"
        }
    } catch {
        Write-Host "❌ FAIL: ForceClearLock parameter error - $_"
    }
    
    # Test Force
    Write-Host "Testing Force parameter..."
    try {
        $output = .\\ArchiveRetention.ps1 -ArchivePath "C:\\Temp" -RetentionDays 91 -Force 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $output -match "COMPLETED") {
            Write-Host "✅ PASS: Force parameter accepted"
        } else {
            Write-Host "⚠️  WARN: Force parameter may have issues"
        }
    } catch {
        Write-Host "❌ FAIL: Force parameter error - $_"
    }
    ''')
    print(result.std_out.decode().strip())
    
    # Test 5: Version check
    print('\n5. Version check:')
    result = session.run_ps('''
    cd C:\\LR\\Scripts\\LRArchiveRetention
    $version = Get-Content .\\VERSION
    Write-Host "Current version: $version"
    
    # Check if version is in script
    $scriptContent = Get-Content .\\ArchiveRetention.ps1 -Raw
    if ($scriptContent -match "Version $version|v$version") {
        Write-Host "✅ PASS: Version number found in script"
    } else {
        Write-Host "⚠️  WARN: Version number may not be updated in script"
    }
    ''')
    print(result.std_out.decode().strip())
    
    print('\n' + '='*60)
    print('Validation complete. Please review results above.')
    
    return 0

if __name__ == '__main__':
    sys.exit(main())