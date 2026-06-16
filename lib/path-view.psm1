# path-view.psm1 - PATH inspection and display.
#
# Exports: Get-Path, Show-Path
# Depends on path.psm1 for internal _Get-PathEntries / _Get-PathRaw helpers.

Import-Module "$PSScriptRoot\path.psm1" -Force -ErrorAction Stop -WarningAction SilentlyContinue

<#
.SYNOPSIS
    Gets PATH entries for a scope.
.DESCRIPTION
    Returns PATH entries as an array of strings, one per directory.
    Also supports returning the raw semicolon-separated string.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.PARAMETER Raw
    If specified, returns the raw semicolon-separated string instead of an array.
.EXAMPLE
    Get-Path -Scope User | ForEach-Object { Write-Host $_ }
    Get-Path -Scope Machine -Raw
#>
function Get-Path {
    [CmdletBinding()]
    param(
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Raw
    )
    if ($Raw) { return _Get-PathRaw -Scope $Scope }
    return _Get-PathEntries -Scope $Scope
}

<#
.SYNOPSIS
    Displays PATH entries in a readable numbered list.
.DESCRIPTION
    Shows PATH entries with index numbers, scope label, and optional
    existence checks. Missing directories are highlighted.
    Purely for display - use Get-Path for programmatic access.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.PARAMETER Check
    If specified, checks whether each PATH entry exists on disk.
.EXAMPLE
    Show-Path
    Show-Path -Scope User -Check
#>
function Show-Path {
    [CmdletBinding()]
    param(
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Check
    )
    $entries = _Get-PathEntries -Scope $Scope
    if ($entries.Count -eq 0) { Write-Host "[$Scope PATH] (empty)"; return }
    Write-Host "[$Scope PATH] ($($entries.Count) entries):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $idx   = "{0,3}" -f ($i + 1)
        $entry = $entries[$i]
        if ($Check) {
            if ($entry -match '%\w+%') {
                Write-Host "  $idx. $entry" -ForegroundColor Yellow
            } elseif (Test-Path $entry) {
                Write-Host "  $idx. $entry" -ForegroundColor Green
            } else {
                Write-Host "  $idx. $entry (missing)" -ForegroundColor Red
            }
        } else {
            Write-Host "  $idx. $entry"
        }
    }
}

Export-ModuleMember -Function @('Get-Path', 'Show-Path')
