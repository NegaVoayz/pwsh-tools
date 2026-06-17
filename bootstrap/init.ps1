# bootstrap/init.ps1 -- Module init-hook runner.
#
# Dot-sourced by profile.ps1 after bootstrap/loader.ps1.
# Expects $PwshToolsRoot to be set.
#
# Scans each loaded package for an internal _Invoke-OnInit function
# and calls it. The function is NOT exported — it is discovered via
# module-scope introspection so it never pollutes the user's namespace.

$libPath = Join-Path $PwshToolsRoot 'lib'
$exports = @(Get-ChildItem -Path $libPath -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "$($_.Name).psm1" } |
    Where-Object { Test-Path $_ } |
    Sort-Object)

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
