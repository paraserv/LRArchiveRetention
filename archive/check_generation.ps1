# Quick check of generation progress
$nasPath = "\\10.20.1.7\LRArchives\Inactive"

# Count folders
$folders = Get-ChildItem -Path $nasPath -Directory -Filter "*_1_1_1_*" -ErrorAction SilentlyContinue
$folderCount = ($folders | Measure-Object).Count

Write-Host "Current folder count: $folderCount" -ForegroundColor Green

if ($folderCount -gt 0) {
    Write-Host "`nSample folders (first 10):" -ForegroundColor Cyan
    $folders | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }
    
    # Check a sample folder for files
    $sampleFolder = $folders | Select-Object -First 1
    $files = Get-ChildItem -Path $sampleFolder.FullName -File -ErrorAction SilentlyContinue
    $fileCount = ($files | Measure-Object).Count
    
    Write-Host "`nSample folder contents ($($sampleFolder.Name)):" -ForegroundColor Cyan
    Write-Host "  File count: $fileCount" -ForegroundColor Yellow
    
    if ($fileCount -gt 0) {
        Write-Host "  Sample files:" -ForegroundColor Gray
        $files | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.Name) - $([math]::Round($_.Length/1MB, 2)) MB" -ForegroundColor Gray
        }
    }
}