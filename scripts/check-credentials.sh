#!/bin/bash
# check-credentials.sh - General credential scanner for Windows and cross-platform environments

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Exit status
EXIT_CODE=0

echo "🔍 Scanning for credentials and secrets..."

# Function to check a single file
check_file() {
    local file="$1"
    local violations=()

    # Skip scanning our own security scanner files
    if [[ "$file" == scripts/check-*.sh ]]; then
        return 0
    fi

    # Common credential patterns
    local patterns=(
        # Passwords in various formats
        "password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{3,}['\"]"
        "Password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{3,}['\"]"
        "PASSWORD[[:space:]]*[:=][[:space:]]*['\"][^'\"]{3,}['\"]"

        # Windows/AD specific patterns
        "logrhythm![0-9a-zA-Z]+"
        "svc_[a-zA-Z]+[[:space:]]*[/\\][[:space:]]*[a-zA-Z0-9!@#$%^&*()]+"
        "Administrator[[:space:]]*[/\\][[:space:]]*[a-zA-Z0-9!@#$%^&*()]+"

        # Connection strings with passwords
        "Server=.*Password=[^;]*;"
        "Data Source=.*Password=[^;]*;"
        "connectionString.*password=[^;\"']*"

        # API keys and tokens
        "[aA]pi[_-]?[kK]ey[[:space:]]*[:=][[:space:]]*['\"][a-zA-Z0-9]{20,}['\"]"
        "[aA]ccess[_-]?[tT]oken[[:space:]]*[:=][[:space:]]*['\"][a-zA-Z0-9]{20,}['\"]"
        "[sS]ecret[_-]?[kK]ey[[:space:]]*[:=][[:space:]]*['\"][a-zA-Z0-9]{20,}['\"]"

        # PowerShell credential patterns
        "-Password[[:space:]]+['\"][^'\"]{3,}['\"]"
        "ConvertTo-SecureString.*-AsPlainText.*-Force"
        "\$credential.*=.*New-Object.*PSCredential.*['\"][^'\"]{3,}['\"]"

        # Environment variables with secrets
        "export.*PASSWORD=.*"
        "set.*PASSWORD=.*"
        "\$env:.*PASSWORD.*=.*"

        # SSH/RSA keys (partial patterns)
        "-----BEGIN.*PRIVATE KEY-----"
        "ssh-rsa AAAA[0-9A-Za-z+/]{20,}"

        # URLs with embedded credentials
        "https?://[^:]+:[^@]+@[^/]+"
        "ftp://[^:]+:[^@]+@[^/]+"
    )

    # Check each pattern
    for pattern in "${patterns[@]}"; do
        if grep -iE "$pattern" "$file" >/dev/null 2>&1; then
            violations+=("Pattern: $pattern")
        fi
    done

    # Check for specific problematic strings
    local forbidden_strings=(
        "logrhythm!1"
        "password123"
        "admin123"
        "secret123"
        "changeme"
        "Password01"
        "P@ssw0rd"
    )

    for string in "${forbidden_strings[@]}"; do
        if grep -iF "$string" "$file" >/dev/null 2>&1; then
            violations+=("Forbidden string: $string")
        fi
    done

    # Report violations
    if [ ${#violations[@]} -gt 0 ]; then
        echo -e "${RED}❌ SECURITY VIOLATION in $file:${NC}"
        for violation in "${violations[@]}"; do
            echo -e "  ${YELLOW}• $violation${NC}"
        done
        echo ""
        return 1
    fi

    return 0
}

# Check all staged files
files_to_check=("$@")

if [ ${#files_to_check[@]} -eq 0 ]; then
    echo "No files to check"
    exit 0
fi

echo "Checking ${#files_to_check[@]} files..."

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        if ! check_file "$file"; then
            EXIT_CODE=1
        fi
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ No credential violations found${NC}"
else
    echo -e "${RED}❌ Credential violations detected!${NC}"
    echo ""
    echo "SECURITY RECOMMENDATIONS:"
    echo "1. Remove hardcoded passwords and use keychain/environment variables"
    echo "2. Use secure credential storage (macOS keychain, Windows Credential Manager)"
    echo "3. Reference credentials via: security find-internet-password -w"
    echo "4. Never commit actual passwords, API keys, or connection strings"
    echo ""
fi

exit $EXIT_CODE
