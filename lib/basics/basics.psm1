# basics/export.ps1 — Unix-like commands package.
#
# Dot-sources all sub-modules, then exports every public function.

. "$PSScriptRoot\disks.ps1"
. "$PSScriptRoot\files.ps1"
. "$PSScriptRoot\headtail.ps1"
. "$PSScriptRoot\grep.ps1"
. "$PSScriptRoot\sudo.ps1"
. "$PSScriptRoot\wc.ps1"
. "$PSScriptRoot\which.ps1"
. "$PSScriptRoot\navigate.ps1"

Export-ModuleMember -Function @(
    'df', 'du',
    'touch', 'ln',
    'head', 'tail',
    'grep',
    'sudo',
    'wc',
    'which',
    'mkcd'
)
