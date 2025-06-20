# LockManager.psm1
# Module for managing single-instance locks

$script:ModuleVersion = '2.0.0'

# Script-level variables
$script:LockInfo = @{
    FilePath = $null
    FileStream = $null
    IsLocked = $false
}

function New-ScriptLock {
    <#
    .SYNOPSIS
        Creates a single-instance lock for a script
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        
        [string]$LockDirectory = $env:TEMP
    )
    
    try {
        # Generate lock file path
        $lockFileName = "$ScriptName.lock"
        $script:LockInfo.FilePath = Join-Path -Path $LockDirectory -ChildPath $lockFileName
        
        # Try to create exclusive lock
        $script:LockInfo.FileStream = [System.IO.FileStream]::new(
            $script:LockInfo.FilePath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        
        # Write lock information
        $lockData = @{
            ProcessId = $PID
            ProcessName = (Get-Process -Id $PID).ProcessName
            MachineName = $env:COMPUTERNAME
            UserName = "$env:USERDOMAIN\$env:USERNAME"
            LockTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        } | ConvertTo-Json
        
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($lockData)
        $script:LockInfo.FileStream.SetLength(0)
        $script:LockInfo.FileStream.Write($bytes, 0, $bytes.Length)
        $script:LockInfo.FileStream.Flush()
        
        $script:LockInfo.IsLocked = $true
        
        return @{
            Success = $true
            LockFile = $script:LockInfo.FilePath
            Message = "Lock acquired successfully"
        }
    }
    catch [System.IO.IOException] {
        # Lock file is in use by another process
        $lockDetails = Get-LockDetails -LockFile $script:LockInfo.FilePath
        
        return @{
            Success = $false
            LockFile = $script:LockInfo.FilePath
            Message = "Another instance is already running"
            ExistingLock = $lockDetails
        }
    }
    catch {
        return @{
            Success = $false
            LockFile = $script:LockInfo.FilePath
            Message = "Failed to acquire lock: $($_.Exception.Message)"
            Error = $_
        }
    }
}

function Remove-ScriptLock {
    <#
    .SYNOPSIS
        Removes the single-instance lock
    #>
    [CmdletBinding()]
    param()
    
    if ($script:LockInfo.IsLocked -and $script:LockInfo.FileStream) {
        try {
            $script:LockInfo.FileStream.Close()
            $script:LockInfo.FileStream.Dispose()
            $script:LockInfo.FileStream = $null
            
            # Try to delete the lock file
            if (Test-Path -Path $script:LockInfo.FilePath) {
                Remove-Item -Path $script:LockInfo.FilePath -Force -ErrorAction SilentlyContinue
            }
            
            $script:LockInfo.IsLocked = $false
            
            Write-Verbose "Lock released successfully"
            return $true
        }
        catch {
            Write-Warning "Error releasing lock: $($_.Exception.Message)"
            return $false
        }
    }
    
    return $true
}

function Get-LockDetails {
    <#
    .SYNOPSIS
        Gets details about an existing lock file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LockFile
    )
    
    try {
        if (Test-Path -Path $LockFile) {
            # Try to read lock file content
            try {
                $content = Get-Content -Path $LockFile -Raw -ErrorAction Stop
                $lockData = $content | ConvertFrom-Json
                
                # Check if process is still running
                $process = Get-Process -Id $lockData.ProcessId -ErrorAction SilentlyContinue
                $lockData | Add-Member -NotePropertyName 'IsProcessRunning' -NotePropertyValue ($null -ne $process)
                
                return $lockData
            }
            catch {
                # Could not read lock file content
                return @{
                    Message = "Lock file exists but could not read details"
                    LockFile = $LockFile
                }
            }
        }
    }
    catch {
        Write-Warning "Error getting lock details: $($_.Exception.Message)"
    }
    
    return $null
}

function Test-ScriptLock {
    <#
    .SYNOPSIS
        Tests if a script lock exists
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        
        [string]$LockDirectory = $env:TEMP
    )
    
    $lockFileName = "$ScriptName.lock"
    $lockFilePath = Join-Path -Path $LockDirectory -ChildPath $lockFileName
    
    if (Test-Path -Path $lockFilePath) {
        $lockDetails = Get-LockDetails -LockFile $lockFilePath
        if ($lockDetails -and $lockDetails.IsProcessRunning) {
            return $true
        }
        else {
            # Lock file exists but process is not running - clean up
            try {
                Remove-Item -Path $lockFilePath -Force -ErrorAction Stop
                Write-Verbose "Cleaned up stale lock file: $lockFilePath"
            }
            catch {
                Write-Warning "Could not clean up stale lock file: $($_.Exception.Message)"
            }
        }
    }
    
    return $false
}

function Register-LockCleanup {
    <#
    .SYNOPSIS
        Registers cleanup handlers for lock removal
    #>
    [CmdletBinding()]
    param()
    
    # Register PowerShell exit event
    $null = Register-EngineEvent -SourceIdentifier 'PowerShell.Exiting' -Action {
        Remove-ScriptLock
    }
    
    # Set up trap for unexpected termination
    trap {
        Remove-ScriptLock
        throw $_
    }
}

# Export module members
Export-ModuleMember -Function @(
    'New-ScriptLock',
    'Remove-ScriptLock',
    'Get-LockDetails',
    'Test-ScriptLock',
    'Register-LockCleanup'
) 