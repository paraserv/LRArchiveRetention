#!/bin/bash
# check-docs-credentials.sh - Documentation specific credential scanner

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

EXIT_CODE=0

echo "🔍 Scanning documentation for exposed credentials..."

check_docs_file() {
    local file="$1"
    local violations=()

    # Skip scanning our own security scanner files and setup docs
    if [[ "$file" == scripts/check-*.sh ]] || [[ "$file" == docs/pre-commit-security-setup.md ]]; then
        return 0
    fi

    # Documentation credential patterns
    local doc_patterns=(
        # Example credentials that might be real
        "password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{3,}['\"]"
        "Password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{3,}['\"]"
        "username.*password.*[a-zA-Z0-9!@#$%^&*()]{6,}"

        # Connection strings in docs
        "Server=.*Password=[^;]*"
        "mongodb://.*:.*@"
        "postgres://.*:.*@"
        "mysql://.*:.*@"

        # API keys and tokens in examples
        "[aA]pi[_-]?[kK]ey[[:space:]]*[:=][[:space:]]*[a-zA-Z0-9]{20,}"
        "[sS]ecret[_-]?[kK]ey[[:space:]]*[:=][[:space:]]*[a-zA-Z0-9]{20,}"
        "[aA]ccess[_-]?[tT]oken[[:space:]]*[:=][[:space:]]*[a-zA-Z0-9]{20,}"

        # SSH keys in documentation
        "ssh-rsa AAAA[0-9A-Za-z+/]{100,}"
        "-----BEGIN.*PRIVATE KEY-----"

        # URLs with credentials
        "https?://[^:]+:[^@]+@[^/\s]+"
        "ftp://[^:]+:[^@]+@[^/\s]+"

        # Windows specific credential patterns
        "Administrator.*['\"][a-zA-Z0-9!@#$%^&*()]{6,}['\"]"
        "svc_[a-zA-Z]+.*['\"][a-zA-Z0-9!@#$%^&*()]{6,}['\"]"

        # Command line examples with passwords
        "kinit.*echo.*['\"][^'\"]{6,}['\"]"
        "-Password.*['\"][^'\"]{6,}['\"]"
    )

    # Check documentation patterns, respecting pragma allowlist comments
    for pattern in "${doc_patterns[@]}"; do
        while IFS= read -r line; do
            # Skip lines with pragma allowlist comment
            if [[ "$line" =~ pragma:[[:space:]]*allowlist[[:space:]]*secret ]] || [[ "$line" =~ pragma:[[:space:]]*whitelist[[:space:]]*secret ]]; then
                continue
            fi
            violations+=("Credential pattern: $pattern")
        done < <(grep -iE "$pattern" "$file" 2>/dev/null || true)
    done

    # Specific forbidden strings in documentation
    local forbidden_doc_strings=(
        "logrhythm!1"
        "password123"
        "admin123"
        "changeme"
        "P@ssw0rd"
        "Password01"
        "secret123"
        "default123"
        "test123"
        "demo123"
    )

    for string in "${forbidden_doc_strings[@]}"; do
        while IFS= read -r line; do
            # Skip lines with pragma allowlist comment
            if [[ "$line" =~ pragma:[[:space:]]*allowlist[[:space:]]*secret ]] || [[ "$line" =~ pragma:[[:space:]]*whitelist[[:space:]]*secret ]]; then
                continue
            fi
            violations+=("Forbidden credential string: $string")
        done < <(grep -iF "$string" "$file" 2>/dev/null || true)
    done

    # Check for acceptable placeholder patterns (these should NOT trigger violations)
    local acceptable_patterns=(
        "YOUR_PASSWORD"
        "ENTER_PASSWORD_HERE"
        "password_from_keychain"
        "<PASSWORD>"
        "\\$\\{PASSWORD\\}"
        "security find-internet-password.*-w"
        "keychain"
        "placeholder"
        "example.com"
        "your-secret-here"
    )

    # Remove violations that match acceptable patterns
    local filtered_violations=()
    for violation in "${violations[@]}"; do
        local is_acceptable=false
        for acceptable in "${acceptable_patterns[@]}"; do
            if echo "$violation" | grep -iE "$acceptable" >/dev/null 2>&1; then
                is_acceptable=true
                break
            fi
        done
        if [ "$is_acceptable" = false ]; then
            filtered_violations+=("$violation")
        fi
    done

    # Report violations
    if [ ${#filtered_violations[@]} -gt 0 ]; then
        echo -e "${RED}❌ DOCUMENTATION SECURITY VIOLATION in $file:${NC}"
        for violation in "${filtered_violations[@]}"; do
            echo -e "  ${YELLOW}• $violation${NC}"
        done
        echo -e "${YELLOW}RECOMMENDATION: Replace with placeholder or keychain reference${NC}"
        echo ""
        return 1
    fi

    return 0
}

# Check all documentation files
files_to_check=("$@")

if [ ${#files_to_check[@]} -eq 0 ]; then
    echo "No documentation files to check"
    exit 0
fi

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        if ! check_docs_file "$file"; then
            EXIT_CODE=1
        fi
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ No documentation credential violations found${NC}"
else
    echo -e "${RED}❌ Documentation credential violations detected!${NC}"
    echo ""
    echo "DOCUMENTATION SECURITY RECOMMENDATIONS:"
    echo "1. Replace real credentials with placeholders like YOUR_PASSWORD"
    echo "2. Use keychain references: security find-internet-password -w"
    echo "3. Add security notes about proper credential storage"
    echo "4. Use example.com or placeholder domains"
    echo "5. Never include real API keys, even in examples"
fi

exit $EXIT_CODE
