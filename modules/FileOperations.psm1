# FileOperations.psm1
# Module for file discovery and deletion operations with parallel processing support

$script:ModuleVersion = '2.0.0'

# Import required .NET assemblies
Add-Type -AssemblyName System.Collections.Concurrent

function Get-FilesForRetention {
    <#
    .SYNOPSIS
        Gets files that are candidates for retention (deletion) based on age and filters
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [datetime]$CutoffDate,
        
        [hashtable]$FileTypeFilter,
        [int]$ParallelThreads = 4,
        [int]$BatchSize = 1000,
        [scriptblock]$ProgressCallback
    )
    
    Write-Verbose "Starting file enumeration for path: $Path"
    Write-Verbose "Cutoff date: $($CutoffDate.ToString('yyyy-MM-dd'))"
    Write-Verbose "Parallel threads: $ParallelThreads"
    
    # Use concurrent collection for thread-safe operations
    $fileCollection = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $errorCollection = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    
    # Get top-level directories for parallel processing
    try {
        $topDirs = @(Get-ChildItem -Path $Path -Directory -Force -ErrorAction Stop)
        $topDirs += [PSCustomObject]@{ FullName = $Path } # Include root for files in root
    }
    catch {
        Write-Error "Failed to enumerate directories in $Path : $_"
        return @()
    }
    
    # Create runspace pool for parallel processing
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ParallelThreads)
    $runspacePool.Open()
    
    # Script block for parallel execution
    $scriptBlock = {
        param($Directory, $CutoffDate, $FileTypeFilter, $FileCollection, $ErrorCollection)
        
        try {
            # Enumerate files in this directory recursively
            $files = Get-ChildItem -Path $Directory.FullName -File -Recurse -Force -ErrorAction Stop
            
            foreach ($file in $files) {
                try {
                    # Apply date filter
                    if ($file.LastWriteTime -ge $CutoffDate) {
                        continue
                    }
                    
                    # Apply file type filter if provided
                    if ($FileTypeFilter) {
                        $extension = [System.IO.Path]::GetExtension($file.Name).ToLower()
                        
                        if ($FileTypeFilter.Include.Count -gt 0) {
                            if ($FileTypeFilter.Include -notcontains $extension) {
                                continue
                            }
                        }
                        
                        if ($FileTypeFilter.Exclude.Count -gt 0) {
                            if ($FileTypeFilter.Exclude -contains $extension) {
                                continue
                            }
                        }
                    }
                    
                    # Add to collection
                    $fileInfo = [PSCustomObject]@{
                        FullName = $file.FullName
                        Name = $file.Name
                        Length = $file.Length
                        LastWriteTime = $file.LastWriteTime
                        Directory = $file.DirectoryName
                    }
                    $FileCollection.Add($fileInfo)
                }
                catch {
                    $ErrorCollection.Add([PSCustomObject]@{
                        File = $file.FullName
                        Error = $_.Exception.Message
                    })
                }
            }
        }
        catch {
            $ErrorCollection.Add([PSCustomObject]@{
                Directory = $Directory.FullName
                Error = $_.Exception.Message
            })
        }
    }
    
    # Start parallel jobs
    $jobs = @()
    foreach ($dir in $topDirs) {
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($dir).AddArgument($CutoffDate).AddArgument($FileTypeFilter).AddArgument($fileCollection).AddArgument($errorCollection)
        $powershell.RunspacePool = $runspacePool
        
        $jobs += [PSCustomObject]@{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            Directory = $dir.FullName
        }
    }
    
    # Wait for jobs and report progress
    $completed = 0
    while ($jobs | Where-Object { -not $_.Handle.IsCompleted }) {
        Start-Sleep -Milliseconds 500
        
        $newCompleted = ($jobs | Where-Object { $_.Handle.IsCompleted }).Count
        if ($newCompleted -gt $completed) {
            $completed = $newCompleted
            if ($ProgressCallback) {
                & $ProgressCallback @{
                    Activity = "Scanning directories"
                    PercentComplete = [int](($completed / $jobs.Count) * 100)
                    Status = "$completed of $($jobs.Count) directories scanned"
                    CurrentOperation = "Found $($fileCollection.Count) files so far"
                }
            }
        }
    }
    
    # Clean up jobs
    foreach ($job in $jobs) {
        try {
            $job.PowerShell.EndInvoke($job.Handle)
        }
        catch {
            Write-Warning "Error in parallel job for $($job.Directory): $_"
        }
        finally {
            $job.PowerShell.Dispose()
        }
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # Report errors if any
    $errors = $errorCollection.ToArray()
    if ($errors.Count -gt 0) {
        Write-Warning "Encountered $($errors.Count) errors during file enumeration"
        foreach ($error in $errors | Select-Object -First 10) {
            Write-Verbose "Error: $($error.Error) - Path: $($error.File ?? $error.Directory)"
        }
    }
    
    # Convert to array and return
    $files = $fileCollection.ToArray()
    Write-Verbose "File enumeration complete. Found $($files.Count) files for retention"
    
    return $files
}

