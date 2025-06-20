# LoggingModule.psm1
# Centralized logging module for ArchiveRetention

$script:ModuleVersion = '2.0.0'

# Script-level variables for log management
$script:LogStreams = @{}
$script:LogConfiguration = @{
    MaxLogSizeMB = 10
    MaxLogFiles = 10
    LogDirectory = $null
    DefaultLevel = 'INFO'
}

function Initialize-LoggingModule {
    <#
    .SYNOPSIS
        Initializes the logging module with configuration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogDirectory,
        
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 10,
        [string]$DefaultLevel = 'INFO'
    )
    
    $script:LogConfiguration.LogDirectory = $LogDirectory
    $script:LogConfiguration.MaxLogSizeMB = $MaxLogSizeMB
    $script:LogConfiguration.MaxLogFiles = $MaxLogFiles
    $script:LogConfiguration.DefaultLevel = $DefaultLevel
    
    # Ensure log directory exists
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
}

function New-LogStream {
    <#
    .SYNOPSIS
        Creates a new log stream for writing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        
        [switch]$Append,
        [string]$Header
    )
    
    try {
        $logPath = Join-Path -Path $script:LogConfiguration.LogDirectory -ChildPath $FileName
        
        # Rotate existing log if needed
        if ((Test-Path -Path $logPath) -and -not $Append) {
            Invoke-LogRotation -LogFile $logPath -MaxLogSizeMB $script:LogConfiguration.MaxLogSizeMB -MaxLogFiles $script:LogConfiguration.MaxLogFiles
        }
        
        # Create UTF-8 encoding without BOM
        $encoding = [System.Text.UTF8Encoding]::new($false)
        
        # Create the stream writer
        $writer = [System.IO.StreamWriter]::new($logPath, $Append, $encoding)
        
        # Write header if provided
        if ($Header) {
            $writer.WriteLine($Header)
            $writer.WriteLine("")
        }
        
        # Store the stream
        $script:LogStreams[$Name] = @{
            Writer = $writer
            Path = $logPath
            EntryCount = 0
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to create log stream '$Name': $_"
        return $false
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry to specified streams
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [AllowEmptyString()]
        [string]$Message = " ",
        
        [Parameter(Position=1)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL', 'VERBOSE')]
        [string]$Level = 'INFO',
        
        [string[]]$StreamNames = @('Main'),
        [switch]$NoConsoleOutput,
        [switch]$NoTimestamp
    )
    
    # Handle empty messages
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }
    
    # Filter DEBUG/VERBOSE unless -Verbose is set
    if (($Level -eq 'DEBUG' -or $Level -eq 'VERBOSE') -and $VerbosePreference -ne 'Continue') {
        return
    }
    
    # Build log entry
    $timestamp = if ($NoTimestamp) { "" } else { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') " }
    $logEntry = "$timestamp[$Level] - $Message"
    
    # Write to console if not suppressed
    if (-not $NoConsoleOutput) {
        switch ($Level) {
            'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
            'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
            'INFO'    { Write-Host $logEntry -ForegroundColor White }
            'DEBUG'   { Write-Debug $logEntry }
            'FATAL'   { Write-Host $logEntry -BackgroundColor Red -ForegroundColor White }
            'VERBOSE' { if ($VerbosePreference -eq 'Continue') { Write-Host $logEntry -ForegroundColor Gray } }
            default   { Write-Host $logEntry }
        }
    }
    
    # Write to log streams
    foreach ($streamName in $StreamNames) {
        if ($script:LogStreams.ContainsKey($streamName)) {
            $stream = $script:LogStreams[$streamName]
            try {
                $stream.Writer.WriteLine($logEntry)
                $stream.Writer.Flush()
                $stream.EntryCount++
                
                # Check if rotation is needed
                if ($stream.EntryCount -ge 1000) {
                    $stream.EntryCount = 0
                    if (Test-Path -Path $stream.Path) {
                        $fileInfo = Get-Item -Path $stream.Path
                        if (($fileInfo.Length / 1MB) -gt $script:LogConfiguration.MaxLogSizeMB) {
                            # Need to rotate
                            Close-LogStream -Name $streamName
                            New-LogStream -Name $streamName -FileName (Split-Path -Leaf $stream.Path) -Append
                        }
                    }
                }
            }
            catch {
                Write-Host "Failed to write to log stream '$streamName': $_" -ForegroundColor Red
            }
        }
    }
}

function Close-LogStream {
    <#
    .SYNOPSIS
        Closes a log stream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    if ($script:LogStreams.ContainsKey($Name)) {
        $stream = $script:LogStreams[$Name]
        try {
            if ($stream.Writer -and -not $stream.Writer.BaseStream.IsClosed) {
                $stream.Writer.Flush()
                $stream.Writer.Close()
                $stream.Writer.Dispose()
            }
        }
        catch {
            Write-Warning "Error closing log stream '$Name': $_"
        }
        finally {
            $script:LogStreams.Remove($Name)
        }
    }
}

function Close-AllLogStreams {
    <#
    .SYNOPSIS
        Closes all open log streams
    #>
    [CmdletBinding()]
    param()
    
    $streamNames = @($script:LogStreams.Keys)
    foreach ($name in $streamNames) {
        Close-LogStream -Name $name
    }
}

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Rotates log files based on size and count limits
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFile,
        
        [int]$MaxLogSizeMB = 10,
        [int]$MaxLogFiles = 10
    )
    
    try {
        if (-not (Test-Path -Path $LogFile)) {
            return
        }
        
        $logItem = Get-Item -Path $LogFile
        $logSize = $logItem.Length / 1MB
        
        if ($logSize -gt $MaxLogSizeMB) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $logDir = Split-Path -Path $LogFile -Parent
            $logName = [System.IO.Path]::GetFileNameWithoutExtension($LogFile)
            $logExt = [System.IO.Path]::GetExtension($LogFile)
            
            # Create rotated logs directory
            $rotatedDir = Join-Path -Path $logDir -ChildPath "rotated_logs"
            if (-not (Test-Path -Path $rotatedDir)) {
                New-Item -ItemType Directory -Path $rotatedDir -Force | Out-Null
            }
            
            # Generate unique rotated filename
            $rotatedPath = Join-Path -Path $rotatedDir -ChildPath "${logName}_${timestamp}${logExt}"
            $counter = 1
            while (Test-Path -Path $rotatedPath) {
                $rotatedPath = Join-Path -Path $rotatedDir -ChildPath "${logName}_${timestamp}_${counter}${logExt}"
                $counter++
            }
            
            # Move the file
            Move-Item -Path $LogFile -Destination $rotatedPath -Force
            
            # Clean up old files
            $oldFiles = Get-ChildItem -Path $rotatedDir -Filter "${logName}_*${logExt}" |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -Skip $MaxLogFiles
            
            foreach ($file in $oldFiles) {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Warning "Log rotation failed: $_"
    }
}

function Get-LogSummary {
    <#
    .SYNOPSIS
        Gets a summary of current logging state
    #>
    [CmdletBinding()]
    param()
    
    $summary = @{
        Configuration = $script:LogConfiguration
        Streams = @{}
    }
    
    foreach ($name in $script:LogStreams.Keys) {
        $stream = $script:LogStreams[$name]
        $fileInfo = if (Test-Path -Path $stream.Path) {
            Get-Item -Path $stream.Path
        } else { $null }
        
        $summary.Streams[$name] = @{
            Path = $stream.Path
            EntryCount = $stream.EntryCount
            SizeMB = if ($fileInfo) { [math]::Round($fileInfo.Length / 1MB, 2) } else { 0 }
            IsOpen = $stream.Writer -and -not $stream.Writer.BaseStream.IsClosed
        }
    }
    
    return $summary
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-LoggingModule',
    'New-LogStream',
    'Write-Log',
    'Close-LogStream',
    'Close-AllLogStreams',
    'Invoke-LogRotation',
    'Get-LogSummary'
) 