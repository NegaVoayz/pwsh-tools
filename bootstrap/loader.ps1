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
# Each module may optionally export an Invoke-OnInit function.
# These are called after all packages are loaded, so they can
# depend on other packages being available.
foreach ($exportPath in $exports) {
    $module = Get-Module | Where-Object { $_.Path -eq $exportPath }
    if (-not $module) { continue }
    $initCmd = $module.ExportedCommands['Invoke-OnInit']
    if (-not $initCmd) { continue }
    $packageName = $module.Name
    try {
        Write-Verbose "[pwsh-tools] Running init hook: $packageName"
        & $initCmd
    } catch {
        Write-Warning "[pwsh-tools] Init hook failed for '$packageName': $_"
    }
}
