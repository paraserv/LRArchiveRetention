# Parallel Streaming Mode Enhancement for ArchiveRetention.ps1 v2.3.0
# This shows the key changes needed to implement parallel deletion in streaming mode

# Key concept: Use a producer-consumer pattern with a thread-safe queue

# 1. Add at the beginning of streaming mode section (around line 1410):
if ($useStreamingMode -and $ParallelProcessing) {
    Write-Log "Using PARALLEL streaming deletion mode with $ThreadCount threads" -Level INFO
    Write-Log "This combines streaming efficiency with parallel network operations for maximum performance" -Level INFO
    
    # Create thread-safe collections for parallel streaming
    $fileQueue = [System.Collections.Concurrent.ConcurrentQueue[System.IO.FileInfo]]::new()
    $isEnumerationComplete = $false
    $parallelStats = @{
        Processed = 0
        Success = 0
        Errors = 0
        TotalSize = 0
    }
    
    # Create runspace pool for deletion workers
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.Open()
    
    # Define worker script block
    $workerScriptBlock = {
        param($Queue, $Stats, $IsComplete, $MaxRetries, $RetryDelaySeconds, $DeletionLogPath)
        
        $localSuccess = 0
        $localErrors = 0
        $localSize = 0
        
        while (-not $IsComplete.Value -or -not $Queue.IsEmpty) {
            $fileInfo = $null
            if ($Queue.TryDequeue([ref]$fileInfo)) {
                try {
                    # Retry logic for network operations
                    $attempt = 1
                    $success = $false
                    while (-not $success -and $attempt -le $MaxRetries) {
                        try {
                            [System.IO.File]::Delete($fileInfo.FullName)
                            $success = $true
                        } catch {
                            if ($attempt -eq $MaxRetries) { throw }
                            Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
                            $attempt++
                        }
                    }
                    
                    $localSuccess++
                    $localSize += $fileInfo.Length
                    
                    # Log to deletion log if provided
                    if ($DeletionLogPath) {
                        try {
                            [System.IO.File]::AppendAllText($DeletionLogPath, "$($fileInfo.FullName)`n")
                        } catch {}
                    }
                } catch {
                    $localErrors++
                }
                
                # Update shared stats periodically
                if (($localSuccess + $localErrors) % 10 -eq 0) {
                    [System.Threading.Interlocked]::Add([ref]$Stats.Success, $localSuccess) | Out-Null
                    [System.Threading.Interlocked]::Add([ref]$Stats.Errors, $localErrors) | Out-Null
                    [System.Threading.Interlocked]::Add([ref]$Stats.TotalSize, $localSize) | Out-Null
                    $localSuccess = 0
                    $localErrors = 0
                    $localSize = 0
                }
            } else {
                # Queue is empty, wait a bit
                Start-Sleep -Milliseconds 100
            }
        }
        
        # Final stats update
        [System.Threading.Interlocked]::Add([ref]$Stats.Success, $localSuccess) | Out-Null
        [System.Threading.Interlocked]::Add([ref]$Stats.Errors, $localErrors) | Out-Null
        [System.Threading.Interlocked]::Add([ref]$Stats.TotalSize, $localSize) | Out-Null
    }
    
    # Start worker threads
    $workers = @()
    $isCompleteRef = [ref]$isEnumerationComplete
    for ($i = 0; $i -lt $ThreadCount; $i++) {
        $powerShell = [powershell]::Create()
        $powerShell.RunspacePool = $runspacePool
        $powerShell.AddScript($workerScriptBlock).AddArgument($fileQueue).AddArgument($parallelStats).AddArgument($isCompleteRef).AddArgument($MaxRetries).AddArgument($RetryDelaySeconds).AddArgument($script:DeletionLogPath) | Out-Null
        
        $workers += @{
            PowerShell = $powerShell
            Result = $powerShell.BeginInvoke()
            Id = $i
        }
    }
    
    Write-Log "Started $ThreadCount parallel deletion workers" -Level INFO
}

