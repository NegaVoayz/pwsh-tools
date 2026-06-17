# loader.ps1 -- Backward-compatible redirect to bootstrap/.
# New code should call bootstrap/loader.ps1 and bootstrap/init.ps1 directly.

$PwshToolsRoot = $PSScriptRoot
. "$PSScriptRoot\bootstrap\loader.ps1"
. "$PSScriptRoot\bootstrap\init.ps1"
