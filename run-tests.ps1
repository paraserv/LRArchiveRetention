# run-tests.ps1
# Quick test runner for ArchiveRetention v2.0

#requires -Version 5.1

param(
    [switch]$ModulesOnly,
    [switch]$IntegrationOnly,
    [switch]$SkipFileOperations,
    [switch]$Verbose
)

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "   ArchiveRetention v2.0 Test Suite   " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

$testDir = Join-Path -Path $PSScriptRoot -ChildPath 'tests'

# Check if running on Windows for proper testing
if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
    Write-Warning "These tests are designed for Windows PowerShell."
    Write-Warning "Some tests may fail on non-Windows platforms."
    $response = Read-Host "Continue anyway? (Y/N)"
    if ($response -ne 'Y') {
        exit 0
    }
}

$results = @{}

# Run module tests
if (-not $IntegrationOnly) {
    Write-Host "`n🧪 Running Module Tests..." -ForegroundColor Yellow
    
    $moduleTestPath = Join-Path -Path $testDir -ChildPath 'test-v2-modules.ps1'
    
    if (Test-Path -Path $moduleTestPath) {
        try {
            $params = @{}
            if ($SkipFileOperations) { $params.SkipFileOperations = $true }
            if ($Verbose) { $params.Verbose = $true }
            
            & $moduleTestPath @params
            $results['Modules'] = $LASTEXITCODE -eq 0
        } catch {
            Write-Error "Module tests failed: $_"
            $results['Modules'] = $false
        }
    } else {
        Write-Warning "Module test script not found: $moduleTestPath"
        $results['Modules'] = $false
    }
}

# Run integration tests
if (-not $ModulesOnly) {
    Write-Host "`n🔧 Running Integration Tests..." -ForegroundColor Yellow
    
    $integrationTestPath = Join-Path -Path $testDir -ChildPath 'test-integration.ps1'
    
    if (Test-Path -Path $integrationTestPath) {
        try {
            $params = @{ UseDefaultTestPath = $true }
            if ($Verbose) { $params.Verbose = $true }
            
            & $integrationTestPath @params
            $results['Integration'] = $LASTEXITCODE -eq 0
        } catch {
            Write-Error "Integration tests failed: $_"
            $results['Integration'] = $false
        }
    } else {
        Write-Warning "Integration test script not found: $integrationTestPath"
        $results['Integration'] = $false
    }
}

# Final summary
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "         TEST SUITE SUMMARY           " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

foreach ($test in $results.GetEnumerator()) {
    $status = if ($test.Value) { "✓ PASSED" } else { "✗ FAILED" }
    $color = if ($test.Value) { "Green" } else { "Red" }
    Write-Host "$($test.Key) Tests: $status" -ForegroundColor $color
}

$allPassed = -not ($results.Values -contains $false)

if ($allPassed) {
    Write-Host "`n✅ All test suites passed!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Test on your Windows server: " -ForegroundColor White
    Write-Host "   scp -r * administrator@10.20.1.200:C:/LogRhythm/Scripts/ArchiveV2/" -ForegroundColor Gray
    Write-Host "2. Run tests on Windows server: " -ForegroundColor White
    Write-Host "   ssh administrator@10.20.1.200" -ForegroundColor Gray
    Write-Host "   cd C:/LogRhythm/Scripts/ArchiveV2" -ForegroundColor Gray
    Write-Host "   .\run-tests.ps1" -ForegroundColor Gray
    Write-Host "3. Test with real data (dry-run): " -ForegroundColor White
    Write-Host "   .\ArchiveRetention.ps1 -ArchivePath 'D:\LogRhythmArchives\Inactive' -RetentionDays 365 -Verbose" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "`n❌ Some test suites failed!" -ForegroundColor Red
    Write-Host "Please review the test output above for details." -ForegroundColor Yellow
    exit 1
} 