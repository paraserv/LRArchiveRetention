# Git Workflow Guide

## ✅ Standard Git Workflow (FIXED!)

**Pre-commit hooks have been reconfigured to not block commits. Regular git commands now work perfectly!**

### Normal Commits (Recommended)

```bash
# Standard git workflow - no special scripts needed!
git add -A
git commit -m "your commit message"
git push origin main
```

**What happens:**
1. Security checks run (detect secrets, credentials, etc.)
2. File validation runs (YAML, JSON syntax)
3. **Formatters don't run** (moved to manual stage)
4. Commit succeeds without retries!

### Quick Commit (Emergency Only)

Use this only for emergency commits when pre-commit hooks are blocking critical fixes:

```bash
# Usage (emergency only)
./scripts/quick-commit.sh "emergency fix message"

# Remember to run hooks later
pre-commit run --all-files
```

**⚠️ Warning:** This bypasses all pre-commit security and quality checks!

### Manual Commit Process

If you prefer manual control:

```bash
# Stage changes
git add -A

# First attempt (may fail due to hook fixes)
git commit -m "your message"

# If it fails, re-stage and commit again
git add -A
git commit -m "your message"
```

## Pre-Commit Hook Optimizations

The configuration has been optimized to reduce failures:

- **File-specific checks**: YAML/JSON checks only run on relevant files
- **Better exclusions**: Excludes virtual environments and git directories
- **Clearer feedback**: Distinguished between critical checks and auto-fixers

### Common Hook Behaviors

**Auto-fixers (expect failures on first commit):**
- `end-of-file-fixer`: Adds missing newlines
- `trailing-whitespace`: Removes trailing spaces
- `mixed-line-ending`: Normalizes line endings

**Critical checks (should not modify files):**
- `check-added-large-files`: Prevents large file commits
- `check-case-conflict`: Prevents case-sensitive filename conflicts
- `check-merge-conflict`: Detects unresolved merge markers
- Security scanners: Detect credentials and secrets

## Best Practices

1. **Use smart-commit.sh** for 95% of your commits
2. **Test locally** before committing with `pre-commit run --all-files`
3. **Emergency only** use quick-commit.sh
4. **Review changes** that hooks make to your files
5. **Keep hooks updated** with `pre-commit autoupdate`

## Troubleshooting

### Persistent Hook Failures
```bash
# Run hooks manually to see detailed output
pre-commit run --all-files

# Update hook versions
pre-commit autoupdate

# Clear hook cache if needed
pre-commit clean
```

### Skip Hooks Temporarily
```bash
# Skip all hooks (not recommended)
git commit --no-verify -m "message"

# Skip specific hook
SKIP=end-of-file-fixer git commit -m "message"
```

## Integration with CLAUDE.md

For Claude Code, use these commands in your instructions:

```bash
# Preferred method for commits
./scripts/smart-commit.sh "commit message"

# For push operations
git push origin main
```
