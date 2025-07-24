# Monitor NAS test data generation progress

$nasPath = "\\10.20.1.7\LRArchives\Inactive"

Write-Host "Monitoring test data generation..." -ForegroundColor Cyan
Write-Host "Target Path: $nasPath" -ForegroundColor Cyan
Write-Host ""

while ($true) {
    # Count folders created
    $folders = Get-ChildItem -Path $nasPath -Directory -Filter "*_1_1_1_*" -ErrorAction SilentlyContinue
    $folderCount = ($folders | Measure-Object).Count
    
    # Get total size
    $totalSize = 0
    $fileCount = 0
    
    if ($folderCount -gt 0) {
        # Sample a few folders to estimate progress
        $sampleFolders = $folders | Select-Object -First 5
        foreach ($folder in $sampleFolders) {
            $files = Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue
            $fileCount += ($files | Measure-Object).Count
            $totalSize += ($files | Measure-Object -Property Length -Sum).Sum
        }
        
        # Extrapolate based on sample
        if ($sampleFolders.Count -gt 0) {
            $avgFilesPerFolder = $fileCount / $sampleFolders.Count
            $avgSizePerFolder = $totalSize / $sampleFolders.Count
            $estimatedTotalFiles = [int]($avgFilesPerFolder * $folderCount)
            $estimatedTotalSize = $avgSizePerFolder * $folderCount / 1GB
        }
    }
    
    # Display progress
    Clear-Host
    Write-Host "=== NAS TEST DATA GENERATION PROGRESS ===" -ForegroundColor Green
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Folders Created: $folderCount" -ForegroundColor Yellow
    if ($folderCount -gt 0) {
        Write-Host "Estimated Files: $estimatedTotalFiles" -ForegroundColor Yellow
        Write-Host "Estimated Size: $([math]::Round($estimatedTotalSize, 2)) GB" -ForegroundColor Yellow
        
        # Show sample folder names to verify format
        Write-Host ""
        Write-Host "Sample folders (verifying format):" -ForegroundColor Cyan
        $folders | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Press Ctrl+C to stop monitoring..." -ForegroundColor DarkGray
    
    # Wait 30 seconds before next update
    Start-Sleep -Seconds 30
}