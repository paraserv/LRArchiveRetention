#!/bin/bash
# update-secrets-baseline.sh
# Manually update the secrets baseline to prevent pre-commit loops

set -e

echo "🔍 Updating secrets baseline..."

# Update the baseline
detect-secrets scan --baseline .secrets.baseline

# Check if baseline was modified
if git diff --quiet .secrets.baseline; then
    echo "✅ Baseline is up to date - no changes needed"
else
    echo "📝 Baseline updated with new line numbers"
    echo "   Run 'git add .secrets.baseline' before your next commit"
fi

echo "🔍 Running manual secrets detection..."
pre-commit run detect-secrets --hook-stage manual --all-files

echo "✅ Secrets baseline update complete"
