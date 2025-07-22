# Changelog

All notable changes to the LogRhythm Archive Retention Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.5] - 2025-07-22

### Fixed
- **Finally block completion**: Fixed hardcoded zero values in finally block
  - Now uses actual execution values for files deleted, directories removed, and space freed
  - Script-level variables track progress throughout execution
  - Ensures accurate reporting even when script is interrupted
- **Enhanced Ctrl-C detection**: Improved termination detection
  - Added more exception types to trap handler
  - Added PowerShell.Exiting event handler
  - Script-level variables updated during streaming for accurate final counts

### Changed
- Added script-level tracking variables that persist across entire execution
- Finally block now uses actual values instead of hardcoded zeros
- Streaming mode updates global counters in real-time

## [2.3.4] - 2025-07-22

### Fixed
- **Parallel retention logging**: Fixed issue where retention logs were not written in parallel mode
  - Changed from concurrent file writes to collecting deleted files and writing from main thread
  - Prevents file access conflicts between StreamWriter and parallel threads
  - Ensures all deleted files are properly logged in retention action logs
- **Ctrl-C handling**: Script now properly detects and reports manual termination
  - Added trap handler for pipeline stopped exceptions
  - Shows "TERMINATED" status instead of "SUCCESS" when interrupted
  - Logs show clear indication of user interruption in both main and retention logs
  - Properly closes resources and saves progress before exiting

### Changed
- Improved status reporting to distinguish between SUCCESS, FAILED, and TERMINATED states
- Enhanced Complete-ScriptExecution to handle termination scenarios

## [2.3.3] - 2025-07-21

### Fixed
- **StreamWriter disposal**: Added proper closure after streaming mode completion
  - In streaming mode, the StreamWriter was kept open throughout the entire execution
  - Now closes StreamWriter after streaming deletion completes, before directory cleanup
  - Also closes StreamWriter before directory cleanup in non-streaming mode
  - This fully resolves the "file is being used by another process" error

## [2.3.2] - 2025-07-21

### Fixed
- **Critical fix**: Retention action log summary now properly written
  - StreamWriter was not being closed before Complete-ScriptExecution tried to append summary
  - Added explicit StreamWriter disposal before all Complete-ScriptExecution calls
  - Summary now includes completion time, file/directory counts, space freed, and status

## [2.3.1] - 2025-07-20

### Fixed
- **Retention Action Log**: Now properly writes completion summary with totals
- **Dry-run Mode**: Fixed hanging issue - now shows proper completion summary
- **Complete-ScriptExecution**: Fixed parameter handling to accept summary data

## [2.3.0] - 2025-07-20

### Added
- **Parallel Streaming Mode**: Revolutionary performance improvement for network operations
  - Combines streaming deletion with parallel processing for maximum throughput
  - Files are processed in batches as discovered, no pre-scan required
  - Automatic batch processing with configurable batch size (default: 500)
  - Expected performance: 120-160 files/sec on network shares with 8 threads
  - Enabled automatically when using `-Execute -ParallelProcessing`

### Changed
- Streaming mode now supports parallel processing for network share operations
- Progress reporting enhanced to show thread count in parallel streaming mode
- Batch processing logic unified between pre-scan and streaming modes

### Technical Details
- Uses same `Invoke-ParallelFileProcessing` function for consistency
- Maintains O(1) memory usage while maximizing deletion throughput
- Processes remaining batch after enumeration completes
- Fully backwards compatible - sequential streaming still available

## [2.2.6] - 2025-07-20

### Fixed
- **CRITICAL PERFORMANCE FIX**: Parallel processing now uses `[System.IO.File]::Delete()` instead of `Remove-Item`
  - Previous: Parallel mode was NOT faster than sequential due to using slow Remove-Item cmdlet
  - Now: Parallel mode should achieve 120-160 files/sec on network shares (4-8x improvement)
  - This completes the System.IO optimization for ALL code paths (streaming, sequential, and parallel)

## [2.2.5] - 2025-07-20

### Fixed
- **Critical bug fix**: Uninitialized `$processingStartTime` variable in streaming mode
  - In streaming mode, `$processingStartTime` was never initialized, causing null reference when calculating processing time
  - Now always initializes `$processingStartTime` before both streaming and batch processing modes
  - This was the root cause of "You cannot call a method on a null-valued expression" errors after streaming completion

## [2.2.4] - 2025-07-20

### Fixed
- **Critical bug fix**: Null reference error in streaming mode when calculating processing rates
  - In streaming mode, `$processedCount` was not properly tracked, causing null reference errors
  - Now uses `$successCount` for rate calculations in streaming mode
  - Fixed all occurrences where processed count is displayed or used in calculations
  - Affects lines 1792, 1800, 1812, and 1817 in the processing summary sections

## [2.2.3] - 2025-07-20

### Fixed
- **Critical bug fix**: Undefined variable $elapsedTimeStr causing null reference error
  - Error occurred in the processing summary section after streaming completion
  - Variable was being used but never defined in that scope
  - Now properly calculates and formats elapsed time before use

## [2.2.2] - 2025-07-20

### Fixed
- **Critical bug fix**: Null reference error after streaming mode completion
  - Script tried to process empty $allFiles array after streaming deletion
  - Now properly skips batch processing when streaming mode is used
  - Removes duplicate "Streaming deletion complete" log messages

## [2.2.1] - 2025-07-20

