#!/bin/bash
# check-powershell-secrets.sh - PowerShell specific credential scanner

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

EXIT_CODE=0

echo "🔍 Scanning PowerShell files for credential issues..."

check_powershell_file() {
    local file="$1"
    local violations=()

    # Skip scanning our own security scanner files
    if [[ "$file" == scripts/check-*.sh ]]; then
        return 0
    fi

    # PowerShell-specific credential anti-patterns
    local ps_patterns=(
        # Hardcoded credentials in PowerShell
        "New-Object.*PSCredential.*['\"][^'\"]+['\"].*['\"][^'\"]{3,}['\"]"
        "ConvertTo-SecureString.*['\"][^'\"]{6,}['\"].*-AsPlainText.*-Force"
        "\$credential.*=.*['\"][^'\"]{3,}['\"]"

        # Direct password parameters
        "-Password[[:space:]]+['\"][^'\"]{3,}['\"]"
        "-UserName[[:space:]]+['\"][^'\"]+['\"].*-Password[[:space:]]+['\"][^'\"]{3,}['\"]"

        # Invoke-Command with embedded credentials
        "Invoke-Command.*-Credential.*['\"][^'\"]{3,}['\"]"

        # Get-Credential with hardcoded values
        "Get-Credential.*['\"][^'\"]+['\"].*['\"][^'\"]{3,}['\"]"

        # Connection strings in PowerShell
        "Server=.*User.*Password=[^;\"']*"
        "Data Source=.*Password=[^;\"']*"

        # Environment variable assignments with secrets
        "\$env:[A-Z_]*PASSWORD[A-Z_]*[[:space:]]*=[[:space:]]*['\"][^'\"]{3,}['\"]"

        # Registry credential storage (insecure)
        "Set-ItemProperty.*Password.*['\"][^'\"]{3,}['\"]"

        # WinRM with embedded credentials
        "New-PSSession.*-Credential.*['\"][^'\"]{3,}['\"]"
        "Enter-PSSession.*-Credential.*['\"][^'\"]{3,}['\"]"
    )

        # Check PowerShell patterns, respecting pragma allowlist comments
    for pattern in "${ps_patterns[@]}"; do
        while IFS= read -r line; do
            # Skip lines with pragma allowlist comment
            if echo "$line" | grep -iE "pragma:.*allowlist.*secret|pragma:.*whitelist.*secret" >/dev/null 2>&1; then
                continue
            fi
            violations+=("PowerShell credential pattern: $pattern")
                 done < <(grep -iE "$pattern" "$file" 2>/dev/null || true)
     done

    # Check for insecure PowerShell practices
    local insecure_practices=(
        # Plain text password storage with hardcoded values
        "echo.*['\"][^'\"]{6,}['\"].*|.*ConvertTo-SecureString"
        "Read-Host.*-AsSecureString.*-Force"

        # Insecure credential export
        "Export-Credential.*-Path.*-Password"
        "ConvertFrom-SecureString.*-Key"

        # Network credentials in clear text
        "System.Net.NetworkCredential.*['\"][^'\"]{3,}['\"]"
    )

    for practice in "${insecure_practices[@]}"; do
        while IFS= read -r line; do
            # Skip lines with pragma allowlist comment
            if echo "$line" | grep -iE "pragma:.*allowlist.*secret|pragma:.*whitelist.*secret" >/dev/null 2>&1; then
                continue
            fi
            violations+=("Insecure practice: $practice")
        done < <(grep -iE "$practice" "$file" 2>/dev/null || true)
    done

    # Check for recommended secure patterns that might be misused
    while IFS= read -r line; do
        # Skip lines with pragma allowlist comment
        if echo "$line" | grep -iE "pragma:.*allowlist.*secret|pragma:.*whitelist.*secret" >/dev/null 2>&1; then
            continue
        fi
        violations+=("Possible insecure Save-Credential usage - should use -UseStdin")
    done < <(grep -iE "Save-Credential.*-Password[[:space:]]+['\"]" "$file" 2>/dev/null || true)

    # Report violations
    if [ ${#violations[@]} -gt 0 ]; then
        echo -e "${RED}❌ POWERSHELL SECURITY VIOLATION in $file:${NC}"
        for violation in "${violations[@]}"; do
            echo -e "  ${YELLOW}• $violation${NC}"
        done
        echo -e "${YELLOW}RECOMMENDATION: Use Save-Credential.ps1 with -UseStdin or keychain integration${NC}"
        echo ""
        return 1
    fi

    return 0
}

# Check all PowerShell files
files_to_check=("$@")

if [ ${#files_to_check[@]} -eq 0 ]; then
    echo "No PowerShell files to check"
    exit 0
fi

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ] && [[ "$file" == *.ps1 ]]; then
        if ! check_powershell_file "$file"; then
            EXIT_CODE=1
        fi
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ No PowerShell credential violations found${NC}"
else
    echo -e "${RED}❌ PowerShell credential violations detected!${NC}"
    echo ""
    echo "POWERSHELL SECURITY RECOMMENDATIONS:"
    echo "1. Use Save-Credential.ps1 with -UseStdin for password input"
    echo "2. Retrieve credentials via keychain: security find-internet-password -w"
    echo "3. Use Windows Credential Manager for secure storage"
    echo "4. Never use ConvertTo-SecureString with -AsPlainText -Force in production"
    echo "5. Use PSCredential objects with secure input methods"
fi

exit $EXIT_CODE
