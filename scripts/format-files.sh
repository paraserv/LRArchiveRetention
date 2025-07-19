#!/bin/bash
# Format Files Script - Fix common formatting issues before commit
# This addresses the root cause of pre-commit hook failures

echo "🔧 Formatting files to prevent pre-commit failures..."

# Fix missing newlines at end of files
echo "📝 Adding missing newlines..."
find . -type f \( -name "*.md" -o -name "*.ps1" -o -name "*.py" -o -name "*.sh" -o -name "*.yaml" -o -name "*.yml" \) \
    -not -path "./.git/*" \
    -not -path "./node_modules/*" \
    -not -path "./.venv/*" \
    -not -path "./winrm_env/*" \
    -exec bash -c 'if [[ -s "$1" && "$(tail -c 1 "$1")" != "" ]]; then echo "" >> "$1"; echo "Fixed: $1"; fi' _ {} \;

# Remove trailing whitespace
echo "🧹 Removing trailing whitespace..."
find . -type f \( -name "*.md" -o -name "*.ps1" -o -name "*.py" -o -name "*.sh" -o -name "*.yaml" -o -name "*.yml" \) \
    -not -path "./.git/*" \
    -not -path "./node_modules/*" \
    -not -path "./.venv/*" \
    -not -path "./winrm_env/*" \
    -exec sed -i '' 's/[[:space:]]*$//' {} \; \
    -exec echo "Cleaned: {}" \;

echo "✅ File formatting complete!"
