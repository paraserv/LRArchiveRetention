# Configuration.psm1
# Module for managing ArchiveRetention configuration and validation

$script:ModuleVersion = '2.0.0'

# Default configuration values
$script:DefaultConfig = @{
    MinimumRetentionDays = 90
    MaxLogSizeMB = 10
    MaxLogFiles = 10
    MaxRetries = 3
    RetryDelaySeconds = 1
    DefaultIncludeFileTypes = @('.lca')
    ProgressUpdateIntervalSeconds = 30
    ParallelThreads = 4
    BatchSize = 1000
}

function Get-DefaultConfiguration {
    <#
    .SYNOPSIS
        Returns the default configuration settings
    #>
    [CmdletBinding()]
    param()
    
    return $script:DefaultConfig.Clone()
}

function Test-Configuration {
    <#
    .SYNOPSIS
        Validates configuration parameters
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )
    
    $isValid = $true
    $errors = @()
    
    # Validate retention days
    if ($Config.RetentionDays -lt 1 -or $Config.RetentionDays -gt 3650) {
        $errors += "RetentionDays must be between 1 and 3650"
        $isValid = $false
    }
    
    # Validate minimum retention safety
    if ($Config.Execute -and $Config.RetentionDays -lt $Config.MinimumRetentionDays) {
        $Config.RetentionDays = $Config.MinimumRetentionDays
        Write-Warning "Retention period adjusted to minimum of $($Config.MinimumRetentionDays) days for safety"
    }
    
    # Validate paths
    if ($Config.ArchivePath) {
        if (-not (Test-Path -Path $Config.ArchivePath -PathType Container)) {
            $errors += "Archive path does not exist or is not accessible: $($Config.ArchivePath)"
            $isValid = $false
        }
    }
    
    # Validate parallel settings
    if ($Config.ParallelThreads -lt 1 -or $Config.ParallelThreads -gt 16) {
        $errors += "ParallelThreads must be between 1 and 16"
        $isValid = $false
    }
    
    if ($Config.BatchSize -lt 100 -or $Config.BatchSize -gt 10000) {
        $errors += "BatchSize must be between 100 and 10000"
        $isValid = $false
    }
    
    return @{
        IsValid = $isValid
        Errors = $errors
        Config = $Config
    }
}

function Get-NormalizedPath {
    <#
    .SYNOPSIS
        Normalizes and validates a file system path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    try {
        # Convert to .NET path format
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.TrimEnd('\', '/'))
        
        # Handle UNC paths specifically
        if ($normalizedPath -match '^\\\\\w+\\.*') {
            # Ensure UNC format is preserved
            if (-not $normalizedPath.StartsWith('\\')) {
                $normalizedPath = '\\' + $normalizedPath.TrimStart('\')
            }
        }
        
        return $normalizedPath
    }
    catch {
        Write-Warning "Error normalizing path: $Path - $($_.Exception.Message)"
        return $Path
    }
}

function New-RuntimeConfiguration {
    <#
    .SYNOPSIS
        Creates a runtime configuration object from parameters
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Parameters,
        [string]$ConfigFile
    )
    
    # Start with defaults
    $config = Get-DefaultConfiguration
    
    # Load from config file if provided
    if ($ConfigFile -and (Test-Path -Path $ConfigFile)) {
        try {
            $fileConfig = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json -AsHashtable
            foreach ($key in $fileConfig.Keys) {
                if ($config.ContainsKey($key)) {
                    $config[$key] = $fileConfig[$key]
                }
            }
        }
        catch {
            Write-Warning "Failed to load config file: $_"
        }
    }
    
    # Override with command-line parameters
    foreach ($key in $Parameters.Keys) {
        $config[$key] = $Parameters[$key]
    }
    
    # Add computed values
    $config['CutoffDate'] = (Get-Date).AddDays(-$config.RetentionDays)
    $config['StartTime'] = Get-Date
    
    return $config
}

function Get-FileTypeFilter {
    <#
    .SYNOPSIS
        Creates a file type filter for file enumeration
    #>
    [CmdletBinding()]
    param(
        [string[]]$IncludeTypes,
        [string[]]$ExcludeTypes
    )
    
    $filter = @{
        Include = @()
        Exclude = @()
    }
    
    # Normalize include types
    if ($IncludeTypes -and $IncludeTypes.Count -gt 0) {
        $filter.Include = $IncludeTypes | ForEach-Object {
            if ($_.StartsWith('.')) { $_ } else { ".$_" }
        }
    }
    
    # Normalize exclude types
    if ($ExcludeTypes -and $ExcludeTypes.Count -gt 0) {
        $filter.Exclude = $ExcludeTypes | ForEach-Object {
            if ($_.StartsWith('.')) { $_ } else { ".$_" }
        }
    }
    
    return $filter
}

function Test-FileTypeFilter {
    <#
    .SYNOPSIS
        Tests if a file matches the type filter criteria
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Filter
    )
    
    $extension = [System.IO.Path]::GetExtension($FileName).ToLower()
    
    # If include types specified, file must match one
    if ($Filter.Include.Count -gt 0) {
        return $Filter.Include -contains $extension
    }
    
    # If exclude types specified, file must not match any
    if ($Filter.Exclude.Count -gt 0) {
        return -not ($Filter.Exclude -contains $extension)
    }
    
    # If no filters specified, include all files
    return $true
}

# Export module members
Export-ModuleMember -Function @(
    'Get-DefaultConfiguration',
    'Test-Configuration',
    'Get-NormalizedPath',
    'New-RuntimeConfiguration',
    'Get-FileTypeFilter',
    'Test-FileTypeFilter'
) 