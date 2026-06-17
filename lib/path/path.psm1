# path/export.psm1 -- PATH management package entry point.
#
# Dot-sources internal modules in dependency order (helpers first),
# then exports only the public API. Internal _ functions stay
# package-private.

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\core.ps1"
. "$PSScriptRoot\view.ps1"
. "$PSScriptRoot\temppath.ps1"
. "$PSScriptRoot\diff.ps1"

Export-ModuleMember -Function @(
    'Add-Path',
    'Remove-Path',
    'Get-Path',
    'Show-Path',
    'Add-TempPath',
    'Remove-TempPath',
    'Save-Path',
    'Compare-Path'
)
