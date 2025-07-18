# LogRhythm Archive Retention Manager

> **Versioning Note:** The authoritative version is defined in `ArchiveRetention.ps1` (`$SCRIPT_VERSION`).

---

## Introduction

This is a high-performance PowerShell script for managing the retention of files, particularly LogRhythm Inactive Archives. It automates the cleanup of old archive files to free up disk space while providing detailed logging, reporting, and flexible credential management. The latest version includes performance optimizations and enhanced logging capabilities.

This script is specifically designed for use with [Exabeam's LogRhythm SIEM](https://www.exabeam.com/platform/logrhythm-siem/) (LR7) self-hosted environments, targeting the files generated by the [Data Processor's "InactiveArchivePath" value](https://docs.logrhythm.com/lrsiem/docs/change-archive-location). LR7 Inactive Archives contain the raw logs collected by LR System Monitor Agents and saved by the LogRhythm Mediator Server Service. The SIEM does not delete these files and so administrators must manage its retention using other methods, such as this script. Retaining these archive log files (.lca) allows you to utilize LogRhythm's SecondLook Wizard to reprocess and reindex the logs back into the SIEM, if needed. Inactive Archives do not affect the current searchability (indexing) of the SIEM. **Warning:** Do not configure this script to target LogRhythm's Active Archives (.lua). These are configured within the product with a value of 1 to 7 days and then automatically age into the Inactive Archive path.

> **Disclaimer:** **Use at your own risk.** This script deletes files according to your parameters. Ensure you have backups and test thoroughly in a non-production environment before production use. The authors are not liable for any data loss or damages.

## Features

- **Safe Execution**: Dry-run mode by default, requires `-Execute` flag for actual deletions
- **Minimum Retention Enforcement**: The script will never delete files newer than $MINIMUM_RETENTION_DAYS, which is hard-coded in the script for safety (default: 90 days, configurable by editing the script). If you specify a lower value with `-Execute`, the script will log a warning and enforce the minimum. Dry-run mode will warn but proceed with any value, showing what would be in scope for deletion with the given parameters.
- **Comprehensive Logging & Auditing**: All script activity is logged with timestamps, including file statistics, progress updates, error handling, and detailed output with `-Verbose`. In execute mode, every file deleted is also recorded in a dedicated audit log (`retention_actions/retention_*.log`) for compliance and traceability. Dry-run mode will show what would be deleted, but only actual deletions are audit-logged.
- **Flexible Configuration**: Customize retention periods (e.g., `-RetentionDays 1095`), archive locations (`-ArchivePath`), and file types to include (default: `.lca`).
- **Performance Optimized**: Efficient file scanning and processing, with real-time progress updates and robust error handling.
- **Flexible Credential Management**: Supports service account permissions or securely saved credentials (via `Save-Credential.ps1`) for network access.

## Requirements

- Windows Server
- PowerShell 5.1 or later
- Sufficient permissions on archive directories (local or UNC share)

## Installation

1. Copy the project to the Windows server (this includes the *.ps1 files and the modules and docs directories)
2. Place it in a directory with appropriate permissions (e.g., `C:\LogRhythm\Scripts\LRArchiveRetention\`) so that only authorized administrators can modify or execute the script
3. Ensure the script has read/write permissions to the archive directories

## Usage

```powershell
# Show help and available parameters
.\ArchiveRetention.ps1 -Help

# Dry run for a local path (shows what would be deleted)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90

# Live execution for a local path (deletes files)
.\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90 -Execute

# Live execution for a network share, assuming process has full access to the share
.\ArchiveRetention.ps1 -ArchivePath "\\REMOTE_SYSTEM\LRArchives\Inactive" -RetentionDays 180 -Execute

# Live execution for a network share using an encrypted saved credential (see Credential Management section for details)
.\ArchiveRetention.ps1 -CredentialTarget "REMOTE_SYSTEM" -RetentionDays 180 -Execute
```

> **Note:** As a safety measure, the script will never delete files newer than the $MINIMUM_RETENTION_DAYS set in the script (default: 90 days), even if you specify a lower value with `-Execute`.

## Credential Management

This section outlines methods for `ArchiveRetention.ps1` to access network shares.

### Option 1: Using Service Accounts for Network Access

A common and often recommended approach, especially for scheduled tasks, is to run `ArchiveRetention.ps1` under a dedicated service account. If this service account has the necessary read/write/delete permissions to the target network share, then `ArchiveRetention.ps1` can access the share using these inherent permissions. In this scenario, you typically do not need to use the `-CredentialTarget` parameter or the `Save-Credential.ps1` helper script.

### Option 2: Using the `Save-Credential.ps1` Helper Script

For scenarios where using a service account's inherent permissions is not feasible or desired (e.g., manual execution, a preference for explicit credential objects, or if the running account lacks direct share access), this project includes the `Save-Credential.ps1` helper script. This utility allows you to securely save an encrypted credential that `ArchiveRetention.ps1` can then use.

This is typically a one-time setup per credential.

#### Saving Credentials with `Save-Credential.ps1`

##### Method A: Interactive (Recommended for Manual Setup)
This is the most secure method for manual use. It uses the standard Windows credential prompt, and your password is never exposed in plaintext in the script or your shell history.
```powershell
# The script will prompt you for a password in a secure dialog box.
.\Save-Credential.ps1 -Target "REMOTE_SYSTEM" -SharePath "\\REMOTE_SYSTEM\LRArchives"
```

##### Method B: Automated (For Scripts and Scheduled Tasks using `Save-Credential.ps1`)
If you need to provide a password non-interactively to `Save-Credential.ps1` (e.g., for an initial automated setup of the local credential), using its `-UseStdin` parameter is a secure method, if used properly. This approach avoids exposing the password in command history or process lists and is suitable for piping a password from an external secrets management tool.

**General Approach with a Secrets Management Tool:**
Most secrets management tools provide a Command-Line Interface (CLI) that can be used to retrieve secrets. You would use your vault's CLI to fetch the password and then pipe it to `Save-Credential.ps1`.
```powershell
# Conceptual Example: Replace with your specific vault's CLI command
# This securely pipes the password from your vault to Save-Credential.ps1
Get-SecretFromYourVaultCLI -SecretName "REMOTE_SYSTEM_Password" | .\Save-Credential.ps1 -Target "REMOTE_SYSTEM" -SharePath "\\REMOTE_SYSTEM\LRArchives" -UseStdin -Quiet
```

**Common Secrets Management Tools with CLI Support:**
Many tools can be used in this way, including but not limited to:
*   **PowerShell SecretManagement:** Microsoft's native solution (modules: `Microsoft.PowerShell.SecretManagement` and `Microsoft.PowerShell.SecretStore`). Use `Get-Secret`.
*   **1Password:** Uses the `op` CLI (e.g., `op read op://vault/item/password`).
*   **HashiCorp Vault:** Uses the `vault` CLI (e.g., `vault kv get -field=password secret/path`).
*   **Azure Key Vault:** Can be accessed via Azure CLI (`az keyvault secret show`) or Azure PowerShell (`Get-AzKeyVaultSecret`).
*   **Bitwarden:** Uses the `bw` CLI (e.g., `bw get password item_name`).
*   **Delinea (Thycotic) Secret Server:** Offers various integration methods, often including CLI or API access.

#### Using Saved Credentials in ArchiveRetention.ps1
Once a credential has been saved using `Save-Credential.ps1`, you can reference it in `ArchiveRetention.ps1` by the target name you chose. The main script will automatically retrieve the encrypted credential and use it to access the share.
```powershell
# Use the saved credential (no need to specify the share path again)
.\ArchiveRetention.ps1 -CredentialTarget "REMOTE_SYSTEM" -RetentionDays 180

# With execution
.\ArchiveRetention.ps1 -CredentialTarget "REMOTE_SYSTEM" -RetentionDays 180 -Execute
```

### Important Considerations for Credential Strategy
- **`ArchiveRetention.ps1` and External Vaults:** The main `ArchiveRetention.ps1` script does **not** directly query external secrets management tools or vaults at runtime. It relies on either the inherent permissions of the account running the script (see Option 1) or a credential previously saved locally and encrypted by `Save-Credential.ps1` (see Option 2).
- **Purpose of External Vaults with `Save-Credential.ps1`:** If you use an external secrets management tool with `Save-Credential.ps1`, its role is to securely provide the password for the *one-time setup* of the local encrypted credential.

**Security Notes:**
- Credentials are encrypted using a hybrid model for maximum security and compatibility. On Windows, the script uses the native **Windows Data Protection API (DPAPI)** by default. On non-Windows systems or if DPAPI is unavailable, it uses **AES-256 encryption**. In both cases, credentials are tied to the machine where they were created.

## Parameters

| Parameter              | Type         | Required | Description                                                                 |
|------------------------|--------------|----------|-----------------------------------------------------------------------------|
| `-ArchivePath`         | string       | Conditional | **Required if not using `-CredentialTarget`**. Path to local directory or network share. |
| `-CredentialTarget`    | string       | Conditional | **Required if not using `-ArchivePath`**. Name of saved credential for network share. |
| `-RetentionDays`       | int          | Yes      | Number of days to retain files, based on file modified date (larger number of days deletes fewer files).  |
| `-Execute`             | switch       | False    | Actually deletes files. If omitted, the script runs in safe dry-run mode.   |
| `-Verbose`             | switch       | False    | Enables detailed, step-by-step logging to the console during execution.     |
| `-LogPath`             | string       | No       | Custom path to the script's log file (default: `script_logs` folder).       |
| `-MaxRetries`          | int          | No       | Max retries for failed file deletions (default: 3).                         |
| `-RetryDelaySeconds`   | int          | No       | Delay between deletion retries in seconds (default: 1).                     |
| `-SkipDirCleanup`      | switch       | False    | Skips the final step of removing empty directories after file processing.   |
| `-IncludeFileTypes`    | string[]     | No       | File extensions to include, e.g., `@('.lca', '.txt')` (default: `@('.lca')`).|

## Best Practices

1. **Backup first**: Ensure you have backups before running with `-Execute`
2. **Test with dry-run**: Use dry-run and `-Verbose` to verify what will be deleted
3. **Start small**: Test on a subset before running on large datasets
4. **Review logs**: Check logs after each run for warnings or errors
5. **Schedule wisely**: Run during maintenance windows, not during peak hours
6. **Use UNC paths**: For network shares, always use UNC paths (e.g., `\\server\share`)
7. **Run as appropriate user**: Ensure the script runs with sufficient permissions

> **Note:** This section is for end users. For developer and automated test plans, see the `/tests` directory.

## Testing & Validation

**How to Safely Test the Script:**
1. **Dry Run**:
   - Run the script without `-Execute` to see what files would be deleted.
   - Example:
     ```powershell
     .\ArchiveRetention.ps1 -ArchivePath "D:\LogRhythmArchives\Inactive" -RetentionDays 90
     ```
   - Review the output and logs to confirm only the intended files are in scope.
2. **Test with a Small Directory**:
   - Use a test directory with sample files to validate behavior.
   - Adjust `-RetentionDays` to test edge cases (e.g., files just above/below the threshold).
3. **Check Logs**:
   - Review `script_logs/ArchiveRetention.log` for a summary and any warnings/errors.
   - In dry-run, no files are deleted; in execute mode, check `retention_actions/retention_*.log` for audit trail.
4. **Validate Results**:
   - After running with `-Execute`, verify that only files older than the retention period are deleted.
   - Confirm no newer files or unintended files are affected.
5. **Restore from Backup (if needed)**:
   - Always ensure you can restore files from backup before running in production.

## Troubleshooting

| Issue                        | Possible Causes & Solutions                                                                 |
|------------------------------|------------------------------------------------------------------------------------------|
| Access Denied                | Run as admin; check share and NTFS permissions; verify account context                    |
| Files Not Being Deleted      | Files may not meet retention; check path and permissions; ensure files are not locked     |
| Mapped Drives Not Available  | Use UNC paths; mapped drives are session-specific                                         |
| File Not Found Errors        | Check for broken shortcuts, inaccessible subfolders, long paths, or special characters    |
| 'Access is denied'           | Insufficient permissions; check both share and NTFS permissions                           |
| Performance Issues           | Run during off-peak; ensure server/network can handle load                                |
| Log File Growth              | Main log rotates at 10MB; archive/rotate retention logs as needed                        |
| Minimum Retention Not Honored| Script enforces minimum retention in execute mode                                         |

- For more details, see logs in `script_logs/` and `retention_actions/`.

## Logging

| Log File Location                        | Description                                                      |
|-------------------------------------------|------------------------------------------------------------------|
| `script_logs/ArchiveRetention.log`        | Main script log (current run): all activity, config, progress    |
| `script_logs/ArchiveRetention_*.log`      | Rotated/archived main logs (previous runs, timestamped)          |
| `retention_actions/retention_*.log`       | Audit logs: every file deleted in execute mode                   |

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔐 Security & Development

This project includes comprehensive security protections and development safeguards. For complete security framework documentation, setup instructions, and developer guidelines, see [`docs/pre-commit-security-setup.md`](pre-commit-security-setup.md).

## Support

Contributions are welcome! Please follow the standard GitHub fork and pull request workflow.

## Author

Nathan Church
Exabeam Professional Services
