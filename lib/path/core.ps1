# core.psm1 — PATH mutation functions (package-private).
# Dot-sourced by export.psm1; assumes helpers.psm1 is already loaded.

<#
.SYNOPSIS
    Adds a directory to a PATH scope.
.DESCRIPTION
    Deduplicates entries (case-insensitive, normalized comparison).
.PARAMETER Path
    The directory path to add. Can be relative (will be resolved).
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.PARAMETER Permanent
    Shorthand for -Scope User. Ignored if -Scope is also specified.
.PARAMETER Position
    Where to insert: Beginning (prepend) or End (append). Default is End.
.EXAMPLE
    Add-Path -Path "C:\my-tools\bin" -Permanent
    Add-Path -Path "C:\my-tools\bin" -Scope User -Position Beginning
#>
function Add-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Permanent,
        [ValidateSet('Beginning', 'End')]
        [string]$Position = 'End'
    )
    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) { $Scope = 'User' }
    $resolved = _Resolve-PathEntry $Path
    $current  = _Get-PathEntries -Scope $Scope
    $alreadyExists = $current | Where-Object {
        (_Normalize-PathEntry $_) -eq (_Normalize-PathEntry $resolved)
    }
    if ($alreadyExists) { Write-Verbose "PATH entry already present: $resolved (scope: $Scope)"; return }
    if ($Position -eq 'Beginning') { $newEntries = @($resolved) + $current }
    else                          { $newEntries = $current + @($resolved) }
    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add $resolved")) {
        _Set-PathEntries -Entries $newEntries -Scope $Scope
        Write-Verbose "Added to $Scope PATH: $resolved"
    }
}

<#
.SYNOPSIS
    Removes a directory from a PATH scope.
.DESCRIPTION
    Matching is case-insensitive with path normalization.
.PARAMETER Path
    The directory path to remove.
.PARAMETER Permanent
    Shorthand for -Scope User. Ignored if -Scope is also specified.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.EXAMPLE
    Remove-Path -Path "C:\my-tools\bin" -Permanent
    Remove-Path -Path "C:\my-tools\bin" -Scope User
#>
function Remove-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Permanent
    )
    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) { $Scope = 'User' }
    $current  = _Get-PathEntries -Scope $Scope
    $target   = _Normalize-PathEntry $Path
    $count    = $current.Count
    $newEntries = $current | Where-Object { (_Normalize-PathEntry $_) -ne $target }
    $removed = $count - $newEntries.Count
    if ($removed -eq 0) { Write-Verbose "PATH entry not found: $Path (scope: $Scope)"; return }
    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Remove $Path ($removed entries)")) {
        _Set-PathEntries -Entries $newEntries -Scope $Scope
        Write-Verbose "Removed from $Scope PATH: $Path ($removed match(es))"
    }
}
