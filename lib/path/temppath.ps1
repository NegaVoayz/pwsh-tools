# temppath.ps1 — Temporary PATH entry tracking and permanentization.
#
# Module-scoped state lives for the duration of the PowerShell session.
# _TempPathEntries tracks PATH entries added via Set-TempPath.

$script:_TempPathEntries = [System.Collections.Generic.List[string]]::new()

# Returns normalized process PATH entries for deduplication.
function _Get-NormalizedProcessPath {
    $entries = _Get-PathEntries 'Process'
    return @($entries | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ })
}

# Adds entries to the persistent User PATH and rebuilds process PATH.
function _Add-ToUserPath {
    param([string[]]$NewEntries)
    $existing = @(_Get-PathEntries 'User' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ })

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $existing) { $null = $set.Add($e) }

    $toAdd = @()
    foreach ($entry in $NewEntries) {
        $resolved = _Resolve-PathEntry $entry
        $normalized = _Normalize-PathEntry $resolved
        if (-not $set.Contains($normalized)) {
            $toAdd += $normalized
            $null = $set.Add($normalized)
        }
    }

    if ($toAdd.Count -eq 0) { return }

    $final = $existing + $toAdd
    _Set-PathEntries $final 'User'
    # _Set-PathEntries with non-Process scope already rebuilds $env:PATH
}

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

    $resolved = _Resolve-PathEntry $Path
    $normalized = _Normalize-PathEntry $resolved
    $currentEntries = _Get-NormalizedProcessPath

    $currentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $currentEntries) { $null = $currentSet.Add($e) }

    if ($currentSet.Contains($normalized)) {
        Write-Warning "'$normalized' is already in the process PATH."
        return
    }

    if ($script:_TempPathEntries -contains $normalized) {
        Write-Warning "'$normalized' is already tracked as a temp PATH entry."
        return
    }

    if ($PSCmdlet.ShouldProcess("Process PATH", "Add $normalized")) {
        if ($Position -eq 'Beginning') {
            $newEntries = @($normalized) + $currentEntries
        } else {
            $newEntries = $currentEntries + @($normalized)
        }
        _Set-PathEntries $newEntries 'Process'
        $script:_TempPathEntries.Add($normalized)
        Write-Host "  Temp PATH + $normalized" -ForegroundColor Green
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

    $resolved = _Resolve-PathEntry $Path
    $normalized = _Normalize-PathEntry $resolved
    $found = $false

    for ($i = $script:_TempPathEntries.Count - 1; $i -ge 0; $i--) {
        if ($script:_TempPathEntries[$i] -eq $normalized) {
            $script:_TempPathEntries.RemoveAt($i)
            $found = $true
        }
    }

    if (-not $found) {
        Write-Warning "'$normalized' is not a tracked temp PATH entry."
    }

    $currentEntries = _Get-NormalizedProcessPath
    $newEntries = @($currentEntries | Where-Object { $_ -ne $normalized })

    if ($newEntries.Count -eq $currentEntries.Count) {
        if (-not $found) {
            Write-Warning "'$normalized' was not found in the process PATH."
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("Process PATH", "Remove $normalized")) {
        _Set-PathEntries $newEntries 'Process'
        Write-Host "  Temp PATH - $normalized" -ForegroundColor Green
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
        _Add-ToUserPath $entries
        $count = $script:_TempPathEntries.Count
        $script:_TempPathEntries.Clear()
        Write-Host "  Saved $count temp PATH entrie(s) -> User PATH" -ForegroundColor Green
    }
}
