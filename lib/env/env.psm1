# env/env.psm1 -- Environment variable management package entry point.
#
# Dot-sources internal modules in dependency order (core first, then
# temp modules that may reference core functions), then exports only
# the public API.

. "$PSScriptRoot\core.ps1"
. "$PSScriptRoot\tempenv.ps1"
. "$PSScriptRoot\tempenv_view.ps1"
. "$PSScriptRoot\env_diff.ps1"

Export-ModuleMember -Function @(
    'Set-Env',
    'Get-Env',
    'Remove-Env',
    'Set-TempEnv',
    'Get-TempEnv',
    'Remove-TempEnv',
    'Save-Env',
    'Clear-TempEnv',
    'Compare-Env'
)
