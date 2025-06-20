# ProgressTracking.psm1
# Module for progress tracking and reporting

$script:ModuleVersion = '2.0.0'

# Script-level variables
$script:ProgressState = @{
    StartTime = $null
    Activities = @{}
    UpdateInterval = [TimeSpan]::FromSeconds(1)
    LastUpdate = [DateTime]::MinValue
}

function Initialize-ProgressTracking {
    <#
    .SYNOPSIS
        Initializes the progress tracking system
    #>
    [CmdletBinding()]
    param(
        [TimeSpan]$UpdateInterval = [TimeSpan]::FromSeconds(1)
    )
    
    $script:ProgressState.StartTime = Get-Date
    $script:ProgressState.UpdateInterval = $UpdateInterval
    $script:ProgressState.Activities.Clear()
    $script:ProgressState.LastUpdate = [DateTime]::MinValue
}

function New-ProgressActivity {
    <#
    .SYNOPSIS
        Creates a new progress activity for tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$Activity,
        
        [int]$TotalItems = 0,
        [string]$Status = "Initializing..."
    )
    
    $script:ProgressState.Activities[$Name] = @{
        Activity = $Activity
        Status = $Status
        TotalItems = $TotalItems
        ProcessedItems = 0
        SuccessCount = 0
        ErrorCount = 0
        StartTime = Get-Date
        LastUpdate = Get-Date
        Metrics = @{}
    }
}

function Update-ProgressActivity {
    <#
    .SYNOPSIS
        Updates progress for a specific activity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [int]$ProcessedItems,
        [int]$SuccessCount,
        [int]$ErrorCount,
        [string]$Status,
        [string]$CurrentOperation,
        [hashtable]$Metrics,
        [switch]$Force
    )
    
    if (-not $script:ProgressState.Activities.ContainsKey($Name)) {
        Write-Warning "Progress activity '$Name' not found"
        return
    }
    
    $activity = $script:ProgressState.Activities[$Name]
    $now = Get-Date
    
    # Update counters if provided
    if ($PSBoundParameters.ContainsKey('ProcessedItems')) {
        $activity.ProcessedItems = $ProcessedItems
    }
    if ($PSBoundParameters.ContainsKey('SuccessCount')) {
        $activity.SuccessCount = $SuccessCount
    }
    if ($PSBoundParameters.ContainsKey('ErrorCount')) {
        $activity.ErrorCount = $ErrorCount
    }
    if ($PSBoundParameters.ContainsKey('Status')) {
        $activity.Status = $Status
    }
    if ($PSBoundParameters.ContainsKey('CurrentOperation')) {
        $activity.CurrentOperation = $CurrentOperation
    }
    if ($Metrics) {
        foreach ($key in $Metrics.Keys) {
            $activity.Metrics[$key] = $Metrics[$key]
        }
    }
    
    # Check if we should display progress
    $shouldDisplay = $Force -or (($now - $script:ProgressState.LastUpdate) -ge $script:ProgressState.UpdateInterval)
    
    if ($shouldDisplay) {
        $percentComplete = 0
        if ($activity.TotalItems -gt 0) {
            $percentComplete = [Math]::Min(100, [int](($activity.ProcessedItems / $activity.TotalItems) * 100))
        }
        
        # Calculate rate
        $elapsed = $now - $activity.StartTime
        $rate = if ($elapsed.TotalSeconds -gt 0 -and $activity.ProcessedItems -gt 0) {
            [Math]::Round($activity.ProcessedItems / $elapsed.TotalSeconds, 1)
        } else { 0 }
        
        # Build status text
        $statusText = $activity.Status
        if ($activity.TotalItems -gt 0) {
            $statusText = "$($activity.ProcessedItems) of $($activity.TotalItems) items"
        }
        
        # Build current operation text
        $operationText = $activity.CurrentOperation
        if (-not $operationText) {
            $operationText = "Rate: $rate items/sec"
            if ($activity.SuccessCount -gt 0 -or $activity.ErrorCount -gt 0) {
                $operationText += " | Success: $($activity.SuccessCount), Errors: $($activity.ErrorCount)"
            }
        }
        
        # Display progress
        Write-Progress -Activity $activity.Activity `
                      -Status $statusText `
                      -CurrentOperation $operationText `
                      -PercentComplete $percentComplete `
                      -Id $Name.GetHashCode()
        
        $activity.LastUpdate = $now
        $script:ProgressState.LastUpdate = $now
    }
}

