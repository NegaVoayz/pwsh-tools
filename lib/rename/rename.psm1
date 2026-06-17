# rename/rename.psm1 -- Batch file renaming package entry point.

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\core.ps1"

Export-ModuleMember -Function @('Rename-File')
