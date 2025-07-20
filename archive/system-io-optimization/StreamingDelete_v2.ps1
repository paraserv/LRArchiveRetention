#Requires -Version 5.1

<#
.SYNOPSIS
    Ultra-fast streaming file deletion using System.IO with credential support
    
.DESCRIPTION
    High-performance file deletion using System.IO.Directory.EnumerateFiles.
    Supports both local paths and network shares with saved credentials.
    
.PARAMETER Path
    Path to scan (local or UNC)
    
.PARAMETER CredentialTarget
    Name of saved credential for network share access
    
.PARAMETER RetentionDays
    Number of days to retain files (default: 365)
    
.PARAMETER FilePattern
    File pattern to match (default: "*.lca")
    
.PARAMETER Execute
    Actually delete files (default is dry-run)
    
.PARAMETER ShowProgress
    Show progress every N files (default: 1000, 0 = disable)
#>

[CmdletBinding(DefaultParameterSetName = 'DirectPath')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'DirectPath')]
    [string]$Path,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'SavedCredential')]
    [string]$CredentialTarget,
    
    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 365,
    
    [Parameter(Mandatory = $false)]
    [string]$FilePattern = "*.lca",
    
    [Parameter(Mandatory = $false)]
    [switch]$Execute,
    
    [Parameter(Mandatory = $false)]
    [int]$ShowProgress = 1000
)

$StartTime = Get-Date
$CutoffDate = (Get-Date).AddDays(-$RetentionDays)

Write-Host "StreamingDelete v2 - System.IO with Credential Support" -ForegroundColor Cyan
Write-Host "Retention: $RetentionDays days (cutoff: $($CutoffDate.ToString('yyyy-MM-dd')))"
Write-Host "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })" -ForegroundColor $(if ($Execute) { 'Yellow' } else { 'Green' })

# Handle credentials if specified
$mappedDrive = $null
if ($PSCmdlet.ParameterSetName -eq 'SavedCredential') {
    Write-Host "Loading saved credentials..." -ForegroundColor Gray
    
    try {
        # Load credential module
        $modulePath = Join-Path $PSScriptRoot "modules\ShareCredentialHelper.psm1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force
        } else {
            throw "Credential module not found at $modulePath"
        }
        
        # Get saved credentials
        $shareInfo = Get-SavedShareCredential -Target $CredentialTarget
        if (!$shareInfo) {
            throw "Failed to retrieve credentials for target: $CredentialTarget"
        }
        
        $Path = $shareInfo.SharePath
        Write-Host "Using share path: $Path"
        
        # Map network drive for better performance
        try {
            $driveLetter = 67..90 | ForEach-Object { [char]$_ } | Where-Object { 
                -not (Test-Path "$_`:") 
            } | Select-Object -First 1
            
            if ($driveLetter) {
                $mappedDrive = New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $Path -Credential $shareInfo.Credential -Scope Script
                $Path = "$driveLetter`:"
                Write-Host "Mapped drive $Path for better performance" -ForegroundColor Gray
            }
        } catch {
            Write-Host "Could not map drive, using UNC path directly" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Credential error: $_"
        exit 1
    }
}

Write-Host "Path: $Path"
Write-Host "Pattern: $FilePattern"
Write-Host ""

# Verify path exists
if (!(Test-Path $Path)) {
    Write-Error "Path does not exist or is not accessible: $Path"
    if ($mappedDrive) { Remove-PSDrive $mappedDrive -Force }
    exit 1
}

# Initialize counters
$scanned = 0
$deleted = 0
$deletedSize = 0
$errors = 0

# Start enumeration
$EnumStart = Get-Date
Write-Host "Starting file enumeration..." -ForegroundColor Gray

try {
    # Use streaming enumeration
    $files = [System.IO.Directory]::EnumerateFiles($Path, $FilePattern, [System.IO.SearchOption]::AllDirectories)
    
    foreach ($filePath in $files) {
        $scanned++
        
        # Show scan progress
        if ($ShowProgress -gt 0 -and ($scanned % $ShowProgress -eq 0)) {
            Write-Host "Scanned: $scanned files..." -NoNewline
            Write-Host "`r" -NoNewline
        }
        
        try {
            $fileInfo = [System.IO.FileInfo]::new($filePath)
            
            if ($fileInfo.LastWriteTime -lt $CutoffDate) {
                if ($Execute) {
                    # Direct deletion
                    [System.IO.File]::Delete($filePath)
                    $deleted++
                    $deletedSize += $fileInfo.Length
                }
                else {
                    # Dry run
                    $deleted++
                    $deletedSize += $fileInfo.Length
                }
                
                # Show delete progress
                if ($ShowProgress -gt 0 -and ($deleted % ($ShowProgress / 10) -eq 0)) {
                    $sizeGB = [Math]::Round($deletedSize / 1GB, 2)
                    Write-Host "$(if ($Execute) { 'Deleted' } else { 'Would delete' }): $deleted files ($sizeGB GB)..." -NoNewline
                    Write-Host "`r" -NoNewline
                }
            }
        }
        catch {
            $errors++
            if ($errors -le 10) {
                Write-Warning "Error processing $filePath`: $_"
            }
        }
    }
}
catch {
    Write-Error "Fatal enumeration error: $_"
}
finally {
    # Clean up mapped drive
    if ($mappedDrive) {
        Remove-PSDrive $mappedDrive -Force
        Write-Host "Unmapped temporary drive" -ForegroundColor Gray
    }
}

# Calculate timings
$EnumTime = (Get-Date) - $EnumStart
$TotalTime = (Get-Date) - $StartTime

# Clear progress line
Write-Host (" " * 80) -NoNewline
Write-Host "`r" -NoNewline

# Final summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Green
Write-Host "Files scanned: $scanned"
Write-Host "Files $(if ($Execute) { 'deleted' } else { 'to delete' }): $deleted"
Write-Host "Space $(if ($Execute) { 'freed' } else { 'to free' }): $('{0:N2}' -f ($deletedSize / 1GB)) GB"
Write-Host "Errors: $errors"
Write-Host ""
Write-Host "Performance:" -ForegroundColor Cyan
Write-Host "  Enumeration: $($EnumTime.TotalSeconds) seconds"
Write-Host "  Total time: $($TotalTime.TotalSeconds) seconds"

if ($scanned -gt 0) {
    $scanRate = [Math]::Round($scanned / $EnumTime.TotalSeconds, 0)
    Write-Host "  Scan rate: $scanRate files/sec"
}

if ($deleted -gt 0 -and $Execute) {
    $deleteRate = [Math]::Round($deleted / $TotalTime.TotalSeconds, 0)
    Write-Host "  Delete rate: $deleteRate files/sec"
}