# 2. Replace the synchronous deletion in streaming mode (around line 1469-1520) with:
if ($useStreamingMode) {
    if ($ParallelProcessing) {
        # PARALLEL STREAMING: Add to queue for workers
        $fileQueue.Enqueue($fileInfo)
        
        # Update counters for progress reporting
        $processedCount++
        $processedSize += $fileInfo.Length
        
        # Track parent directory
        $modifiedDirectories[$fileInfo.DirectoryName] = $true
        
        # Check queue size and throttle if needed
        while ($fileQueue.Count -gt 10000) {
            Start-Sleep -Milliseconds 100
            
            # Update stats from workers
            $successCount = $parallelStats.Success
            $errorCount = $parallelStats.Errors
        }
    } else {
        # SEQUENTIAL STREAMING: Original synchronous code
        try {
            Invoke-WithRetry -Operation {
                [System.IO.File]::Delete($fileInfo.FullName)
            } -Description "Delete file: $($fileInfo.FullName)" -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds
            # ... rest of original code ...
        }
    }
}

# 3. After enumeration completes (around line 1565), add cleanup for parallel mode:
if ($useStreamingMode -and $ParallelProcessing) {
    Write-Log "File enumeration complete. Waiting for parallel workers to finish processing queue..." -Level INFO
    $isEnumerationComplete = $true
    
    # Wait for queue to empty and workers to complete
    $waitStart = Get-Date
    while ($fileQueue.Count -gt 0 -or $workers.Where({-not $_.PowerShell.InvocationStateInfo.State.Equals('Completed')}).Count -gt 0) {
        $queueSize = $fileQueue.Count
        $activeWorkers = $workers.Where({$_.PowerShell.InvocationStateInfo.State -eq 'Running'}).Count
        
        if ((Get-Date) - $waitStart -gt [TimeSpan]::FromSeconds(5)) {
            Write-Log "Queue size: $queueSize, Active workers: $activeWorkers" -Level INFO
            $waitStart = Get-Date
        }
        
        Start-Sleep -Milliseconds 500
        
        # Update final stats
        $successCount = $parallelStats.Success
        $errorCount = $parallelStats.Errors
    }
    
    # Clean up workers
    foreach ($worker in $workers) {
        try {
            $worker.PowerShell.EndInvoke($worker.Result)
            $worker.PowerShell.Dispose()
        } catch {
            Write-Log "Error cleaning up worker $($worker.Id): $_" -Level WARNING
        }
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    Write-Log "Parallel streaming deletion complete: $successCount files deleted, $errorCount errors" -Level INFO
}

# 4. For progress reporting in parallel streaming mode, modify the periodic progress section:
if ($useStreamingMode -and $ParallelProcessing) {
    # Get current stats from workers
    $currentSuccess = $parallelStats.Success
    $currentErrors = $parallelStats.Errors
    $currentSize = $parallelStats.TotalSize
    
    $rate = if ($elapsedTotal.TotalSeconds -gt 0) { 
        [math]::Round($currentSuccess / $elapsedTotal.TotalSeconds, 1) 
    } else { 0 }
    
    Write-Log "Parallel streaming progress: Scanned $scannedCount files, deleted $currentSuccess files ($([math]::Round($currentSize / 1GB, 2)) GB freed)" -Level INFO
    Write-Log "  Deletion rate: $rate files/sec (using $ThreadCount threads), Queue size: $($fileQueue.Count)" -Level INFO
}

# Expected Performance Improvements:
# - Single-threaded network: 15-20 files/sec
# - 4 threads: 60-80 files/sec
# - 8 threads: 120-160 files/sec
# - 16 threads: 200-300 files/sec (may hit network/server limits)

# Note: Actual performance depends on:
# - Network latency (RTT to file server)
# - File server performance
# - SMB protocol version and settings
# - Network bandwidth (usually not the bottleneck for small files)