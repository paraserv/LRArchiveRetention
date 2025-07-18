#!/bin/bash
# setup-pre-commit.sh - Complete pre-commit security setup script

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 LRArchiveRetention Pre-Commit Security Setup${NC}"
echo "=================================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install pre-commit and detect-secrets
install_dependencies() {
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"

    if command_exists pipx; then
        echo "Using pipx to install pre-commit and detect-secrets..."
        pipx install pre-commit
        pipx install detect-secrets
    elif command_exists pip3; then
        echo "Using pip3 to install pre-commit and detect-secrets..."
        pip3 install --user pre-commit detect-secrets
    elif command_exists pip; then
        echo "Using pip to install pre-commit and detect-secrets..."
        pip install --user pre-commit detect-secrets
    else
        echo -e "${RED}❌ No Python package manager found.${NC}"
        echo "Please install pipx via: brew install pipx"
        echo "Or create a virtual environment and install manually."
        exit 1
    fi
}

# Function to setup pre-commit
setup_precommit() {
    echo -e "${YELLOW}🛠️  Setting up pre-commit hooks...${NC}"

    # Ensure we're in the project root
    if [ ! -f ".pre-commit-config.yaml" ]; then
        echo -e "${RED}❌ .pre-commit-config.yaml not found. Are you in the project root?${NC}"
        exit 1
    fi

    # Install pre-commit hooks
    pre-commit install

    # Install commit-msg hook (optional)
    pre-commit install --hook-type commit-msg || echo "commit-msg hook installation failed (optional)"

    echo -e "${GREEN}✅ Pre-commit hooks installed${NC}"
}

# Function to generate or update secrets baseline
setup_secrets_baseline() {
    echo -e "${YELLOW}🔍 Setting up secrets baseline...${NC}"

    if command_exists detect-secrets; then
        if [ ! -f ".secrets.baseline" ]; then
            echo "Generating initial secrets baseline..."
            detect-secrets scan --baseline .secrets.baseline
        else
            echo "Updating existing secrets baseline..."
            detect-secrets scan --baseline .secrets.baseline --update
        fi
        echo -e "${GREEN}✅ Secrets baseline configured${NC}"
    else
        echo -e "${YELLOW}⚠️  detect-secrets not found, using pre-created baseline${NC}"
    fi
}

# Function to make scripts executable
setup_scripts() {
    echo -e "${YELLOW}🔧 Setting up security scripts...${NC}"

    if [ -d "scripts" ]; then
        chmod +x scripts/*.sh
        echo -e "${GREEN}✅ Security scripts made executable${NC}"
    else
        echo -e "${RED}❌ Scripts directory not found${NC}"
        exit 1
    fi
}

# Function to test the setup
test_setup() {
    echo -e "${YELLOW}🧪 Testing pre-commit setup...${NC}"

    # Test on a few sample files
    echo "Testing credential scanner on documentation..."
    if pre-commit run check-windows-credentials --files README.md >/dev/null 2>&1; then
        echo -e "${GREEN}✅ General credential scanner working${NC}"
    else
        echo -e "${YELLOW}⚠️  Credential scanner found issues (check manually)${NC}"
    fi

    # Test PowerShell scanner if PS1 files exist
    if ls *.ps1 >/dev/null 2>&1; then
        echo "Testing PowerShell scanner..."
        if pre-commit run check-powershell-secrets --files *.ps1 >/dev/null 2>&1; then
            echo -e "${GREEN}✅ PowerShell scanner working${NC}"
        else
            echo -e "${YELLOW}⚠️  PowerShell scanner found issues (check manually)${NC}"
        fi
    fi

    echo -e "${GREEN}✅ Setup testing complete${NC}"
}

# Function to display next steps
show_next_steps() {
    echo ""
    echo -e "${BLUE}🎉 Pre-commit security setup complete!${NC}"
    echo "============================================"
    echo ""
    echo "Next steps:"
    echo "1. Test the full setup: ${YELLOW}pre-commit run --all-files${NC}"
    echo "2. Make a test commit to verify hooks work"
    echo "3. Store your credentials in keychain:"
    echo "   ${YELLOW}security add-internet-password -s \"windev01.lab.paraserv.com\" -a \"svc_logrhythm@LAB.PARASERV.COM\" -w${NC}"
    echo ""
    echo "Documentation: ${BLUE}docs/pre-commit-security-setup.md${NC}"
    echo ""
    echo "To run security checks manually:"
    echo "• ${YELLOW}pre-commit run check-windows-credentials --all-files${NC}"
    echo "• ${YELLOW}pre-commit run check-powershell-secrets --all-files${NC}"
    echo "• ${YELLOW}pre-commit run check-docs-credentials --all-files${NC}"
    echo ""
}

# Main execution
main() {
    echo "Starting setup..."

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ Not in a git repository. Please run from the project root.${NC}"
        exit 1
    fi

    # Install dependencies
    install_dependencies

    # Setup pre-commit
    setup_precommit

    # Setup secrets baseline
    setup_secrets_baseline

    # Setup scripts
    setup_scripts

    # Test the setup
    test_setup

    # Show next steps
    show_next_steps
}

# Run main function
main "$@"