function Complete-ProgressActivity {
    <#
    .SYNOPSIS
        Completes and removes a progress activity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [string]$FinalStatus = "Completed"
    )
    
    if ($script:ProgressState.Activities.ContainsKey($Name)) {
        $activity = $script:ProgressState.Activities[$Name]
        
        # Show final progress
        Write-Progress -Activity $activity.Activity `
                      -Status $FinalStatus `
                      -Completed `
                      -Id $Name.GetHashCode()
        
        # Remove from tracking
        $script:ProgressState.Activities.Remove($Name)
    }
}

function Get-ProgressSummary {
    <#
    .SYNOPSIS
        Gets a summary of all progress activities
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    
    if ($Name) {
        if ($script:ProgressState.Activities.ContainsKey($Name)) {
            return $script:ProgressState.Activities[$Name].Clone()
        }
        return $null
    }
    
    # Return all activities
    $summary = @{
        StartTime = $script:ProgressState.StartTime
        ElapsedTime = (Get-Date) - $script:ProgressState.StartTime
        Activities = @{}
    }
    
    foreach ($key in $script:ProgressState.Activities.Keys) {
        $summary.Activities[$key] = $script:ProgressState.Activities[$key].Clone()
    }
    
    return $summary
}

function Format-ByteSize {
    <#
    .SYNOPSIS
        Formats byte size to human readable format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [long]$Bytes
    )
    
    $sizes = 'B','KB','MB','GB','TB','PB'
    $index = 0
    $size = [double]$Bytes
    
    while ($size -ge 1024 -and $index -lt ($sizes.Count - 1)) {
        $size = $size / 1024
        $index++
    }
    
    return "{0:N2} {1}" -f $size, $sizes[$index]
}

function Format-TimeSpan {
    <#
    .SYNOPSIS
        Formats a timespan to human readable format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [TimeSpan]$TimeSpan
    )
    
    if ($TimeSpan.TotalDays -ge 1) {
        return "{0:N0}d {1:00}h {2:00}m" -f [Math]::Floor($TimeSpan.TotalDays), $TimeSpan.Hours, $TimeSpan.Minutes
    }
    elseif ($TimeSpan.TotalHours -ge 1) {
        return "{0:00}h {1:00}m {2:00}s" -f [Math]::Floor($TimeSpan.TotalHours), $TimeSpan.Minutes, $TimeSpan.Seconds
    }
    else {
        return "{0:00}m {1:00}s" -f [Math]::Floor($TimeSpan.TotalMinutes), $TimeSpan.Seconds
    }
}

function Get-EstimatedTimeRemaining {
    <#
    .SYNOPSIS
        Calculates estimated time remaining for an activity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ActivityName
    )
    
    if (-not $script:ProgressState.Activities.ContainsKey($ActivityName)) {
        return $null
    }
    
    $activity = $script:ProgressState.Activities[$ActivityName]
    
    if ($activity.ProcessedItems -eq 0 -or $activity.TotalItems -eq 0) {
        return $null
    }
    
    $elapsed = (Get-Date) - $activity.StartTime
    $itemsRemaining = $activity.TotalItems - $activity.ProcessedItems
    
    if ($itemsRemaining -le 0) {
        return [TimeSpan]::Zero
    }
    
    $secondsPerItem = $elapsed.TotalSeconds / $activity.ProcessedItems
    $secondsRemaining = $itemsRemaining * $secondsPerItem
    
    return [TimeSpan]::FromSeconds($secondsRemaining)
}

function Write-ProgressReport {
    <#
    .SYNOPSIS
        Writes a detailed progress report
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Progress Report",
        [switch]$IncludeMetrics
    )
    
    $summary = Get-ProgressSummary
    
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host ("=" * $Title.Length) -ForegroundColor Cyan
    Write-Host "Total Elapsed Time: $(Format-TimeSpan -TimeSpan $summary.ElapsedTime)" -ForegroundColor White
    
    foreach ($name in $summary.Activities.Keys) {
        $activity = $summary.Activities[$name]
        $elapsed = (Get-Date) - $activity.StartTime
        
        Write-Host "`n$($activity.Activity):" -ForegroundColor Yellow
        Write-Host "  Status: $($activity.Status)" -ForegroundColor White
        Write-Host "  Progress: $($activity.ProcessedItems) / $($activity.TotalItems) items" -ForegroundColor White
        Write-Host "  Success: $($activity.SuccessCount), Errors: $($activity.ErrorCount)" -ForegroundColor White
        Write-Host "  Elapsed: $(Format-TimeSpan -TimeSpan $elapsed)" -ForegroundColor White
        
        $eta = Get-EstimatedTimeRemaining -ActivityName $name
        if ($eta) {
            Write-Host "  ETA: $(Format-TimeSpan -TimeSpan $eta)" -ForegroundColor White
        }
        
        if ($IncludeMetrics -and $activity.Metrics.Count -gt 0) {
            Write-Host "  Metrics:" -ForegroundColor White
            foreach ($metric in $activity.Metrics.GetEnumerator()) {
                Write-Host "    $($metric.Key): $($metric.Value)" -ForegroundColor Gray
            }
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-ProgressTracking',
    'New-ProgressActivity',
    'Update-ProgressActivity',
    'Complete-ProgressActivity',
    'Get-ProgressSummary',
    'Format-ByteSize',
    'Format-TimeSpan',
    'Get-EstimatedTimeRemaining',
    'Write-ProgressReport'
) 