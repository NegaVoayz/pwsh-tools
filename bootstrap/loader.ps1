# bootstrap/loader.ps1 -- Package discovery and import.
#
# Dot-sourced by profile.ps1. Expects $PwshToolsRoot to be set
# to the repository root before being called.
#
# This file handles Phase 1 (loading). Phase 2 (init hooks) is
# handled by bootstrap/init.ps1, called afterwards.

$libPath = Join-Path $PwshToolsRoot 'lib'

if (-not (Test-Path $libPath)) {
    Write-Warning "[pwsh-tools] lib\ directory not found: $libPath"
    return
}

$exports = @(Get-ChildItem -Path $libPath -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "$($_.Name).psm1" } |
    Where-Object { Test-Path $_ } |
    Sort-Object)

if ($exports.Count -eq 0) {
    return
}

# Import all packages
foreach ($exportPath in $exports) {
    $packageName = Split-Path (Split-Path $exportPath -Parent) -Leaf
    try {
        Import-Module -Name $exportPath -Force -ErrorAction Stop
        Write-Verbose "[pwsh-tools] Loaded package: $packageName" -Verbose:$false
    } catch {
        Write-Warning "[pwsh-tools] Failed to load package '$packageName': $_"
    }
}
