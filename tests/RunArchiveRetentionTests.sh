#!/bin/bash
set -e
# run-archive-retention-tests.sh
#
# Run all core ArchiveRetention.ps1 test scenarios via SSH from your Mac/Linux machine.
# Usage: bash tests/RunArchiveRetentionTests.sh

# --- Configuration ---
SSH_USER="administrator"
SSH_HOST="10.20.1.200"
SSH_KEY="~/.ssh/id_rsa_windows"
CREDENTIAL_TARGET="MainRun"
REMOTE_SCRIPT_DIR='C:\LogRhythm\Scripts\ArchiveV2'
# In bash, to represent a literal UNC path in a variable, it's safest to use single quotes
# or correctly escaped double quotes. We use double quotes here for consistency.
ARCHIVE_PATH="\\\\10.20.1.7\\LRArchives"

SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o LogLevel=ERROR ${SSH_USER}@${SSH_HOST}"

# Arrays to store summary results
TEST_NAMES=()
TEST_RESULTS=()

record_result() {
  local name="$1"
  local result_code="$2"
  local status="PASS"
  if [ $result_code -ne 0 ]; then
    status="FAIL($result_code)"
  fi
  TEST_NAMES+=("$name")
  TEST_RESULTS+=("$status")
}

# --- Helper Functions ---

# Utility to invoke a remote PowerShell command and retry if ArchiveRetention exits
# with the special exit-code 9 (single-instance lock in use). Ensures sequential
# execution when tests are run in quick succession.
#   $1 – human-readable test name (for logging)
#   $2 – full PowerShell command to execute remotely (already properly quoted)
run_with_lock_retry() {
  local test_name="$1"
  local ps_command="$2"

  local max_retries=30   # ~5 minutes max (30 * 10s)
  local sleep_seconds=10
  local attempt=0

  while true; do
    echo -e "\n--- Running Test: $test_name (attempt $((attempt+1))) ---"
    $SSH_CMD "$ps_command"
    local exit_code=$?

    # 9 => lock in use, wait and retry
    if [ $exit_code -eq 9 ]; then
      if [ $attempt -ge $((max_retries-1)) ]; then
        echo "!!! Gave up waiting for lock after $max_retries attempts."
        return 9
      fi
      echo "Another instance still running. Waiting ${sleep_seconds}s..."
      sleep $sleep_seconds
      attempt=$((attempt+1))
      continue
    fi

    # Return whatever exit code we received (0 == pass)
    return $exit_code
  done
}

# Function for tests targeting the network share using -CredentialTarget
run_network_test() {
  local test_name="$1"
  local ps_args="$2"

  local ps_core="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -CredentialTarget '$CREDENTIAL_TARGET' $ps_args -Verbose"
  local final_ssh_command="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $ps_core }\""

  run_with_lock_retry "$test_name" "$final_ssh_command"
  local rc=$?
  record_result "$test_name" $rc
}

# Function for tests targeting a local path on the remote server
run_local_test() {
  local test_name="$1"
  local ps_args="$2"
  local local_archive_path="C:\\Temp\\ArchiveTest"

  local ps_core="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -ArchivePath '$local_archive_path' $ps_args -Verbose"
  local final_ssh_command="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $ps_core }\""

  run_with_lock_retry "$test_name" "$final_ssh_command"
  local rc=$?
  record_result "$test_name" $rc
}

# Concurrency lock test: ensure second instance exits with code 9
run_concurrency_test() {
  local test_name="Concurrency Lock (Second instance exits with code 9)"

  echo -e "\n--- Running Test: $test_name ---"

  # Launch first instance in a background PowerShell job on the server (holds lock ~15s)
  local first_ps="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -CredentialTarget '$CREDENTIAL_TARGET' -RetentionDays 20 -Verbose; Start-Sleep -Seconds 15"
  local launch_bg="powershell -NoProfile -ExecutionPolicy Bypass -Command \"Start-Job -ScriptBlock { $first_ps } | Out-Null\""
  $SSH_CMD "$launch_bg"

  # Give the job a moment to acquire the lock
  sleep 2

  # Attempt second run; should fail fast with exit code 9
  local second_cmd="powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -CredentialTarget '$CREDENTIAL_TARGET' -RetentionDays 20 -Verbose }\""
  $SSH_CMD "$second_cmd"
  local exit_code=$?

  # Clean up jobs on remote (best effort)
  $SSH_CMD "powershell -NoProfile -ExecutionPolicy Bypass -Command \"Get-Job | Receive-Job -Keep | Out-Null; Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue\"" || true

  # Evaluate result: expect 9 to PASS
  if [ $exit_code -eq 9 ]; then
    record_result "$test_name" 0
  else
    record_result "$test_name" $exit_code
  fi
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

# Concurrency test must come before special cases that rely on script availability
run_concurrency_test

# --- Special Test Cases (cannot use the helper function) ---

echo -e "\n--- Running Test: Non-Existent Archive Path (Local) ---"
NON_EXISTENT_PATH="C:\\DoesNotExist"
non_existent_ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -ArchivePath '$NON_EXISTENT_PATH' -RetentionDays 20 -Verbose"
run_with_lock_retry "Non-Existent Archive Path (Local)" "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $non_existent_ps_command }\""
record_result "Non-Existent Archive Path (Local)" $?

echo -e "\n--- Running Test: Help Output ---"
help_ps_command="cd '$REMOTE_SCRIPT_DIR'; .\\ArchiveRetention.ps1 -Help"
run_with_lock_retry "Help Output" "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& { $help_ps_command }\""
record_result "Help Output" $?

echo -e "\n===== TEST SUMMARY ====="
printf "%-3s | %-45s | %-10s\n" "#" "Test" "Result"
printf -- "%-3s-+-%-45s-+-%-10s\n" "---" "---------------------------------------------" "----------"
for idx in "${!TEST_NAMES[@]}"; do
  printf "%-3s | %-45s | %-10s\n" "$((idx+1))" "${TEST_NAMES[$idx]}" "${TEST_RESULTS[$idx]}"
done

# Absolute path to this script's directory (for placing summary file here)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Write to local summary log inside tests dir
summary_file="$SCRIPT_DIR/summary_$(date +%Y%m%d_%H%M%S).log"
{
  echo "# ArchiveRetention Test Summary ($(date))"
  for idx in "${!TEST_NAMES[@]}"; do
    echo "$((idx+1)). ${TEST_NAMES[$idx]} - ${TEST_RESULTS[$idx]}"
  done
} > "$summary_file"

echo -e "\nSummary written to $summary_file\n"