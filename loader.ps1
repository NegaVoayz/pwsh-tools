# loader.ps1 -- Backward-compatible redirect to bootstrap/loader.ps1.
# New code should use bootstrap/loader.ps1 directly.

$PwshToolsRoot = $PSScriptRoot
. "$PSScriptRoot\bootstrap\loader.ps1"
