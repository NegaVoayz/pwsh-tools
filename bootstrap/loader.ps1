# bootstrap/loader.ps1 -- Package discovery, import, and init hooks.
#
# Dot-sourced by profile.ps1. Expects $PwshToolsRoot to be set
# to the repository root before being called.

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

# Phase 1: Import all packages
foreach ($exportPath in $exports) {
    $packageName = Split-Path (Split-Path $exportPath -Parent) -Leaf
    try {
        Import-Module -Name $exportPath -Force -ErrorAction Stop
        Write-Verbose "[pwsh-tools] Loaded package: $packageName" -Verbose:$false
    } catch {
        Write-Warning "[pwsh-tools] Failed to load package '$packageName': $_"
    }
}

# Phase 2: Run module init hooks
# Each module may optionally define an internal _Invoke-OnInit function.
# It is NOT exported — the loader discovers it via the module scope.
# This avoids polluting the user's command namespace and prevents
# collision when multiple modules define init hooks.
foreach ($exportPath in $exports) {
    $module = Get-Module | Where-Object { $_.Path -eq $exportPath }
    if (-not $module) { continue }
    $initCmd = & $module { Get-Command _Invoke-OnInit -ErrorAction SilentlyContinue }
    if (-not $initCmd) { continue }
    $packageName = $module.Name
    try {
        Write-Verbose "[pwsh-tools] Running init hook: $packageName"
        & $initCmd
    } catch {
        Write-Warning "[pwsh-tools] Init hook failed for '$packageName': $_"
    }
}
