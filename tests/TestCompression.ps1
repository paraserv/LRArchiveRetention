# Test script to verify log rotation and compression

# Create test directory
$testDir = "$PSScriptRoot\TestLogs"
if (-not (Test-Path -Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir | Out-Null
}

# Simple logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Write-Host "$timestamp [$Level] - $Message"
}

# Function to create a test log file
function New-TestLogFile {
    param(
        [string]$Path,
        [int]$SizeMB = 15
    )
    
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] This is a test log entry. " + 
            ("A" * 500) + ("B" * 500) + ("C" * 500) + "`n"
    $linesNeeded = [math]::Ceiling(($SizeMB * 1MB) / $line.Length)
    
    Write-Log "Creating test log file: $Path ($SizeMB MB, ~$linesNeeded lines)"
    
    1..$linesNeeded | ForEach-Object {
        Add-Content -Path $Path -Value $line -NoNewline
        if ($_ % 100 -eq 0) {
            $percentComplete = ($_ / $linesNeeded) * 100
            Write-Progress -Activity "Creating test log file" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
        }
    }
    
    Write-Progress -Activity "Creating test log file" -Completed
    $fileInfo = Get-Item -Path $Path
    Write-Log "Created test log file: $Path ($([math]::Round($fileInfo.Length/1MB, 2)) MB)"
}

# Include the compression function from the main script
function Compress-LogFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [switch]$DeleteOriginal = $false
    )
    
    try {
        Write-Log "Compressing file: $FilePath"
        
        if (-not (Test-Path -Path $FilePath)) {
            Write-Log "File not found: $FilePath" -Level WARNING
            return $false
        }
        
        $zipPath = "$FilePath.zip"
        
        # Skip if zip already exists and is newer than the source file
        if (Test-Path -Path $zipPath) {
            $zipFile = Get-Item -Path $zipPath
            $srcFile = Get-Item -Path $FilePath
            if ($zipFile.LastWriteTime -ge $srcFile.LastWriteTime) {
                Write-Log "Skipping compression - zip file is up to date: $zipPath"
                return $true
            }
        }
        
        # Load the compression assembly
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Create a temporary directory for the file to compress
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
        $tempFile = Join-Path -Path $tempDir -ChildPath (Split-Path -Leaf $FilePath)
        $tempZip = $null
        
        try {
            # Create temp directory and copy the file
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            Copy-Item -Path $FilePath -Destination $tempFile -Force
            
            # Create a temp zip file
            $tempZip = [System.IO.Path]::GetTempFileName() + '.zip'
            
            # Compress the file
            $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            [System.IO.Compression.ZipFile]::CreateFromDirectory(
                $tempDir,
                $tempZip,
                $compressionLevel,
                $false  # includeBaseDirectory
            )
            
            # Move the temp zip to the final location
            if (Test-Path -Path $zipPath) {
                Remove-Item -Path $zipPath -Force -ErrorAction Stop
            }
            Move-Item -Path $tempZip -Destination $zipPath -Force
            $tempZip = $null  # Clear so we don't try to delete it in the finally block
            
            # Set the last write time to match the original file
            (Get-Item $zipPath).LastWriteTime = (Get-Item $FilePath).LastWriteTime
            
            Write-Log "Successfully compressed file: $FilePath -> $zipPath"
            
            # Delete original if requested
            if ($DeleteOriginal) {
                Remove-Item -Path $FilePath -Force -ErrorAction Stop
                Write-Log "Removed original file: $FilePath"
            }
            
            return $true
        } finally {
            # Clean up temp files
            if (Test-Path -Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($tempZip -and (Test-Path -Path $tempZip)) {
                Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log "Failed to compress file: $FilePath - $($_.Exception.Message)" -Level ERROR
        Write-Log $_.ScriptStackTrace -Level DEBUG
        return $false
    }
}

# Clean up any existing test files from previous runs
Write-Log "Cleaning up any existing test files..."
Get-ChildItem -Path $testDir -Filter "test_*" | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

# Test log rotation and compression
$testLog = Join-Path -Path $testDir -ChildPath "test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create a test log file (15MB)
Write-Log "`nCreating a new test log file..."
New-TestLogFile -Path $testLog -SizeMB 15

# Test compression
Write-Log "`nTesting compression..."
$result = Compress-LogFile -FilePath $testLog -DeleteOriginal -Verbose

# Show results
Write-Log "`nTest results:"
Write-Log "------------"
Get-ChildItem -Path $testDir -File | 
    Select-Object Name, @{Name='SizeMB';Expression={[math]::Round($_.Length/1MB, 2)}}, LastWriteTime | 
    Format-Table -AutoSize

if ($result) {
    Write-Log "`n✅ Compression test completed successfully!" -Level SUCCESS
} else {
    Write-Log "`n❌ Compression test failed!" -Level ERROR
}
