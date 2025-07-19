#!/bin/bash
# Quick Commit Script - Bypasses pre-commit for emergency commits
# Usage: ./scripts/quick-commit.sh "emergency fix message"

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 \"commit message\""
    echo "⚠️  WARNING: This bypasses pre-commit hooks - use only for emergencies!"
    exit 1
fi

COMMIT_MSG="$1"

echo "⚡ Quick Commit: Bypassing pre-commit hooks..."
echo "⚠️  Remember to run 'pre-commit run --all-files' later!"

# Stage all changes and commit with --no-verify
git add -A
git commit --no-verify -m "$COMMIT_MSG

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

echo "✅ Quick commit completed! Run pre-commit checks when ready."
