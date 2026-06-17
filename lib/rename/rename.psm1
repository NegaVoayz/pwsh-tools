# rename/rename.psm1 — Batch file renaming package entry point.
#
# Removes the built-in 'rename' alias (-> Rename-Item) so our function
# takes priority at the command line.

# Suppress the built-in rename alias if it exists
if (Test-Path 'Alias:\rename') {
    Remove-Item 'Alias:\rename' -Force -ErrorAction SilentlyContinue
}

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\core.ps1"

Export-ModuleMember -Function @('rename')
