# core.psm1 -- PATH mutation functions (package-private).
# Dot-sourced by export.psm1; assumes helpers.psm1 is already loaded.

<#
.SYNOPSIS
    Adds a directory to a PATH scope.
.DESCRIPTION
    Deduplicates entries (case-insensitive, normalized comparison).
.PARAMETER Path
    The directory path to add. Can be relative (will be resolved).
.PARAMETER Scope
    User, Machine, or Process. Defaults to User (permanent).
    Use Add-TempPath for temporary (process-only) entries.
.PARAMETER Position
    Where to insert: Beginning (prepend) or End (append). Default is End.
.EXAMPLE
    Add-Path -Path "C:\my-tools\bin"
    Add-Path -Path "C:\my-tools\bin" -Scope Machine
    Add-Path -Path "C:\my-tools\bin" -Position Beginning
#>
function Add-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [Parameter(Position=1)]
        [ValidateSet('User', 'Machine', 'Process')]
        [string]$Scope = 'User',
        [ValidateSet('Beginning', 'End')]
        [string]$Position = 'End'
    )
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
.PARAMETER Scope
    User, Machine, or Process. Defaults to User (permanent).
.EXAMPLE
    Remove-Path -Path "C:\my-tools\bin"
    Remove-Path -Path "C:\my-tools\bin" -Scope Machine
#>
function Remove-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [Parameter(Position=1)]
        [ValidateSet('User', 'Machine', 'Process')]
        [string]$Scope = 'User'
    )
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
