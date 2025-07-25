#!/bin/bash
# Production Release Package Creator
# Creates clean, minimal packages for end users

set -e

VERSION=${1:-"2.3.21"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_ROOT/releases"
TEMP_DIR="$RELEASE_DIR/temp"

echo "🚀 Creating LogRhythm Archive Retention Manager Release v$VERSION"
echo "Project root: $PROJECT_ROOT"

# Clean and create release directory
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
mkdir -p "$TEMP_DIR"

# Production package directory
PROD_DIR="$TEMP_DIR/LRArchiveRetention-v$VERSION-Production"
COMPLETE_DIR="$TEMP_DIR/LRArchiveRetention-v$VERSION-Complete"

echo "📦 Creating Production Package..."
mkdir -p "$PROD_DIR"

# Essential files for production use
echo "  ✅ Copying core scripts..."
cp "$PROJECT_ROOT/ArchiveRetention.ps1" "$PROD_DIR/"
cp "$PROJECT_ROOT/Save-Credential.ps1" "$PROD_DIR/"
cp "$PROJECT_ROOT/CreateScheduledTask.ps1" "$PROD_DIR/"

echo "  ✅ Copying modules..."
mkdir -p "$PROD_DIR/modules"
cp -r "$PROJECT_ROOT/modules/"* "$PROD_DIR/modules/"

echo "  ✅ Copying essential documentation..."
mkdir -p "$PROD_DIR/docs"
cp "$PROJECT_ROOT/docs/QUICK_START.md" "$PROD_DIR/docs/"
cp "$PROJECT_ROOT/docs/installation.md" "$PROD_DIR/docs/"
cp "$PROJECT_ROOT/docs/command-reference.md" "$PROD_DIR/docs/"
cp "$PROJECT_ROOT/docs/performance-benchmarks.md" "$PROD_DIR/docs/"

echo "  ✅ Copying project files..."
cp "$PROJECT_ROOT/README.md" "$PROD_DIR/"
cp "$PROJECT_ROOT/CHANGELOG.md" "$PROD_DIR/"
cp "$PROJECT_ROOT/LICENSE" "$PROD_DIR/"
cp "$PROJECT_ROOT/VERSION" "$PROD_DIR/"

# Create production-specific README
cat > "$PROD_DIR/README_PRODUCTION.md" << 'EOF'
# LogRhythm Archive Retention Manager - Production Package

This is the **Production Package** containing only the essential files needed to deploy and use the Archive Retention Manager in production environments.

## 🚀 Quick Start

1. **Extract** this package to `C:\LogRhythm\Scripts\LRArchiveRetention\`
2. **Follow** the [Quick Start Guide](docs/QUICK_START.md)
3. **Be productive** in 5 minutes!

## 📁 Package Contents

- `ArchiveRetention.ps1` - Main retention script
- `Save-Credential.ps1` - Credential management
- `CreateScheduledTask.ps1` - Task automation
- `modules/` - Required PowerShell modules
- `docs/` - Essential documentation
- `README.md` - Complete project documentation
- `CHANGELOG.md` - Version history

## 📖 Documentation

- **[Quick Start Guide](docs/QUICK_START.md)** - 5-minute setup
- **[Installation Guide](docs/installation.md)** - Detailed setup
- **[Command Reference](docs/command-reference.md)** - All commands

## 🔗 Need More?

- **Complete Package**: Download if you need development tools
- **GitHub Repository**: https://github.com/paraserv/LRArchiveRetention
- **Issues/Support**: Use GitHub Issues for questions

---

**Version**: Production Package | **Source**: GitHub Release
EOF

echo "📦 Creating Complete Package..."
mkdir -p "$COMPLETE_DIR"

# Copy everything for complete package
echo "  ✅ Copying all files..."
rsync -av --exclude='.git' --exclude='releases' --exclude='*.pyc' --exclude='__pycache__' \
  "$PROJECT_ROOT/" "$COMPLETE_DIR/"

# Create complete-specific README
cat > "$COMPLETE_DIR/README_COMPLETE.md" << 'EOF'
# LogRhythm Archive Retention Manager - Complete Package

This is the **Complete Package** containing all files including development tools, tests, and advanced features.

## 📁 Package Contents

- **Production Files**: All essential scripts and documentation
- **Development Tools**: Testing, validation, and development scripts
- **Test Suite**: Comprehensive testing framework
- **Advanced Features**: Performance monitoring, debugging tools

## 👥 Target Users

- **Developers** contributing to the project
- **Advanced Users** needing customization
- **QA Teams** requiring full testing capabilities
- **DevOps** teams needing CI/CD integration

## 🚀 Quick Start

**For Production Use**: See [Quick Start Guide](docs/QUICK_START.md)
**For Development**: See [CLAUDE.md](CLAUDE.md) for development context

## 📖 Additional Documentation

- **[Development Guide](CLAUDE.md)** - AI assistant context
- **[Test Documentation](tests/README.md)** - Testing framework
- **[Project Structure](docs/PROJECT_STRUCTURE.md)** - Codebase organization

---

**Version**: Complete Package | **Source**: GitHub Release
EOF

echo "📦 Creating ZIP packages..."

# Create ZIP files
cd "$TEMP_DIR"

echo "  ✅ Creating Production ZIP..."
zip -r "$RELEASE_DIR/LRArchiveRetention-v$VERSION-Production.zip" "LRArchiveRetention-v$VERSION-Production/" > /dev/null

echo "  ✅ Creating Complete ZIP..."
zip -r "$RELEASE_DIR/LRArchiveRetention-v$VERSION-Complete.zip" "LRArchiveRetention-v$VERSION-Complete/" > /dev/null

# Calculate file sizes
PROD_SIZE=$(du -h "$RELEASE_DIR/LRArchiveRetention-v$VERSION-Production.zip" | cut -f1)
COMPLETE_SIZE=$(du -h "$RELEASE_DIR/LRArchiveRetention-v$VERSION-Complete.zip" | cut -f1)

echo "📊 Package Summary:"
echo "  📦 Production Package: $PROD_SIZE"
echo "  📦 Complete Package: $COMPLETE_SIZE"
echo "  📁 Location: $RELEASE_DIR"

# Create checksums
echo "🔐 Creating checksums..."
cd "$RELEASE_DIR"
shasum -a 256 *.zip > checksums.txt

echo "✅ Release packages created successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Review packages in: $RELEASE_DIR"
echo "2. Test Production package deployment"
echo "3. Create GitHub release with these files"
echo "4. Upload both ZIP files as release assets"
echo ""
echo "📁 Release Files:"
ls -la "$RELEASE_DIR"

# Cleanup temp directory
rm -rf "$TEMP_DIR"

echo ""
echo "🎉 Release v$VERSION ready for GitHub!"
