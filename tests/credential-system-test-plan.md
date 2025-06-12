# Credential System Test Plan

> **Purpose:** Regression testing template for the LogRhythm Archive Retention credential management system  
> **Components:** Save-Credential.ps1 + ShareCredentialHelper.psm1  
> **Last Updated:** 2025-06-12  

## Overview

This document outlines repeatable tests for the credential management system to ensure functionality remains intact after code changes. Execute these tests before any production deployment.

## Required Output
- **Test Results Log:** A markdown file named `credential-system-test-results-YYYYMMDD.md` must be created to document the outcome of each test. Use `tests/credential-system-test-results-20250612.md` as a template for structure and detail.

## Test Environment Requirements

- **Server:** Windows Server with PowerShell 5.1+ or PowerShell Core 6+
- **Test Share:** Network share accessible for validation (e.g., \\server\share)
- **SSH Access:** Private key authentication configured
- **Credentials:** Valid username/password for test share
- **Clean State:** Clear credential store before testing

---

## Pre-Test Setup

### 1. Clear Existing Credentials
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Remove-Item -Path modules\CredentialStore\*.cred -Force -ErrorAction SilentlyContinue; Remove-Item -Path modules\CredentialStore\.encryption.key -Force -ErrorAction SilentlyContinue"'
```

### 2. Verify Clean State
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Get-ChildItem -Path modules\CredentialStore -Force"'
```
**Expected:** Empty directory or only directory structure

---

## Test Suite

### 1. Authentication & Validation Tests

#### Test 1.1: Bad Password - Quiet Mode
```bash
echo "wrongpassword" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget BadTest1 -SharePath \\SERVER\SHARE -UseStdin -Quiet }"'
```
**Expected:** Clean error message, no credential saved, exit code 1

#### Test 1.2: Bad Password - Normal Mode
```bash
echo "wrongpassword" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget BadTest2 -SharePath \\SERVER\SHARE -UseStdin }"'
```
**Expected:** Detailed error with troubleshooting tips, exit code 1

#### Test 1.3: Bad Password - Verbose Mode
```bash
echo "wrongpassword" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget BadTest3 -SharePath \\SERVER\SHARE -UseStdin -Verbose }"'
```
**Expected:** Full debug info showing username and operations, exit code 1

### 2. Successful Credential Storage Tests

#### Test 2.1: Good Password - Quiet Mode
```bash
echo "$VALID_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget GoodTest1 -SharePath \\SERVER\SHARE -UseStdin -Quiet }"'
```
**Expected:** Minimal output, credential saved successfully, exit code 0

#### Test 2.2: Good Password - Normal Mode
```bash
echo "$VALID_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget GoodTest2 -SharePath \\SERVER\SHARE -UseStdin }"'
```
**Expected:** Success messages with helpful info, exit code 0

#### Test 2.3: Good Password - Verbose Mode
```bash
echo "$VALID_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget GoodTest3 -SharePath \\SERVER\SHARE -UseStdin -Verbose }"'
```
**Expected:** Full debug output showing all operations, exit code 0

### 3. Credential Management Tests

#### Test 3.1: List Saved Credentials
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Import-Module .\modules\ShareCredentialHelper.psm1; Get-SavedCredentials"'
```
**Expected:** List of saved credentials with metadata.

#### Test 3.2: Check Credential Store Files
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Get-ChildItem -Path modules\CredentialStore\*.cred | Select-Object Name, Length, LastWriteTime"'
```
**Expected:** Show all credential files created (~4KB each)

### 4. Integration Tests

#### Test 4.1: Use Saved Credentials with ArchiveRetention
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; .\ArchiveRetention.ps1 -CredentialTarget GoodTest1 -RetentionDays 180"'
```
**Expected:** Seamless integration, network drive mapping, successful execution

#### Test 4.2: Non-existent Credential Target
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; .\ArchiveRetention.ps1 -CredentialTarget NonExistentTarget -RetentionDays 180"'
```
**Expected:** Clear error message with instructions, exit code 1

### 5. Error Handling Tests

