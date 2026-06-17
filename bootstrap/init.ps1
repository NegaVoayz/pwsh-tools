# bootstrap/init.ps1 -- Per-package init module runner.
#
# Dot-sourced by profile.ps1 after bootstrap/loader.ps1.
# Expects $PwshToolsRoot to be set.
#
# Scans lib/*/init.psm1 and imports each one. Unlike <pkg>.psm1,
# an init.psm1 does NOT export functions — its module body IS the
# init action, executed at import time.

$libPath = Join-Path $PwshToolsRoot 'lib'

$initModules = @(Get-ChildItem -Path "$libPath\*\init.psm1" -ErrorAction SilentlyContinue | Sort-Object)

foreach ($initPath in $initModules) {
    $packageName = Split-Path (Split-Path $initPath -Parent) -Leaf
    try {
        Write-Verbose "[pwsh-tools] Running init: $packageName"
        Import-Module -Name $initPath.FullName -Force -ErrorAction Stop
    } catch {
        Write-Warning "[pwsh-tools] Init failed for '$packageName': $_"
    }
}