function Remove-FilesWithRetry {
    <#
    .SYNOPSIS
        Removes files with retry logic and batch processing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Files,
        
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 1,
        [int]$BatchSize = 100,
        [scriptblock]$ProgressCallback,
        [scriptblock]$DeletionCallback
    )
    
    $totalFiles = $Files.Count
    $processedCount = 0
    $successCount = 0
    $failedCount = 0
    $errors = @()
    
    # Process files in batches
    for ($i = 0; $i -lt $totalFiles; $i += $BatchSize) {
        $batch = $Files[$i..[Math]::Min($i + $BatchSize - 1, $totalFiles - 1)]
        
        foreach ($file in $batch) {
            $success = $false
            $attempts = 0
            $lastError = $null
            
            while (-not $success -and $attempts -lt $MaxRetries) {
                $attempts++
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $success = $true
                    $successCount++
                    
                    # Call deletion callback if provided
                    if ($DeletionCallback) {
                        & $DeletionCallback $file
                    }
                }
                catch {
                    $lastError = $_
                    if ($attempts -lt $MaxRetries) {
                        Start-Sleep -Seconds ($RetryDelaySeconds * $attempts)
                    }
                }
            }
            
            if (-not $success) {
                $failedCount++
                $errors += [PSCustomObject]@{
                    File = $file.FullName
                    Error = $lastError.Exception.Message
                    Attempts = $attempts
                }
            }
            
            $processedCount++
            
            # Report progress
            if ($ProgressCallback -and ($processedCount % 100 -eq 0 -or $processedCount -eq $totalFiles)) {
                & $ProgressCallback @{
                    Activity = "Deleting files"
                    PercentComplete = [int](($processedCount / $totalFiles) * 100)
                    Status = "$processedCount of $totalFiles files processed"
                    CurrentOperation = "Success: $successCount, Failed: $failedCount"
                }
            }
        }
    }
    
    return [PSCustomObject]@{
        TotalFiles = $totalFiles
        ProcessedCount = $processedCount
        SuccessCount = $successCount
        FailedCount = $failedCount
        Errors = $errors
    }
}

function Remove-EmptyDirectories {
    <#
    .SYNOPSIS
        Removes empty directories recursively
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [switch]$WhatIf
    )
    
    Write-Verbose "Starting empty directory cleanup under: $Path"
    
    $removedCount = 0
    $errors = @()
    
    try {
        # Get all directories sorted by depth (deepest first)
        $directories = Get-ChildItem -Path $Path -Recurse -Directory -Force |
                      Sort-Object { $_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count } -Descending
        
        foreach ($dir in $directories) {
            # Skip the root path itself
            if ($dir.FullName -eq (Resolve-Path $Path).Path) {
                continue
            }
            
            try {
                $children = Get-ChildItem -Path $dir.FullName -Force
                if ($children.Count -eq 0) {
                    if ($WhatIf) {
                        Write-Verbose "Would remove empty directory: $($dir.FullName)"
                    }
                    else {
                        Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
                        Write-Verbose "Removed empty directory: $($dir.FullName)"
                    }
                    $removedCount++
                }
            }
            catch {
                $errors += [PSCustomObject]@{
                    Directory = $dir.FullName
                    Error = $_.Exception.Message
                }
            }
        }
    }
    catch {
        Write-Error "Error during empty directory enumeration: $_"
    }
    
    return [PSCustomObject]@{
        RemovedCount = $removedCount
        Errors = $errors
    }
}

function Get-DirectoryStatistics {
    <#
    .SYNOPSIS
        Gets statistics about a directory including file counts and sizes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [datetime]$CutoffDate,
        [hashtable]$FileTypeFilter
    )
    
    $stats = @{
        TotalFiles = 0
        TotalSize = 0
        OldFiles = 0
        OldFileSize = 0
        FilesByExtension = @{}
        OldestFile = $null
        NewestFile = $null
    }
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction Stop
        
        foreach ($file in $files) {
            $stats.TotalFiles++
            $stats.TotalSize += $file.Length
            
            # Track by extension
            $ext = [System.IO.Path]::GetExtension($file.Name).ToLower()
            if (-not $stats.FilesByExtension.ContainsKey($ext)) {
                $stats.FilesByExtension[$ext] = @{ Count = 0; Size = 0 }
            }
            $stats.FilesByExtension[$ext].Count++
            $stats.FilesByExtension[$ext].Size += $file.Length
            
            # Check if old
            if ($CutoffDate -and $file.LastWriteTime -lt $CutoffDate) {
                $stats.OldFiles++
                $stats.OldFileSize += $file.Length
            }
            
            # Track oldest/newest
            if (-not $stats.OldestFile -or $file.LastWriteTime -lt $stats.OldestFile.LastWriteTime) {
                $stats.OldestFile = $file
            }
            if (-not $stats.NewestFile -or $file.LastWriteTime -gt $stats.NewestFile.LastWriteTime) {
                $stats.NewestFile = $file
            }
        }
    }
    catch {
        Write-Warning "Error getting directory statistics: $_"
    }
    
    return $stats
}

# Export module members
Export-ModuleMember -Function @(
    'Get-FilesForRetention',
    'Remove-FilesWithRetry',
    'Remove-EmptyDirectories',
    'Get-DirectoryStatistics'
) 