#!/bin/bash
# Smart Commit Script - Handles pre-commit hook failures gracefully
# Usage: ./scripts/smart-commit.sh "commit message"

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 \"commit message\""
    echo "Example: $0 \"fix: update documentation\""
    exit 1
fi

COMMIT_MSG="$1"

echo "🚀 Smart Commit: Starting commit process..."

# Stage all changes
echo "📁 Staging all changes..."
git add -A

# First commit attempt - let pre-commit hooks fix files
echo "🔧 Running pre-commit hooks (fixing files if needed)..."
if git commit -m "$COMMIT_MSG

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"; then
    echo "✅ Commit successful on first attempt!"
else
    echo "🔄 First commit failed (expected - hooks fixed files). Retrying..."

    # Stage the fixed files and commit again
    git add -A
    if git commit -m "$COMMIT_MSG

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"; then
        echo "✅ Commit successful on second attempt!"
    else
        echo "❌ Commit failed after hook fixes. Check for errors above."
        exit 1
    fi
fi

echo "🎉 Smart commit completed successfully!"
