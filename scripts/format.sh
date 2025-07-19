#!/bin/bash
# Format all files using pre-commit formatters
# Usage: ./scripts/format.sh

echo "🔧 Running code formatters..."

# Check if pre-commit is available
if ! command -v pre-commit &> /dev/null; then
    echo "⚠️  pre-commit not found, falling back to manual formatting..."
    ./scripts/format-files.sh
    exit $?
fi

# Run manual stage formatters
pre-commit run --hook-stage manual --all-files

echo "✅ Formatting complete!"