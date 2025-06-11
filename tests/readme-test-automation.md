# readme-test-automation.md

## ArchiveRetention.ps1 Test Automation

This folder contains scripts to automate running and validating tests for ArchiveRetention.ps1.

---

### Prerequisites
- SSH access to the Windows server
- SSH private key (e.g., `~/.ssh/id_rsa_windows`)
- ArchiveRetention.ps1 and test data present on the server
- Bash environment (macOS/Linux)

---

## Usage

### 1. Run Core Tests (Recommended)
```bash
bash RunArchiveRetentionTests.sh
```
- Runs all core and edge-case test scenarios via SSH using the PowerShell command pattern from ide-reference.md.
- Prints output for each test, including warnings, errors, and summary.
- Edit the script to add or modify test cases as needed.

### 2. Test Data Generation
See the test plan for details on generating test data with `GenerateTestData.ps1` before running tests.

---

## Extending the Tests
- To add more scenarios, edit `RunArchiveRetentionTests.sh` and add more `run_test` calls.
- Review the test-plan.md for a list of recommended and edge-case scenarios.

### 2. Validate Logs (Manual/Optional)
To view logs after a test, run:
```bash
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 \
  'powershell -Command "Get-Content -Tail 20 ''C:\LogRhythm\Scripts\ArchiveV2\script_logs\ArchiveRetention.log''"'
```
- Adjust the log path as needed.

---

## Interpreting Results
- Each test prints a summary and any warnings/errors.
- Review the output for pass/fail and compare to the expected results in test-plan.md.
- Check logs on the server for detailed audit/compliance info.
- Update the test tracking table in test-plan.md after each run.

---

**Note:**
- Scripts like `run-archive-tests.sh` and `validate-logs.sh` were intended for local Windows execution but are not used in the canonical workflow. Use `RunArchiveRetentionTests.sh` for all core test automation from your Mac.
