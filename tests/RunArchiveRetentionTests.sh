# (This file will be renamed to run-archive-retention-tests.sh)
# run-archive-retention-tests.sh
#
# Run all core ArchiveRetention.ps1 test scenarios via SSH from your Mac/Linux machine.
# Usage: bash RunArchiveRetentionTests.sh
#
# Requirements:
# - SSH key and server details as in ide_reference.md
# - ArchiveRetention.ps1 and test data present on the server
#
# This script will:
# - Run each test scenario
# - Print output for each
# - Make it easy to extend with more scenarios
#
# See test-plan.md and readme-test-automation.md for details.

SSH="ssh -i ~/.ssh/id_rsa_windows -o StrictHostKeyChecking=no -o LogLevel=ERROR administrator@10.20.1.200"
# Using Windows Credential Manager with the service account
CREDENTIAL_TARGET="10.20.1.7"
BASE_CMD="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { cd 'C:\\LogRhythm\\Scripts\\ArchiveV2'; .\\ArchiveRetention.ps1 -ArchivePath '\\\\10.20.1.7\\LRArchives' -CredentialTarget '$CREDENTIAL_TARGET'"

run_test() {
  local desc="$1"
  local args="$2"
  echo "\n=== $desc ==="
  $SSH "$BASE_CMD $args -Verbose }\""
}

run_test "Dry-Run Mode (No Deletions, 20 days)" "-RetentionDays 20"
run_test "Execute Mode (Deletions, 20 days)" "-RetentionDays 20 -Execute"
run_test "Minimum Retention (Below Minimum, 10 days, Dry-Run)" "-RetentionDays 10"
run_test "Minimum Retention (Below Minimum, 10 days, Execute)" "-RetentionDays 10 -Execute"
run_test "Maximum Retention (3650 days, Execute)" "-RetentionDays 3650 -Execute"
run_test "Include Only .lca and .txt Files (20 days)" "-RetentionDays 20 -IncludeFileTypes .lca,.txt"
# Skipping ExcludeFileTypes test: parameter not supported
run_test "Custom Log Path (20 days)" "-RetentionDays 20 -LogPath '\\\\10.20.1.7\\LRArchives\\Test\\custom.log'"
# For Non-Existent Archive Path, override the base command
nonexistent_cmd="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { cd 'C:\\LogRhythm\\Scripts\\ArchiveV2'; .\\ArchiveRetention.ps1 -ArchivePath '\\\\10.20.1.7\\DoesNotExist' -RetentionDays 20 -Verbose }\""
echo "\n=== Non-Existent Archive Path ==="
$SSH "$nonexistent_cmd"
# For Help Output, run with only -Help
help_cmd="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { cd 'C:\\LogRhythm\\Scripts\\ArchiveV2'; .\\ArchiveRetention.ps1 -Help }\""
echo "\n=== Help Output ==="
$SSH "$help_cmd"
run_test "Non-Existent Archive Path" "-RetentionDays 20 -ArchivePath '\\\\10.20.1.7\\DoesNotExist'"
run_test "Help Output" "-Help"
run_test "Custom Retention Actions Path (20 days, Execute)" "-RetentionDays 20 -RetentionActionsPath '\\\\10.20.1.7\\LRArchives\\custom_retention.log' -Execute"

# Add more run_test calls for additional scenarios as needed 