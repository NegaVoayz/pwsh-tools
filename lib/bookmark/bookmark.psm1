# bookmark/bookmark.psm1 -- Directory bookmark package entry point.
#
# Provides mark/jump/marks/unmark for storing and navigating to
# bookmarked directories, with optional env snapshots and init code.

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\storage.ps1"
. "$PSScriptRoot\core.ps1"
. "$PSScriptRoot\view.ps1"

Export-ModuleMember -Function @(
    'Set-Bookmark',
    'Use-Bookmark',
    'Get-Bookmark',
    'Remove-Bookmark'
)
