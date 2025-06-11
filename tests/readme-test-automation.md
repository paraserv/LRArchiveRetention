# readme-test-automation.md

**Purpose:** This guide is for developers, testers, and auditors to automate and validate ArchiveRetention.ps1 using cross-platform tools.

---

**Note:** All commands assume you are running from the project root on your Mac/Linux machine.

## ArchiveRetention.ps1 Test Automation

This folder contains scripts to automate generating test data, running, and validating tests for ArchiveRetention.ps1.

---

## Quick Workflow Checklist
1. **Generate test data on the server** using `GenerateTestData.ps1`.
2. **Run all core and edge-case tests** using `RunArchiveRetentionTests.sh` from your Mac/Linux (includes a built-in concurrency lock test).
3. **Review the on-screen summary table** or open the generated `summary_*.log` file in this `tests` folder for a concise PASS/FAIL overview.
4. **Validate detailed logs and interpret results** using SSH and log commands.

---

### Prerequisites
- SSH access to the Windows server
- SSH private key (e.g., `~/.ssh/id_rsa_windows`)
- Bash environment (macOS/Linux) for running automation scripts
- PowerShell (7+/Core) on the Windows server
- Sufficient disk space for test data generation

---

## Usage

### 1. Generate Test Data
**You must run this before running the core tests.**

```bash
scp -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR tests/GenerateTestData.ps1 administrator@10.20.1.200:'C:/LogRhythm/Scripts/ArchiveV2/tests/'
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 \
  "pwsh -NoProfile -ExecutionPolicy Bypass -Command \"& { cd 'C:/LogRhythm/Scripts/ArchiveV2/tests'; ./GenerateTestData.ps1 -RootPath 'D:/LogRhythmArchives/Test' }\""
```
- This script will create a realistic, auto-scaled test data set in `D:\LogRhythmArchives\Test`.

### 2. Run Core Tests

```bash
bash RunArchiveRetentionTests.sh
```
- Runs all scenarios **sequentially**, automatically waiting for any previous run to finish.
- A dedicated **concurrency lock test** launches two overlapping runs to verify that the second exits with code 9.
- When finished, the script prints a compact summary table and writes `summary_<timestamp>.log` to this `tests` directory.
- Prints output for each test, including warnings, errors, and summary.
- Edit the script to add or modify test cases as needed.

### 3. Validate Logs and Interpret Results
**Review the output for pass/fail and compare to the expected results in test-plan.md.**

```bash
ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200 \
  'powershell -Command "Get-Content -Tail 20 ''C:\LogRhythm\Scripts\ArchiveV2\script_logs\ArchiveRetention.log''"'
```
- Adjust the log path as needed.
- Check logs on the server for detailed audit/compliance info.
- Update the test tracking table in test-plan.md after each run.

---

## Extending the Tests
- To add more scenarios, edit `RunArchiveRetentionTests.sh` and add more helper calls (e.g., `run_network_test`, `run_local_test`, `run_concurrency_test`).
- Keep the concurrency lock test as the canonical pattern for validating single-instance protection.
- Review the test-plan.md for a list of recommended and edge-case scenarios.

---

## Troubleshooting
- **SSH connection fails:**
  - Check your SSH key path and permissions.
  - Ensure the server is reachable and the user has access.
- **Not enough disk space:**
  - The data generator will auto-scale, but ensure at least 20% free disk space.
- **PowerShell errors:**
  - Make sure PowerShell 7+/Core is installed and in the PATH.
- **Permission denied on server:**
  - Ensure your user has write/delete permissions in the test data directory.
- **Test data not generated:**
  - **Always run `GenerateTestData.ps1` before running tests.** If missing, re-run the generator.
- **Test script errors:**
  - Check for typos in script names or paths. Ensure all scripts are up to date and in the correct folder.

---

## FAQ
- **Q: What if I want to reset the test data?**
  - **A:** Re-run `GenerateTestData.ps1` to regenerate a fresh test set. This will overwrite the previous data.
- **Q: What if a test fails?**
  - **A:** Review the output and logs for errors. Check the troubleshooting section above. If needed, regenerate test data and re-run.
- **Q: Can I add my own test scenarios?**
  - **A:** Yes! Edit `RunArchiveRetentionTests.sh` and add more `run_test` calls. See test-plan.md for ideas.
- **Q: How do I check detailed logs?**
  - **A:** Use the SSH log command above, or open the log files directly on the server.
- **Q: What if the script output is unclear?**
  - **A:** Compare the output to the expected results in test-plan.md. If still unclear, check the logs or ask for help.
- **Q: How do I update the test tracking table?**
  - **A:** Edit `test-plan.md` and fill in the Pass/Fail and Notes columns after each run.
