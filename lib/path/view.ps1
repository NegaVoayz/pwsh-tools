# view.psm1 — PATH inspection functions (package-private).
# Dot-sourced by export.psm1; assumes helpers.psm1 is already loaded.

<#
.SYNOPSIS
    Gets PATH entries for a scope.
.DESCRIPTION
    Returns PATH entries as an array, one per directory.
    Use -Raw for the raw semicolon-separated string.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.PARAMETER Raw
    Return the raw semicolon-separated string.
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
    Shows entries with index, scope label, and optional existence check.
    Use Get-Path for programmatic access.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.PARAMETER Check
    If specified, checks whether each entry exists on disk.
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
