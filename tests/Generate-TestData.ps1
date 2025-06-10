# tests/Generate-TestData.ps1
<#+
.SYNOPSIS
    Generate test directories and files for ArchiveRetention.ps1 testing.
.DESCRIPTION
    This script creates a directory tree with a specified number of files and subfolders, and sets file modification dates in the past to simulate aging for retention tests.
.PARAMETER RootPath
    The root directory where test data will be created.
.PARAMETER FileCount
    Total number of files to create (default: 100).
.PARAMETER FolderCount
    Number of subfolders to create (default: 10).
.PARAMETER MinAgeDays
    Minimum file age in days (default: 1).
.PARAMETER MaxAgeDays
    Maximum file age in days (default: 180).
.EXAMPLE
    .\Generate-TestData.ps1 -RootPath 'D:\TestArchives' -FileCount 200 -FolderCount 20 -MinAgeDays 10 -MaxAgeDays 120
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$RootPath,
    [int]$FileCount = 100,
    [int]$FolderCount = 10,
    [int]$MinAgeDays = 1,
    [int]$MaxAgeDays = 180
)

# Create root directory if it doesn't exist
if (-not (Test-Path -Path $RootPath)) {
    New-Item -ItemType Directory -Path $RootPath | Out-Null
}

# Generate subfolders
$folders = @($RootPath)
for ($i = 1; $i -le $FolderCount; $i++) {
    $sub = Join-Path $RootPath ("Subfolder_$i")
    if (-not (Test-Path $sub)) {
        New-Item -ItemType Directory -Path $sub | Out-Null
    }
    $folders += $sub
}

# Generate files with random ages
$rand = New-Object System.Random
for ($i = 1; $i -le $FileCount; $i++) {
    $folder = $folders[$rand.Next(0, $folders.Count)]
    $file = Join-Path $folder ("TestFile_{0:D4}.txt" -f $i)
    Set-Content -Path $file -Value "This is test file $i."
    $age = $rand.Next($MinAgeDays, $MaxAgeDays+1)
    $modDate = (Get-Date).AddDays(-$age)
    Set-ItemProperty -Path $file -Name LastWriteTime -Value $modDate
    Set-ItemProperty -Path $file -Name CreationTime -Value $modDate
    Set-ItemProperty -Path $file -Name LastAccessTime -Value $modDate
}

Write-Host "Generated $FileCount files in $($folders.Count) folders under $RootPath with ages $MinAgeDays-$MaxAgeDays days." -ForegroundColor Green 