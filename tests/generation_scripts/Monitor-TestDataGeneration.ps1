#Requires -Version 7.0
<#
.SYNOPSIS
    Monitors running test data generation jobs
.DESCRIPTION
    This script monitors any running test data generation background jobs
    and displays their progress and output.
.EXAMPLE
    .\Monitor-TestDataGeneration.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Function to format size
function Format-Size {
    param([long]$Size)
    
    if ($Size -gt 1TB) {
        return "{0:N2} TB" -f ($Size / 1TB)
    } elseif ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } else {
        return "{0:N2} KB" -f ($Size / 1KB)
    }
}

# Find test data generation jobs
$jobs = Get-Job | Where-Object { $_.Name -like "*TestDataGeneration*" }

if ($jobs.Count -eq 0) {
    Write-Host "No test data generation jobs found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To start a new test data generation job, run:"
    Write-Host "  .\Start-TestDataGeneration.ps1" -ForegroundColor Cyan
    exit 0
}

Write-Host "Found $($jobs.Count) test data generation job(s):" -ForegroundColor Green
Write-Host ""

foreach ($job in $jobs) {
    $runtime = if ($job.PSEndTime) {
        $job.PSEndTime - $job.PSBeginTime
    } else {
        (Get-Date) - $job.PSBeginTime
    }
    
    Write-Host "Job ID: $($job.Id)" -ForegroundColor Cyan
    Write-Host "  Name: $($job.Name)"
    Write-Host "  State: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Running') { 'Green' } elseif ($job.State -eq 'Failed') { 'Red' } else { 'Yellow' })
    Write-Host "  Started: $($job.PSBeginTime)"
    Write-Host "  Runtime: $([Math]::Round($runtime.TotalMinutes, 2)) minutes"
    
    if ($job.State -eq 'Running') {
        Write-Host ""
        Write-Host "Recent output:" -ForegroundColor Yellow
        
        # Get last 10 lines of output
        $output = Receive-Job -Job $job -Keep
        if ($output.Count -gt 0) {
            $recentOutput = $output[([Math]::Max(0, $output.Count - 10))..($output.Count - 1)]
            foreach ($line in $recentOutput) {
                if ($line) {
                    Write-Host "  $line"
                }
            }
        } else {
            Write-Host "  (No output yet)"
        }
        
        Write-Host ""
        Write-Host "To continue monitoring this job, run:" -ForegroundColor Cyan
        Write-Host "  Receive-Job -Id $($job.Id) -Keep -Wait" -ForegroundColor White
    }
    
    Write-Host "-" * 60
}

# Check NAS path for current size
Write-Host ""
Write-Host "Checking NAS test data directory..." -ForegroundColor Yellow

$nasPath = "\\10.20.1.7\LRArchives\TestData"
$credentialTarget = "NAS_CREDS"

try {
    # Import credential module
    $scriptPath = "C:\LR\Scripts\LRArchiveRetention"
    $modulePath = Join-Path $scriptPath "modules\ShareCredentialHelper.psm1"
    Import-Module $modulePath -Force -ErrorAction SilentlyContinue
    
    # Try to connect with saved credentials
    $credential = Get-SavedCredential -Target $credentialTarget -ErrorAction SilentlyContinue
    if ($credential) {
        $null = New-PSDrive -Name "NASTEMP" -PSProvider FileSystem -Root $nasPath -Credential $credential -ErrorAction Stop
        
        # Get directory size
        $files = Get-ChildItem -Path "NASTEMP:\" -Recurse -File -ErrorAction SilentlyContinue
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $fileCount = $files.Count
        
        Write-Host "Current test data statistics:" -ForegroundColor Green
        Write-Host "  Path: $nasPath"
        Write-Host "  Files: $fileCount"
        Write-Host "  Size: $(Format-Size $totalSize)"
        Write-Host "  Target: 2 TB"
        Write-Host "  Progress: $([Math]::Round(($totalSize / 2TB) * 100, 2))%"
        
        Remove-PSDrive -Name "NASTEMP" -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "Could not access NAS path: $_" -ForegroundColor Red
}