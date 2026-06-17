# temppath.ps1 — Temporary PATH entry tracking and permanentization.
#
# Module-scoped state lives for the duration of the PowerShell session.
# _TempPathEntries tracks PATH entries added via Set-TempPath.

$script:_TempPathEntries = [System.Collections.Generic.List[string]]::new()

<#
.SYNOPSIS
    Adds a temporary PATH entry. (tracked, permanentizable).
.DESCRIPTION
    Adds a directory to the process-scope PATH and tracks it for
    later permanentization with Save-Path. Deduplicates against
    existing process PATH entries.
.PARAMETER Path
    The directory path to add to PATH.
.PARAMETER Position
    Add at Beginning or End of PATH. Default is End.
.EXAMPLE
    Set-TempPath C:\tools\bin
    Set-TempPath C:\project\node_modules\.bin -Position Beginning
#>
function Set-TempPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [ValidateSet('Beginning', 'End')]
        [string]$Position = 'End'
    )

    $resolved = _Resolve-TempPath $Path
    $currentEntries = _Get-ProcessPathEntries

    # Deduplicate (case-insensitive)
    $currentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $currentEntries) { $null = $currentSet.Add($e) }

    if ($currentSet.Contains($resolved)) {
        Write-Warning "'$resolved' is already in the process PATH."
        return
    }

    if ($script:_TempPathEntries -contains $resolved) {
        Write-Warning "'$resolved' is already tracked as a temp PATH entry."
        return
    }

    if ($PSCmdlet.ShouldProcess("Process PATH", "Add $resolved")) {
        if ($Position -eq 'Beginning') {
            $newEntries = @($resolved) + $currentEntries
        } else {
            $newEntries = $currentEntries + @($resolved)
        }
        _Set-ProcessPathEntries $newEntries
        $script:_TempPathEntries.Add($resolved)
        Write-Host "  Temp PATH + $resolved" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Removes a temporary PATH entry.
.DESCRIPTION
    Removes a directory from the process-scope PATH and from the
    temp tracking list.
.PARAMETER Path
    The directory path to remove from PATH.
.EXAMPLE
    Remove-TempPath C:\tools\bin
#>
function Remove-TempPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path
    )

    $resolved = _Resolve-TempPath $Path
    $found = $false

    # Remove from tracking list (case-insensitive)
    for ($i = $script:_TempPathEntries.Count - 1; $i -ge 0; $i--) {
        if ($script:_TempPathEntries[$i] -eq $resolved) {
            $script:_TempPathEntries.RemoveAt($i)
            $found = $true
        }
    }

    if (-not $found) {
        Write-Warning "'$resolved' is not a tracked temp PATH entry."
    }

    # Also remove from process PATH
    $currentEntries = _Get-ProcessPathEntries
    $newEntries = @($currentEntries | Where-Object { $_ -ne $resolved })

    if ($newEntries.Count -eq $currentEntries.Count) {
        if (-not $found) {
            Write-Warning "'$resolved' was not found in the process PATH."
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("Process PATH", "Remove $resolved")) {
        _Set-ProcessPathEntries $newEntries
        Write-Host "  Temp PATH - $resolved" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Permanentizes all tracked temporary PATH entries.
.DESCRIPTION
    Promotes ALL tracked temp PATH entries (added via Set-TempPath)
    from Process scope to persistent User scope in the registry.
    Clears the tracking list afterwards.
.PARAMETER All
    Required switch to confirm intent.
.EXAMPLE
    Save-Path -All
#>
function Save-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [switch]$All
    )

    if ($script:_TempPathEntries.Count -eq 0) {
        Write-Host "  (no temp PATH entries to save)" -ForegroundColor DarkGray
        return
    }

    $entries = $script:_TempPathEntries.ToArray()
    if ($PSCmdlet.ShouldProcess("User PATH", "Save $($entries.Count) temp path entries")) {
        _Set-UserPathWithEntries $entries
        $count = $script:_TempPathEntries.Count
        $script:_TempPathEntries.Clear()
        Write-Host "  Saved $count temp PATH entrie(s) -> User PATH" -ForegroundColor Green
    }
}
