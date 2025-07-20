# Fast File Enumeration Functions for Network Shares
# Uses .NET methods for significantly faster performance

function Get-FilesUsingDotNet {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string[]]$IncludeExtensions = @('.lca'),
        
        [datetime]$OlderThan,
        
        [switch]$ShowProgress
    )
    
    $fileList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalSize = 0
    $scannedCount = 0
    $matchedCount = 0
    $startTime = Get-Date
    $lastProgressTime = $startTime
    
    # Convert extensions to lowercase for comparison
    $extensions = $IncludeExtensions | ForEach-Object { $_.ToLower() }
    
    try {
        # Use EnumerateFiles for streaming enumeration
        $enumerationOptions = [System.IO.EnumerationOptions]::new()
        $enumerationOptions.RecurseSubdirectories = $true
        $enumerationOptions.IgnoreInaccessible = $true
        $enumerationOptions.AttributesToSkip = [System.IO.FileAttributes]::Device
        
        # Get all files using .NET (much faster than Get-ChildItem)
        foreach ($filePath in [System.IO.Directory]::EnumerateFiles($Path, "*", $enumerationOptions)) {
            $scannedCount++
            
            # Show progress every 1000 files or every 5 seconds
            if ($ShowProgress -and ($scannedCount % 1000 -eq 0 -or ((Get-Date) - $lastProgressTime).TotalSeconds -ge 5)) {
                $rate = [math]::Round($scannedCount / ((Get-Date) - $startTime).TotalSeconds, 0)
                Write-Host "`r  Scanning: $scannedCount files found ($rate files/sec) - Matched: $matchedCount" -NoNewline -ForegroundColor Cyan
                $lastProgressTime = Get-Date
            }
            
            try {
                # Get file info
                $fileInfo = [System.IO.FileInfo]::new($filePath)
                
                # Check extension
                if ($extensions -notcontains $fileInfo.Extension.ToLower()) {
                    continue
                }
                
                # Check age
                if ($fileInfo.LastWriteTime -ge $OlderThan) {
                    continue
                }
                
                # Add to results
                $matchedCount++
                $totalSize += $fileInfo.Length
                
                $fileList.Add([PSCustomObject]@{
                    FullName = $fileInfo.FullName
                    Name = $fileInfo.Name
                    DirectoryName = $fileInfo.DirectoryName
                    Length = $fileInfo.Length
                    LastWriteTime = $fileInfo.LastWriteTime
                })
                
            } catch {
                # Skip files we can't access
                continue
            }
        }
        
        if ($ShowProgress) {
            Write-Host "`r  Scan complete: $scannedCount files scanned, $matchedCount matched" -ForegroundColor Green
            Write-Host ""
        }
        
    } catch {
        Write-Warning "Error during enumeration: $_"
    }
    
    return @{
        Files = $fileList
        TotalSize = $totalSize
        ScannedCount = $scannedCount
        MatchedCount = $matchedCount
        Duration = (Get-Date) - $startTime
    }
}

function Get-FilesUsingQueue {
    <#
    .SYNOPSIS
    Alternative method using Queue-based traversal for even better performance on some systems
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string[]]$IncludeExtensions = @('.lca'),
        
        [datetime]$OlderThan,
        
        [switch]$ShowProgress
    )
    
    $fileList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
    $totalSize = 0
    $scannedCount = 0
    $matchedCount = 0
    $startTime = Get-Date
    $lastProgressTime = $startTime
    
    # Convert extensions to lowercase
    $extensions = $IncludeExtensions | ForEach-Object { $_.ToLower() }
    
    # Start with root directory
    $queue.Enqueue([System.IO.DirectoryInfo]::new($Path))
    
    while ($queue.Count -gt 0) {
        $currentDir = $queue.Dequeue()
        
        try {
            # Enumerate subdirectories
            foreach ($subDir in $currentDir.EnumerateDirectories()) {
                $queue.Enqueue($subDir)
            }
            
            # Enumerate files
            foreach ($file in $currentDir.EnumerateFiles()) {
                $scannedCount++
                
                # Show progress
                if ($ShowProgress -and ($scannedCount % 1000 -eq 0 -or ((Get-Date) - $lastProgressTime).TotalSeconds -ge 5)) {
                    $rate = [math]::Round($scannedCount / ((Get-Date) - $startTime).TotalSeconds, 0)
                    Write-Host "`r  Scanning: $scannedCount files found ($rate files/sec) - Matched: $matchedCount" -NoNewline -ForegroundColor Cyan
                    $lastProgressTime = Get-Date
                }
                
                # Check extension
                if ($extensions -notcontains $file.Extension.ToLower()) {
                    continue
                }
                
                # Check age
                if ($file.LastWriteTime -ge $OlderThan) {
                    continue
                }
                
                # Add to results
                $matchedCount++
                $totalSize += $file.Length
                
                $fileList.Add([PSCustomObject]@{
                    FullName = $file.FullName
                    Name = $file.Name
                    DirectoryName = $file.DirectoryName
                    Length = $file.Length
                    LastWriteTime = $file.LastWriteTime
                })
            }
        } catch {
            # Skip directories we can't access
            continue
        }
    }
    
    if ($ShowProgress) {
        Write-Host "`r  Scan complete: $scannedCount files scanned, $matchedCount matched" -ForegroundColor Green
        Write-Host ""
    }
    
    return @{
        Files = $fileList
        TotalSize = $totalSize
        ScannedCount = $scannedCount
        MatchedCount = $matchedCount
        Duration = (Get-Date) - $startTime
    }
}

