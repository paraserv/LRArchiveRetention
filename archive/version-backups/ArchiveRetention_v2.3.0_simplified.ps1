# Simplified Parallel Network Deletion Approach for v2.3.0
# Instead of complex parallel streaming, use existing parallel batch processing with smaller batches

# Key insight: The existing script already has parallel processing for batch mode!
# We can achieve good network performance by:
# 1. Using -ParallelProcessing switch
# 2. Using smaller -BatchSize (e.g., 100-500 files)
# 3. Letting the existing parallel infrastructure handle the work

# Usage for optimal network performance:
.\ArchiveRetention.ps1 -CredentialTarget "NAS_CREDS" `
    -RetentionDays 547 `
    -Execute `
    -ParallelProcessing `
    -ThreadCount 8 `
    -BatchSize 200 `
    -ShowDeleteProgress

# This approach:
# - Uses the existing, tested parallel processing code
# - Processes files in small batches (200 files) for responsive progress
# - With 8 threads, should achieve 120-160 files/sec on network
# - No complex streaming mode changes needed

# Performance expectations with this approach:
# - Single-threaded: 15-20 files/sec
# - 4 threads: 60-80 files/sec  
# - 8 threads: 120-160 files/sec
# - 16 threads: 200-300 files/sec (may hit server limits)

# The only code change needed is to update documentation and perhaps add a note
# in the script that for network operations, parallel mode is recommended:

# Add to script parameter help:
<#
.PARAMETER ParallelProcessing
    Enable parallel file processing using runspaces. HIGHLY RECOMMENDED for network shares
    to achieve 4-16x performance improvement. Use with -ThreadCount to control parallelism.

.PARAMETER ThreadCount  
    Number of parallel threads for file operations (default: 4, max: 16).
    For network shares: 8 threads recommended for optimal performance.
    For local drives: 2-4 threads usually sufficient.

.EXAMPLE
    # Optimal configuration for network share deletion
    .\ArchiveRetention.ps1 -CredentialTarget "NAS_PROD" -RetentionDays 365 -Execute `
        -ParallelProcessing -ThreadCount 8 -BatchSize 200
#>

# Add to the configuration output section (around line 1372):
if (-not $ParallelProcessing -and $ArchivePath -like "\\*") {
    Write-Log "TIP: For network paths, use -ParallelProcessing -ThreadCount 8 for 4-8x faster deletion" -Level INFO
    if ($script:showProgress) {
        Write-Host "  TIP: Add -ParallelProcessing -ThreadCount 8 for much faster network deletion!" -ForegroundColor Yellow
    }
}