### Fixed
- **CRITICAL PERFORMANCE FIX**: Replaced PowerShell `Remove-Item` with `[System.IO.File]::Delete()` for file deletion
  - Previous: ~20 files/sec deletion rate
  - Expected: 100-500 files/sec deletion rate (5-25x improvement on local drives)
  - Network operations still limited by SMB latency (~15-20 files/sec single-threaded)
  - This fix implements the optimization specified in "Optimized Plan.md"
  - Affects both streaming mode and batch processing

### Added
- Performance tip when network path detected without parallel processing
- Recommendation to use `-ParallelProcessing -ThreadCount 8` for network shares
- Expected network performance: 120-160 files/sec with 8 threads

### Changed
- File deletion now uses direct .NET API for maximum performance
- Maintains same retry logic and error handling

## [2.2.0] - 2025-07-20

### Added
- **Streaming Deletion Mode**: Files are processed and deleted as discovered in EXECUTE mode
- **Zero Memory Growth**: Constant O(1) memory usage for any dataset size
- **Immediate Processing**: Deletions begin within seconds, no waiting for full scan

### Changed
- **Default Behavior**: EXECUTE mode now uses streaming deletion (no pre-scan)
- **Pre-scan Behavior**: Only performed in dry-run mode or when showing summaries
- **Progress Reporting**: Adapted for real-time streaming feedback
- **Memory Model**: Eliminated array building for execute operations

### Performance
- **Memory Usage**: From O(n) to O(1) - handles millions of files with minimal RAM
- **Start Time**: Deletions begin immediately vs waiting for full scan completion
- **Interruption Safe**: Progress is saved continuously, no lost work
- **Scalability**: No practical limit on number of files processed

### Technical Details
- Pre-scan still available for dry-run mode to show what would be deleted
- Batch processing logic preserved but bypassed in streaming mode
- Statistics (oldest/newest files) still tracked without array building

## [2.1.0] - 2025-07-20

### Added
- **System.IO Optimization**: Implemented `System.IO.Directory.EnumerateFiles` for 10-20x performance improvement
- **Enhanced Scan Performance**: Dramatically improved file enumeration speed for large datasets (50,000-200,000+ files)
- **Real-time Performance Metrics**: Display scan rate (files/second) during enumeration

### Changed
- **File Enumeration Method**: Replaced `Get-ChildItem` with streaming `System.IO` enumeration
- **Memory Usage**: Reduced from O(n) to O(1) memory complexity during file scanning
- **Scan Progress**: Enhanced progress reporting with performance metrics

### Performance
- **Expected Improvements**: 10-20x faster file enumeration on large datasets
- **Memory Efficiency**: Constant memory usage regardless of file count
- **Streaming Processing**: Files are processed as discovered, not loaded into memory

## [2.0.0] - 2025-07-19

### Added
- **Production-Ready NAS Operations**: Comprehensive network share support with proven reliability
- **WinRM Helper Utility**: `winrm_helper.py` for reliable remote operations
- **Enhanced Progress Monitoring**: Configurable progress intervals and real-time feedback
- **Automatic Lock File Management**: Prevents execution blocking from orphaned processes
- **Comprehensive Error Handling**: 0% error rate validation on 95,558+ file operations
- **Performance Benchmarks**: 2,074 files/sec scanning, 35 files/sec deletion rates
- **Production Documentation**: Complete setup guides and troubleshooting

### Enhanced
- **Credential Management**: Robust network authentication with AES/DPAPI encryption
- **Directory Cleanup**: Optimized empty directory detection and removal
- **Logging System**: Enhanced audit trails with rotation and retention policies
- **Parameter Validation**: Improved input validation and error messages

### Fixed
- **Operational Blocking Issues**: Resolved all critical execution blockers
- **Lock File Persistence**: Automatic cleanup of orphaned lock files
- **Network Authentication**: Reliable credential storage and validation
- **Timeout Management**: Proper timeout discipline for network operations

### Performance
- **Large-Scale Validation**: Successfully processed 4.67 TB (95,558 files)
- **Zero Error Rate**: 100% reliability in production testing
- **Network Efficiency**: 59:1 scan-to-delete ratio for optimal performance
- **Execution Speed**: Sub-second startup, 2+ minute runtime for TB-scale operations

### Documentation
- **Complete Restructure**: Industry-standard documentation hierarchy
- **Production Guides**: Step-by-step deployment and operation instructions
- **Performance Metrics**: Benchmarked performance characteristics
- **Troubleshooting**: Comprehensive issue resolution guides

### Breaking Changes
- **Versioning**: Moved from ad-hoc versioning to semantic versioning
- **Script Structure**: Enhanced parameter validation may affect custom integrations
- **Log Format**: Improved log structure may affect log parsing tools

### Migration Guide
For users upgrading from previous versions:
1. Review new parameter options (`-QuietMode`, `-ShowScanProgress`, etc.)
2. Update any log parsing tools for new log format
3. Verify credential storage using new validation tools
4. Test with `winrm_helper.py` for reliable operations

### Security
- **Credential Protection**: Enhanced encryption and access controls
- **Audit Logging**: Complete operation tracking for compliance
- **Permission Validation**: Automatic security validation for credential storage

## [1.2.0] - 2025-07-18 (Legacy)

### Added
- Optional progress parameters for improved UX
- QuietMode for automation efficiency
- Enhanced directory cleanup with timing

### Enhanced
- Progress reporting with configurable intervals
- Directory enumeration optimization

## [1.1.0] - 2025-07-17 (Legacy)

### Added
- Network credential support
- Scheduled task integration

### Enhanced
- Basic progress reporting
- Log rotation improvements

## [1.0.0] - Initial Release (Legacy)

### Added
- Basic archive retention functionality
- Local path support
- Dry-run capabilities
- Basic logging