function Remove-FilesParallel {
    <#
    .SYNOPSIS
    Removes files in parallel using ForEach-Object -Parallel (PowerShell 7+)
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Files,
        
        [int]$ThrottleLimit = 8,
        
        [switch]$WhatIf,
        
        [string]$LogPath
    )
    
    $results = $Files | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $file = $_
        $result = @{
            Path = $file.FullName
            Success = $false
            Error = $null
            Size = $file.Length
        }
        
        try {
            if (-not $using:WhatIf) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                
                # Log to file if specified
                if ($using:LogPath) {
                    Add-Content -Path $using:LogPath -Value "DELETED: $($file.FullName)" -ErrorAction SilentlyContinue
                }
            }
            
            $result.Success = $true
        } catch {
            $result.Error = $_.Exception.Message
        }
        
        return $result
    }
    
    return $results
}

# Example usage function
function Start-FastArchiveRetention {
    param(
        [string]$Path = "\\10.20.1.7\LRArchives",
        [int]$RetentionDays = 365,
        [switch]$Execute,
        [int]$ThreadCount = 8
    )
    
    Write-Host "=== Fast Archive Retention Scanner ===" -ForegroundColor Cyan
    Write-Host "Path: $Path"
    Write-Host "Retention: $RetentionDays days"
    Write-Host "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })"
    Write-Host ""
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    Write-Host "Scanning for files older than: $($cutoffDate.ToString('yyyy-MM-dd'))"
    Write-Host ""
    
    # Use fast .NET enumeration
    $scanResult = Get-FilesUsingDotNet -Path $Path -OlderThan $cutoffDate -ShowProgress
    
    Write-Host ""
    Write-Host "Scan Results:" -ForegroundColor Yellow
    Write-Host "  Total files scanned: $($scanResult.ScannedCount)"
    Write-Host "  Files to process: $($scanResult.MatchedCount)"
    Write-Host "  Total size: $([math]::Round($scanResult.TotalSize / 1GB, 2)) GB"
    Write-Host "  Scan duration: $([math]::Round($scanResult.Duration.TotalSeconds, 1)) seconds"
    Write-Host "  Scan rate: $([math]::Round($scanResult.ScannedCount / $scanResult.Duration.TotalSeconds, 0)) files/sec"
    
    if ($Execute -and $scanResult.Files.Count -gt 0) {
        Write-Host ""
        Write-Host "Starting parallel deletion with $ThreadCount threads..." -ForegroundColor Yellow
        
        $deleteStart = Get-Date
        $results = Remove-FilesParallel -Files $scanResult.Files -ThrottleLimit $ThreadCount -WhatIf:$(-not $Execute)
        $deleteEnd = Get-Date
        
        $successCount = ($results | Where-Object { $_.Success }).Count
        $errorCount = ($results | Where-Object { -not $_.Success }).Count
        
        Write-Host ""
        Write-Host "Deletion Results:" -ForegroundColor Green
        Write-Host "  Successful: $successCount"
        Write-Host "  Errors: $errorCount"
        Write-Host "  Duration: $([math]::Round(($deleteEnd - $deleteStart).TotalSeconds, 1)) seconds"
        Write-Host "  Rate: $([math]::Round($successCount / ($deleteEnd - $deleteStart).TotalSeconds, 0)) files/sec"
    }
}

# Test the performance difference
function Test-EnumerationPerformance {
    param(
        [string]$Path = "\\10.20.1.7\LRArchives"
    )
    
    Write-Host "=== Enumeration Performance Test ===" -ForegroundColor Cyan
    Write-Host "Path: $Path"
    Write-Host ""
    
    # Test 1: Traditional Get-ChildItem
    Write-Host "Method 1: Get-ChildItem -Recurse" -ForegroundColor Yellow
    $start = Get-Date
    try {
        $files1 = @(Get-ChildItem -Path $Path -Recurse -File -Filter "*.lca" -ErrorAction Stop | Select-Object -First 10000)
        $duration1 = (Get-Date) - $start
        Write-Host "  Found $($files1.Count) files in $([math]::Round($duration1.TotalSeconds, 1)) seconds"
        Write-Host "  Rate: $([math]::Round($files1.Count / $duration1.TotalSeconds, 0)) files/sec"
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # Test 2: .NET Directory.EnumerateFiles
    Write-Host "Method 2: System.IO.Directory.EnumerateFiles" -ForegroundColor Yellow
    $start = Get-Date
    try {
        $count = 0
        $enumerator = [System.IO.Directory]::EnumerateFiles($Path, "*.lca", [System.IO.SearchOption]::AllDirectories).GetEnumerator()
        while ($enumerator.MoveNext() -and $count -lt 10000) {
            $count++
        }
        $duration2 = (Get-Date) - $start
        Write-Host "  Found $count files in $([math]::Round($duration2.TotalSeconds, 1)) seconds"
        Write-Host "  Rate: $([math]::Round($count / $duration2.TotalSeconds, 0)) files/sec"
        
        if ($duration1.TotalSeconds -gt 0 -and $duration2.TotalSeconds -gt 0) {
            $improvement = [math]::Round($duration1.TotalSeconds / $duration2.TotalSeconds, 1)
            Write-Host "  Speed improvement: ${improvement}x faster" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
}

# Export functions
Export-ModuleMember -Function Get-FilesUsingDotNet, Get-FilesUsingQueue, Remove-FilesParallel, Start-FastArchiveRetention, Test-EnumerationPerformance