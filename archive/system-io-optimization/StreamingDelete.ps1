#Requires -Version 5.1

<#
.SYNOPSIS
    Ultra-fast streaming file deletion using System.IO with minimal overhead
    
.DESCRIPTION
    Streamlined version focusing purely on performance for large-scale deletions.
    Uses System.IO.Directory.EnumerateFiles with streaming processing.
    
.PARAMETER Path
    Path to scan (local or UNC)
    
.PARAMETER RetentionDays
    Number of days to retain files (default: 365)
    
.PARAMETER FilePattern
    File pattern to match (default: "*.lca")
    
.PARAMETER Execute
    Actually delete files (default is dry-run)
    
.PARAMETER ShowProgress
    Show progress every N files (default: 1000, 0 = disable)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    
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

Write-Host "StreamingDelete - Ultra-fast file deletion" -ForegroundColor Cyan
Write-Host "Path: $Path"
Write-Host "Pattern: $FilePattern"
Write-Host "Retention: $RetentionDays days (cutoff: $($CutoffDate.ToString('yyyy-MM-dd')))"
Write-Host "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })" -ForegroundColor $(if ($Execute) { 'Yellow' } else { 'Green' })
Write-Host ""

# Verify path exists
if (!(Test-Path $Path)) {
    Write-Error "Path does not exist: $Path"
    exit 1
}

# Ensure UNC paths are properly formatted
if ($Path -match '^\\\\') {
    Write-Host "Detected UNC path" -ForegroundColor Gray
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
    # Use streaming enumeration - this is the key to performance
    $files = [System.IO.Directory]::EnumerateFiles($Path, $FilePattern, [System.IO.SearchOption]::AllDirectories)
    
    foreach ($filePath in $files) {
        $scanned++
        
        # Show scan progress
        if ($ShowProgress -gt 0 -and ($scanned % $ShowProgress -eq 0)) {
            Write-Host "Scanned: $scanned files..." -NoNewline
            Write-Host "`r" -NoNewline
        }
        
        try {
            # Get file info without creating FileInfo object for every file
            $fileInfo = [System.IO.FileInfo]::new($filePath)
            
            if ($fileInfo.LastWriteTime -lt $CutoffDate) {
                if ($Execute) {
                    # Direct deletion - fastest method
                    [System.IO.File]::Delete($filePath)
                    $deleted++
                    $deletedSize += $fileInfo.Length
                }
                else {
                    # Dry run - just count
                    $deleted++
                    $deletedSize += $fileInfo.Length
                }
                
                # Show delete progress
                if ($ShowProgress -gt 0 -and ($deleted % ($ShowProgress / 10) -eq 0)) {
                    $sizeGB = [Math]::Round($deletedSize / 1GB, 2)
                    Write-Host "Deleted: $deleted files ($sizeGB GB)..." -NoNewline
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