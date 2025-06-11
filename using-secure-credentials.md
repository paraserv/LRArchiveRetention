# Using Secure Credentials with ArchiveRetention.ps1

To enhance security and enable automation, `ArchiveRetention.ps1` supports running against network shares (UNC paths) using securely stored credentials. This avoids exposing passwords in scripts or command history and is essential for running the script as a scheduled task or under a different user context.

This guide explains how to create an encrypted credential file and use it with the script.

---

## How It Works

The script uses a cross-platform compatible AES-256 encryption method for secure credential management. This approach ensures that credentials can be securely stored and used on any system, including Windows Server Core, Linux, and macOS.

**Key Features**

- **Strong Encryption**: Uses AES-256, the industry standard for symmetric encryption.
- **Cross-Platform**: Works on any machine with PowerShell.
- **Machine-Specific Key**: An encryption key is generated and stored locally on the machine, protected by file system permissions.
- **Non-Interactive Support**: Designed to work seamlessly with scheduled tasks and service accounts.

---

## Step 1: Create the Encrypted Credential File

You only need to do this once on the server where `ArchiveRetention.ps1` will be executed.

1.  **Log in to the server** with the user account that will run the scheduled task or execute the script.
2.  **Open a PowerShell console.**
3.  **Run the following command:**

    ```powershell
    Get-Credential | Export-CliXml -Path "C:\\Path\\To\\Your\\SecureCreds.xml"
    ```

4.  **A credential prompt will appear.** Enter the username and password for the account that has access to the network share (e.g., `DOMAIN\\ServiceAccount`).
5.  **Verify the file is created.** A file named `SecureCreds.xml` will be created at the path you specified. **Treat this file as sensitive**, and ensure it is stored in a location with appropriate permissions.

---

## Step 2: Use the Credential File with the Script

Once the credential file is created, you can use the `-CredentialXmlPath` parameter to provide it to the script.

### Example Usage

```powershell
.\ArchiveRetention.ps1 -ArchivePath "\\\\FileServer01\\LogRhythmArchives" -RetentionDays 365 -CredentialXmlPath "C:\\Path\\To\\Your\\SecureCreds.xml" -Execute
```

### How the Script Uses the Credential

When you provide the `-CredentialXmlPath`:
1.  The script imports the encrypted credential file.
2.  It creates a temporary PowerShell drive (PSDrive) mapped to the UNC path (`\\\\FileServer01\\LogRhythmArchives`).
3.  It performs all its work using this authenticated, temporary drive.
4.  After the script finishes (whether it succeeds or fails), it automatically removes the temporary drive, leaving no trace of the connection.

This provides a seamless and secure way to manage files on remote shares without compromising on security or reliability.
