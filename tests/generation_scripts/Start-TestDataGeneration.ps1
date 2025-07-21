#Requires -Version 7.0
<#
.SYNOPSIS
    Starts the test data generation process on NAS with proper logging and monitoring
.DESCRIPTION
    This script starts GenerateTestData.ps1 to create 2TB of test data on the NAS share
    using saved credentials and logs all output for monitoring.
.PARAMETER LogPath
    Path where the log file will be created (default: C:\LR\Scripts\LRArchiveRetention\logs)
.EXAMPLE
    .\Start-TestDataGeneration.ps1
#>

[CmdletBinding()]
param(
    [string]$LogPath = "C:\LR\Scripts\LRArchiveRetention\logs"
)

# Script configuration
$ErrorActionPreference = 'Stop'
$scriptPath = "C:\LR\Scripts\LRArchiveRetention"
$testDataScript = Join-Path $scriptPath "tests\GenerateTestData.ps1"
$nasPath = "\\10.20.1.7\LRArchives\TestData"
$credentialTarget = "NAS_CREDS"
$targetSize = 2TB

# Create log directory if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Generate log filename with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogPath "TestDataGeneration_$timestamp.log"

# Function to write to both console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $logFile -Value $logEntry
}

Write-Log "=== Test Data Generation Started ===" "INFO"
Write-Log "Target Path: $nasPath" "INFO"
Write-Log "Target Size: $($targetSize / 1TB) TB" "INFO"
Write-Log "Log File: $logFile" "INFO"

# Verify the test data script exists
if (-not (Test-Path $testDataScript)) {
    Write-Log "ERROR: Test data script not found at: $testDataScript" "ERROR"
    exit 1
}

# Import credential helper module
try {
    $modulePath = Join-Path $scriptPath "modules\ShareCredentialHelper.psm1"
    Import-Module $modulePath -Force
    Write-Log "Credential module loaded successfully" "INFO"
} catch {
    Write-Log "ERROR: Failed to load credential module: $_" "ERROR"
    exit 1
}

# Verify NAS credentials exist
try {
    $savedCreds = Get-SavedCredentials | Where-Object { $_.Target -eq $credentialTarget }
    if (-not $savedCreds) {
        Write-Log "ERROR: No saved credentials found for target: $credentialTarget" "ERROR"
        Write-Log "Please run Save-Credential.ps1 first to save NAS credentials" "ERROR"
        exit 1
    }
    Write-Log "Found saved credentials for: $credentialTarget" "INFO"
} catch {
    Write-Log "ERROR: Failed to check credentials: $_" "ERROR"
    exit 1
}

# Create the job script block
$jobScript = {
    param(
        [string]$TestDataScript,
        [string]$NasPath,
        [string]$CredentialTarget,
        [long]$TargetSize
    )
    
    # Run the test data generation script
    & pwsh -File $TestDataScript -RootPath $NasPath -TargetTotalSize $TargetSize -UseCredential $CredentialTarget -Verbose
}

# Start the background job
Write-Log "Starting test data generation job..." "INFO"
try {
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $testDataScript, $nasPath, $credentialTarget, $targetSize -Name "TestDataGeneration"
    Write-Log "Job started successfully with ID: $($job.Id)" "INFO"
} catch {
    Write-Log "ERROR: Failed to start job: $_" "ERROR"
    exit 1
}

# Monitor the job
Write-Log "Monitoring job progress..." "INFO"
Write-Log "Press Ctrl+C to stop monitoring (job will continue running)" "INFO"

$lastOutputCount = 0
try {
    while ($job.State -eq 'Running') {
        # Get job output
        $output = Receive-Job -Job $job -Keep
        
        # Process new output lines
        if ($output.Count -gt $lastOutputCount) {
            $newOutput = $output[$lastOutputCount..($output.Count - 1)]
            foreach ($line in $newOutput) {
                if ($line -match 'WARNING') {
                    Write-Log $line "WARN"
                } elseif ($line -match 'ERROR') {
                    Write-Log $line "ERROR"
                } else {
                    Write-Log $line "INFO"
                }
            }
            $lastOutputCount = $output.Count
        }
        
        # Show job status
        $runtime = (Get-Date) - $job.PSBeginTime
        $status = "Job Status: $($job.State) | Runtime: $([Math]::Round($runtime.TotalMinutes, 2)) minutes"
        Write-Host "`r$status" -NoNewline
        
        # Wait before next check
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Log "Monitoring interrupted: $_" "WARN"
}

# Get final job results
Write-Log "" "INFO"  # New line after status
Write-Log "Job completed with state: $($job.State)" "INFO"

# Capture any remaining output
$finalOutput = Receive-Job -Job $job
foreach ($line in $finalOutput[$lastOutputCount..($finalOutput.Count - 1)]) {
    if ($line) {
        Write-Log $line "INFO"
    }
}

# Check job status
if ($job.State -eq 'Failed') {
    Write-Log "Job failed! Error details:" "ERROR"
    $job.ChildJobs | ForEach-Object {
        if ($_.Error) {
            Write-Log $_.Error "ERROR"
        }
    }
    exit 1
} elseif ($job.State -eq 'Completed') {
    Write-Log "Test data generation completed successfully!" "SUCCESS"
    Write-Log "Total runtime: $([Math]::Round(((Get-Date) - $job.PSBeginTime).TotalMinutes, 2)) minutes" "INFO"
}

# Clean up job
Remove-Job -Job $job -Force

Write-Log "=== Test Data Generation Finished ===" "INFO"
Write-Log "Log saved to: $logFile" "INFO"