#### Test 5.1: Invalid Share Path
```bash
echo "$VALID_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget InvalidShare -SharePath \\nonexistent.server\share -UseStdin -Quiet }"'
```
**Expected:** Network error detection, exit code 1

#### Test 5.2: Duplicate Credential Target
```bash
echo "$VALID_PASSWORD" | ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& { cd C:\LogRhythm\Scripts\ArchiveV2; .\Save-Credential.ps1 -CredentialTarget GoodTest1 -SharePath \\SERVER\SHARE -UseStdin }"'
```
**Expected:** Overwrite existing credential with confirmation, exit code 0

### 6. Credential Removal Tests
#### Test 6.1: Remove Credential with WhatIf
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Import-Module .\modules\ShareCredentialHelper.psm1; Remove-ShareCredential -Target GoodTest2 -WhatIf"'
```
**Expected:** Show what would be removed without actually removing.

#### Test 6.2: Remove Credential (Actual)
**Note:** This test requires an interactive 'Yes' confirmation because the `-Force` switch is not yet implemented for `Remove-ShareCredential`. For automated testing, this step should be skipped or handled with an expect script.
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Import-Module .\modules\ShareCredentialHelper.psm1; Remove-ShareCredential -Target GoodTest2"'
```
**Expected:** Interactive prompt to confirm removal. Credential file is deleted after confirmation.

### 7. Performance & Scale Tests

#### Test 7.1: Integration with File Processing
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; .\ArchiveRetention.ps1 -CredentialTarget GoodTest3 -RetentionDays 90 -Verbose"'
```
**Expected:** Full functionality with file processing, performance metrics logged

#### Test 7.2: Final Summary
```bash
ssh -i ~/.ssh/id_rsa_windows administrator@SERVER 'powershell -NoProfile -ExecutionPolicy Bypass -Command "cd C:\LogRhythm\Scripts\ArchiveV2; Get-ChildItem -Path modules\CredentialStore\*.cred | Select-Object Name, Length, LastWriteTime"'
```
**Expected:** Summary of all created credentials

---

## Validation Criteria

### Security Requirements
- [ ] Bad passwords properly rejected with clear error messages
- [ ] Good passwords validated against actual network share before storage
- [ ] Credentials encrypted with AES-256 + machine binding
- [ ] File permissions properly restricted

### SSH Compatibility
- [ ] Non-interactive mode works with `-UseStdin` parameter via piping
- [ ] `-Quiet` mode provides minimal output for automation
- [ ] Error handling provides clean messages without stack traces

### Integration Requirements
- [ ] Seamless integration with ArchiveRetention.ps1
- [ ] Automatic network drive mapping
- [ ] Proper error handling for missing credentials

### Performance Requirements
- [ ] Credential save/retrieval operations complete in <5 seconds
- [ ] Network validation completes within timeout period
- [ ] No memory leaks or resource issues

---

## Test Execution Checklist

- [ ] **Environment Setup:** Server accessible, credentials available
- [ ] **Pre-Test Cleanup:** Credential store cleared
- [ ] **Authentication Tests:** All bad password scenarios tested
- [ ] **Storage Tests:** All good password scenarios tested
- [ ] **Management Tests:** List and file operations tested
- [ ] **Integration Tests:** ArchiveRetention.ps1 integration verified
- [ ] **Error Handling:** All error scenarios tested
- [ ] **Performance Tests:** Scale and performance verified
- [ ] **Post-Test Validation:** All criteria met
- [ ] **Results Documented:** Test results recorded in separate document

---

## Notes for Test Execution

1. **Replace Placeholders:** Update `SERVER` and `SHARE`. For `$VALID_PASSWORD`, source it securely (e.g., from Keychain: `VALID_PASSWORD=$(security find-generic-password ... -w)`) before running tests.
2. **Document Results:** Create a `credential-system-test-results-YYYYMMDD.md` file and record all outputs for each test case.
3. **Track Issues:** Note any deviations from expected behavior.
4. **Performance Metrics:** Record timing and performance data
5. **Regression Testing:** Run full suite after any code changes

---

*This test plan should be executed in full before any production deployment or after significant code changes to ensure system reliability.* 