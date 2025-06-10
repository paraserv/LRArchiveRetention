# ArchiveRetention.ps1 Comprehensive Test Plan

## Purpose
This document outlines all recommended tests to ensure the ArchiveRetention.ps1 script is robust, safe, and reliable in a wide range of real-world and edge-case scenarios.

---

## 1. **Basic Functionality**

### 1.1 Dry-Run Mode (No Deletions)
- **Test:** Run script without `-Execute` on a directory with files older and newer than the retention period.
- **Expected:** No files or directories are deleted. Log shows what would be deleted.

### 1.2 Execute Mode (Deletions)
- **Test:** Run script with `-Execute` on a directory with files older and newer than the retention period.
- **Expected:** Only files older than the retention period are deleted. Log and audit log reflect actions.

---

## 2. **Retention Period Enforcement**

### 2.1 Minimum Retention (Below Minimum)
- **Test:** Run with a retention period below the hard-coded minimum (e.g., 10 days).
- **Expected:** In dry-run, warning is logged but action is simulated. In execute, minimum is enforced and warning is logged.

### 2.2 Maximum Retention (Above Maximum)
- **Test:** Run with a very high retention period (e.g., 3650 days).
- **Expected:** No files are deleted unless they are older than the specified period.

---

## 3. **File and Directory Scenarios**

### 3.1 Mixed File Types
- **Test:** Include/exclude specific file types using parameters.
- **Expected:** Only specified file types are considered for deletion.

### 3.2 Nested Directories
- **Test:** Run on a directory tree with multiple levels of subfolders.
- **Expected:** All eligible files are deleted, and empty directories are removed (in execute mode).

### 3.3 Read-Only and Locked Files
- **Test:** Include files that are read-only or locked by another process.
- **Expected:** Script logs errors for files it cannot delete, continues processing others.

### 3.4 Empty Directories
- **Test:** Run after deleting all files, leaving empty folders.
- **Expected:** Empty directories are removed (in execute mode), or listed for removal (dry-run).

---

## 4. **Error Handling and Edge Cases**

### 4.1 Non-Existent Path
- **Test:** Run with a non-existent or inaccessible path.
- **Expected:** Script logs a clear error and exits safely.

### 4.2 Permission Issues
- **Test:** Run as a user without permission to delete files or folders.
- **Expected:** Script logs permission errors, continues or exits as appropriate.

### 4.3 Network/Mapped Drives
- **Test:** Run on a UNC path or mapped network drive.
- **Expected:** Script works if path is accessible; logs errors if not.

### 4.4 Large Number of Files
- **Test:** Run on a directory with thousands of files.
- **Expected:** Script completes without performance or memory issues; progress and summary are logged.

---

## 5. **Logging and Audit**

### 5.1 Main Log File
- **Test:** Verify all actions, warnings, and errors are logged to the main log.
- **Expected:** Log is clear, non-duplicative, and rotates as expected.

### 5.2 Audit Log (Retention Actions)
- **Test:** In execute mode, verify every deleted file is logged in the audit log.
- **Expected:** Audit log is accurate and complete.

### 5.3 Log Rotation
- **Test:** Fill log to exceed rotation threshold.
- **Expected:** Old logs are archived, new log is created, and no data is lost.

---

## 6. **Script Parameters and Help**

### 6.1 Help Output
- **Test:** Run script with `-Help` or no parameters.
- **Expected:** Help message is displayed, with correct version and usage info.

### 6.2 Custom Log Path
- **Test:** Specify a custom log file path.
- **Expected:** Logs are written to the specified location.

---

## 7. **Environment and Compatibility**

### 7.1 PowerShell Version
- **Test:** Run on supported and unsupported PowerShell versions.
- **Expected:** Script runs on supported versions, logs a warning or error on unsupported.

### 7.2 OS Variants
- **Test:** Run on different Windows Server and client OS versions.
- **Expected:** Script works consistently.

---

## 8. **Safety and Idempotence**

### 8.1 Repeated Runs
- **Test:** Run script multiple times in a row.
- **Expected:** No errors or unexpected behavior; script is idempotent.

### 8.2 Root Path Protection
- **Test:** Attempt to run with system root or critical path as archive path.
- **Expected:** Script refuses to run or logs a critical warning.

---

## 9. **Performance and Stress**

### 9.1 Large Files
- **Test:** Run on directories with very large files.
- **Expected:** Script processes them correctly, logs accurate size info.

### 9.2 Simultaneous Runs
- **Test:** Run multiple instances of the script at once.
- **Expected:** No file lock or concurrency issues; logs are not corrupted.

---

## 10. **Disaster Recovery**

### 10.1 Interrupted Run
- **Test:** Kill the script mid-run.
- **Expected:** Logs are closed cleanly, no partial deletions or corruption.

---

## 11. **Audit and Compliance**

### 11.1 Audit Trail Completeness
- **Test:** Verify that all deletions are traceable via logs and audit logs.
- **Expected:** Satisfies compliance requirements for retention actions.

---

## 12. **Documentation and Usability**

### 12.1 README/Docs Accuracy
- **Test:** Follow the README instructions step-by-step.
- **Expected:** All documented features and warnings are accurate and up-to-date.

---

## 13. **Custom/Advanced Scenarios**

### 13.1 Symlinks/Junctions
- **Test:** Include symlinks or junctions in the archive path.
- **Expected:** Script handles or skips them safely, logs actions.

### 13.2 File System Quotas/Low Disk Space
- **Test:** Run on a nearly full disk.
- **Expected:** Script logs warnings if unable to write logs or complete actions.

---

# Test Tracking Table

| Test # | Description | Pass/Fail | Notes |
|--------|-------------|-----------|-------|
| 1.1    | Dry-Run Mode |           |       |
| 1.2    | Execute Mode |           |       |
| ...    | ...         |           |       |

---

**Note:**  
- Always test in a non-production environment first.
- Review logs after each test for unexpected warnings or errors.
- Update this document as new features or edge cases are discovered. 