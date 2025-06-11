#!/bin/bash
# run-archive-retention-tests.sh
#
# Run all core ArchiveRetention.ps1 test scenarios via SSH from your Mac/Linux machine.
# Usage: bash tests/RunArchiveRetentionTests.sh

# --- Configuration ---
SSH_USER="administrator"
SSH_HOST="10.20.1.200"
SSH_KEY="~/.ssh/id_rsa_windows"
CREDENTIAL_TARGET="10.20.1.7"
REMOTE_SCRIPT_DIR='C:\LogRhythm\Scripts\ArchiveV2'
# In bash, to represent a literal UNC path in a variable, it's safest to use single quotes
# or correctly escaped double quotes. We use double quotes here for consistency.
ARCHIVE_PATH="\\\\10.20.1.7\\LRArchives"

SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o LogLevel=ERROR ${SSH_USER}@${SSH_HOST}"

# --- Helper Functions ---

# Function for tests targeting the network share using -CredentialTarget
run_network_test() {
  local test_name="$1"
  local ps_args="$2"

  echo -e "\n--- Running Network Test: $test_name ---"

  # Command for the NetworkShare parameter set
  local ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -CredentialTarget '$CREDENTIAL_TARGET' $ps_args -Verbose"

  local final_ssh_command="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $ps_command }\""
  $SSH_CMD "$final_ssh_command"
}

# Function for tests targeting a local path on the remote server
run_local_test() {
  local test_name="$1"
  local ps_args="$2"
  # Use a dummy local path for testing purposes
  local local_archive_path="C:\\Temp\\ArchiveTest"

  echo -e "\n--- Running Local Test: $test_name ---"

  # Command for the LocalPath parameter set
  local ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -ArchivePath '$local_archive_path' $ps_args -Verbose"

  local final_ssh_command="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $ps_command }\""
  $SSH_CMD "$final_ssh_command"
}

# --- Test Cases ---

# Network Share Tests
run_network_test "Dry-Run Mode (No Deletions, 20 days)" "-RetentionDays 20 -SkipDirCleanup"
run_network_test "Execute Mode (Deletions, 20 days)" "-RetentionDays 20 -Execute -SkipDirCleanup"
run_network_test "Minimum Retention (Below Minimum, 10 days, Dry-Run)" "-RetentionDays 10 -SkipDirCleanup"
run_network_test "Minimum Retention (Below Minimum, 10 days, Execute)" "-RetentionDays 10 -Execute -SkipDirCleanup"
run_network_test "Maximum Retention (3650 days, Execute)" "-RetentionDays 3650 -Execute -SkipDirCleanup"
run_network_test "Include Only .lca and .txt Files (20 days)" "-IncludeFileTypes .lca,.txt -RetentionDays 20 -SkipDirCleanup"

# Local Path Tests (using a dummy path for syntax validation)
run_local_test "Custom Log Path (20 days)" "-LogPath 'C:\\Temp\\custom.log' -RetentionDays 20"

# --- Special Test Cases (cannot use the helper function) ---

echo -e "\n--- Running Test: Non-Existent Archive Path (Local) ---"
NON_EXISTENT_PATH="C:\\DoesNotExist"
non_existent_ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -ArchivePath '$NON_EXISTENT_PATH' -RetentionDays 20 -Verbose"
$SSH_CMD "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $non_existent_ps_command }\""

echo -e "\n--- Running Test: Help Output ---"
help_ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -Help"
$SSH_CMD "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $help_ps_command }\""

echo -e "\n--- All tests complete. ---"