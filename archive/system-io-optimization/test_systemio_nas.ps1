# Test System.IO performance on NAS with proper credentials
param(
    [string]$LogFile = "C:\temp\systemio_test.log"
)

# Initialize logging
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$timestamp - $Message"
}

Write-Log "Starting System.IO NAS performance test"
Write-Log "PID: $PID"

# Load credential module
try {
    Import-Module C:\LR\Scripts\LRArchiveRetention\modules\ShareCredentialHelper.psm1 -Force
    Write-Log "Credential module loaded"
    # Verify function exists
    if (Get-Command Get-SavedShareCredential -ErrorAction SilentlyContinue) {
        Write-Log "Get-SavedShareCredential function available"
    } else {
        Write-Log "ERROR: Get-SavedShareCredential function not found"
        exit 1
    }
} catch {
    Write-Log "ERROR: Failed to load credential module: $_"
    exit 1
}

# Get NAS credentials
try {
    $creds = Get-SavedShareCredential -Target NAS_CREDS
    $nasPath = $creds.SharePath
    Write-Log "Retrieved credentials for: $nasPath"
} catch {
    Write-Log "ERROR: Failed to get NAS credentials: $_"
    exit 1
}

# Map network drive for better access
try {
    Write-Log "Mapping network drive..."
    $drive = New-PSDrive -Name NASTEST -PSProvider FileSystem -Root $nasPath -Credential $creds.Credential -ErrorAction Stop
    $testPath = "NASTEST:"
    Write-Log "Drive mapped successfully to $testPath"
} catch {
    Write-Log "ERROR: Failed to map drive: $_"
    # Try direct path
    $testPath = $nasPath
    Write-Log "Using direct path: $testPath"
}

# Test parameters
$retentionDays = 365
$cutoff = (Get-Date).AddDays(-$retentionDays)
Write-Log "Retention: $retentionDays days (cutoff: $($cutoff.ToString('yyyy-MM-dd')))"
Write-Log ""

# Test 1: Get-ChildItem baseline
Write-Log "=== TEST 1: Get-ChildItem Baseline ==="
$timer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $gcFiles = @(Get-ChildItem -Path $testPath -Filter *.lca -File -Recurse)
    $gcCount = $gcFiles.Count
    $gcOldFiles = @($gcFiles | Where-Object { $_.LastWriteTime -lt $cutoff })
    $gcOldCount = $gcOldFiles.Count
    $gcSize = ($gcOldFiles | Measure-Object -Property Length -Sum).Sum / 1GB
    $timer.Stop()
    
    Write-Log "Get-ChildItem Results:"
    Write-Log "  Total files: $gcCount"
    Write-Log "  Files to delete: $gcOldCount"
    Write-Log "  Size to delete: $([Math]::Round($gcSize, 2)) GB"
    Write-Log "  Time: $($timer.Elapsed.TotalSeconds) seconds"
    Write-Log "  Performance: $([Math]::Round($gcCount / $timer.Elapsed.TotalSeconds, 0)) files/sec"
} catch {
    Write-Log "ERROR in Get-ChildItem: $_"
}
Write-Log ""

# Test 2: System.IO.Directory.EnumerateFiles
Write-Log "=== TEST 2: System.IO.Directory.EnumerateFiles ==="
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$enumCount = 0
$enumOldCount = 0
$enumSize = 0

try {
    # Use the UNC path directly for System.IO
    $enumPath = if ($testPath -eq "NASTEST:") { $nasPath } else { $testPath }
    Write-Log "Enumerating files from: $enumPath"
    
    $files = [System.IO.Directory]::EnumerateFiles($enumPath, "*.lca", [System.IO.SearchOption]::AllDirectories)
    
    foreach ($filePath in $files) {
        $enumCount++
        
        # Show progress every 1000 files
        if ($enumCount % 1000 -eq 0) {
            Write-Log "  Progress: $enumCount files scanned..."
        }
        
        $fileInfo = [System.IO.FileInfo]::new($filePath)
        if ($fileInfo.LastWriteTime -lt $cutoff) {
            $enumOldCount++
            $enumSize += $fileInfo.Length
        }
    }
    $timer.Stop()
    
    Write-Log "System.IO Results:"
    Write-Log "  Total files: $enumCount"
    Write-Log "  Files to delete: $enumOldCount"
    Write-Log "  Size to delete: $([Math]::Round($enumSize / 1GB, 2)) GB"
    Write-Log "  Time: $($timer.Elapsed.TotalSeconds) seconds"
    Write-Log "  Performance: $([Math]::Round($enumCount / $timer.Elapsed.TotalSeconds, 0)) files/sec"
} catch {
    Write-Log "ERROR in System.IO: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"
}
Write-Log ""

# Test 3: System.IO with minimal processing (pure enumeration speed)
Write-Log "=== TEST 3: System.IO Pure Enumeration Speed ==="
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$pureCount = 0

try {
    $enumPath = if ($testPath -eq "NASTEST:") { $nasPath } else { $testPath }
    $files = [System.IO.Directory]::EnumerateFiles($enumPath, "*.lca", [System.IO.SearchOption]::AllDirectories)
    
    foreach ($file in $files) {
        $pureCount++
    }
    $timer.Stop()
    
    Write-Log "Pure enumeration results:"
    Write-Log "  Files counted: $pureCount"
    Write-Log "  Time: $($timer.Elapsed.TotalSeconds) seconds"
    Write-Log "  Performance: $([Math]::Round($pureCount / $timer.Elapsed.TotalSeconds, 0)) files/sec"
} catch {
    Write-Log "ERROR in pure enumeration: $_"
}

# Cleanup
try {
    if (Get-PSDrive -Name NASTEST -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name NASTEST -Force
        Write-Log "Drive unmapped"
    }
} catch {
    Write-Log "Warning: Could not unmap drive: $_"
}

Write-Log ""
Write-Log "=== PERFORMANCE COMPARISON ==="
if ($gcCount -gt 0 -and $enumCount -gt 0) {
    $speedup = [Math]::Round($gcFiles.Count / $timer.Elapsed.TotalSeconds / ($enumCount / $timer.Elapsed.TotalSeconds), 1)
    Write-Log "System.IO vs Get-ChildItem speedup: ${speedup}x"
}
Write-Log "Test completed"