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

See [TEST_DATA_GENERATION_GUIDE.md](TEST_DATA_GENERATION_GUIDE.md) for detailed instructions on generating test data.

## Adding New Tests

1. Place unit tests in `unit/`
2. Place integration tests in `integration/`
3. Place performance tests in `performance/`
4. Follow naming convention: `test_<feature>_<scenario>.ps1` or `.py`
5. Update this README with new test descriptions

## CI/CD Integration

Tests are designed to be run both locally and in CI/CD pipelines. See `.github/workflows/` for GitHub Actions integration.