# Test Data Generation Scripts

This folder contains helper scripts for generating test data on the NAS. These scripts were created during the process of generating 2TB of test data and document the solutions to various issues encountered.

## Main Scripts

- **`run_2tb_generation.py`** - Complete Python script that handles all setup and starts 2TB generation
- **`generate_2tb_test_data.ps1`** - PowerShell wrapper that maps drives and runs the test
- **`start_2tb_generation.py`** - Alternative approach with detailed monitoring

## Usage

The simplest approach is to use `run_2tb_generation.py`:

```bash
# From Mac/Linux
source winrm_env/bin/activate
python3 tests/generation_scripts/run_2tb_generation.py
```

## Key Learnings

1. **Module Path Issue**: The test script expects modules in `tests/modules/` not the main modules folder
2. **Credential Permissions**: Must run via WinRM with service account, not SSH
3. **Process Management**: Always kill existing PowerShell processes before starting
4. **Auto-scaling**: The script automatically adjusts parameters to fit within size limits

## See Also

- [TEST_DATA_GENERATION_GUIDE.md](../TEST_DATA_GENERATION_GUIDE.md) - Complete documentation
- [GenerateTestData.ps1](../GenerateTestData.ps1) - The main test data generation script