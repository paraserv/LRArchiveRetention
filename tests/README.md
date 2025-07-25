# Tests Directory

This directory contains all test scripts, test data generation tools, and testing documentation for the LogRhythm Archive Retention Manager.

## Directory Structure

```
tests/
├── unit/                    # Unit tests for individual functions/modules
├── integration/             # Integration tests for script functionality
│   ├── test_*.ps1          # PowerShell integration test scripts
│   └── test_*.py           # Python integration test scripts
├── performance/            # Performance and load tests
├── generation_scripts/     # Test data generation tools
│   └── *.py               # Python scripts for generating test data
├── GenerateTestData.ps1    # Main test data generation script
├── RunArchiveRetentionTests.sh  # Automated test runner
└── *.md                    # Testing documentation
```

## Test Categories

### Unit Tests (`unit/`)
- Individual function tests
- Module-specific tests
- Mock-based testing

### Integration Tests (`integration/`)
- Full script execution tests
- Lock file handling tests
- Credential management tests
- Network path tests
- Error handling scenarios

### Performance Tests (`performance/`)
- Large dataset processing
- Parallel processing benchmarks
- Memory usage tests
- Network throughput tests

## Running Tests

### PowerShell Tests
```powershell
# Run individual test
.\tests\integration\test_forceclearlock_simple.ps1

# Run all tests
.\tests\RunArchiveRetentionTests.sh
```

### Python Tests (via WinRM)
```bash
# Activate virtual environment
source winrm_env/bin/activate

# Run test via tools
python3 tools/validate_script.py
```

## Test Data Generation

### 🔧 Recent Fix: Timestamp Regression (July 2025)

**Issue Resolved**: The `generate_nas_balanced.sh` script was creating files with current timestamps instead of backdated timestamps, making them ineligible for retention testing.

**Fix Applied**: Added proper file timestamp setting using `touch -t` command to match folder dates.

### 📊 Available Generation Scripts

| Script | Platform | Use Case | Timestamp Support |
|--------|----------|----------|-------------------|
| `GenerateTestData.ps1` | PowerShell 7+ | Local/Network, High Performance | ✅ Proper backdating |
| `generate_nas_balanced.sh` | Bash/Linux | Direct NAS generation | ✅ **Fixed July 2025** |
| `generation_scripts/*.py` | Python | Various test scenarios | ✅ Configurable |

### 🚀 Quick Start - Generate Test Data

#### Option 1: Direct NAS Generation (Recommended)
```bash
# Generate 4TB of properly aged test data
ssh qnap 'cd /share/LRArchives && ./generate_nas_balanced.sh 4096'

# Verify timestamps are properly backdated
ssh qnap 'find /share/LRArchives -name "*.lca" -exec stat -c "%y %n" {} \; | head -5'
```

#### Option 2: PowerShell Generation
```powershell
# Generate test data with network credentials
.\tests\GenerateTestData.ps1 -CredentialTarget "NAS_PROD" -FolderCount 5000 -MaxSizeGB 100

# Local generation
.\tests\GenerateTestData.ps1 -RootPath "D:\TestData" -FolderCount 1000 -MaxFileSizeMB 10
```

### 🔍 Timestamp Verification

After generating test data, verify timestamps are properly backdated:

```bash
# Check file modification times (should span 3+ years)
ssh qnap 'find /share/LRArchives -name "*.lca" -exec stat -c "%Y %n" {} \; | sort -n | head -10'

# Human-readable format
ssh qnap 'find /share/LRArchives -name "*.lca" -exec stat -c "%y %n" {} \; | head -10'
```

### 🎯 Test Retention Policy

After generating properly aged data:

```powershell
# Test 3-year retention (should find files older than 1095 days)
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095

# Execute if results look correct
.\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 1095 -Execute
```

## Adding New Tests

1. Place unit tests in `unit/`
2. Place integration tests in `integration/`
3. Place performance tests in `performance/`
4. Follow naming convention: `test_<feature>_<scenario>.ps1` or `.py`
5. Update this README with new test descriptions

## CI/CD Integration

Tests are designed to be run both locally and in CI/CD pipelines. See `.github/workflows/` for GitHub Actions integration.