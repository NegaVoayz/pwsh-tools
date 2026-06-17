# core.ps1 — Bookmark management commands (mark, jump, unmark).

<#
.SYNOPSIS
    Stores the current directory as a bookmark.
.DESCRIPTION
    Saves the current location under a name for quick return via
    'jump'. Optionally captures an environment variable snapshot
    and stores init code to run when jumping back.
.PARAMETER Name
    The bookmark name. Case-insensitive.
.PARAMETER Snapshot
    Capture current environment variables with this bookmark.
.PARAMETER NoSnapshot
    Remove any stored env snapshot from this bookmark.
.PARAMETER InitCode
    PowerShell code to execute when jumping to this bookmark.
.EXAMPLE
    mark myproject
    mark myproject -Snapshot
    mark myproject -InitCode "npx tsc --watch"
#>
function mark {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [switch]$Snapshot,
        [switch]$NoSnapshot,
        [string]$InitCode
    )

    $currentPath = (Get-Location).Path
    $bookmarks = _Load-Bookmarks

    $entry = if ($bookmarks.Contains($Name)) { $bookmarks[$Name] } else { $null }

    if ($entry) {
        $action = "Update bookmark '$Name'"
    } else {
        $action = "Create bookmark '$Name'"
    }

    if (-not $PSCmdlet.ShouldProcess($currentPath, $action)) { return }

    if (-not $entry) {
        $entry = [PSCustomObject]@{
            path    = $currentPath
            created = (Get-Date -Format 'o')
            env     = $null
            init    = $null
        }
        $bookmarks[$Name] = $entry
    } else {
        $entry.path = $currentPath
        $entry.created = (Get-Date -Format 'o')
    }

    if ($Snapshot) {
        $entry.env = _Capture-EnvSnapshot
        Write-Verbose "Captured env snapshot for '$Name'"
    } elseif ($NoSnapshot) {
        $entry.env = $null
        Write-Verbose "Removed env snapshot from '$Name'"
    }

    if ($PSBoundParameters.ContainsKey('InitCode')) {
        if ($InitCode) {
            $entry.init = $InitCode
            Write-Verbose "Stored init code for '$Name'"
        } else {
            $entry.init = $null
            Write-Verbose "Cleared init code for '$Name'"
        }
    }

    _Save-Bookmarks $bookmarks

    $flags = @()
    if ($entry.env) { $flags += 'env' }
    if ($entry.init) { $flags += 'init' }
    $flagStr = if ($flags.Count -gt 0) { " ($($flags -join ', '))" } else { '' }

    Write-Host "  [$Name] -> $currentPath$flagStr" -ForegroundColor Green
}

<#
.SYNOPSIS
    Jumps to a stored bookmark directory.
.DESCRIPTION
    Changes the current location to a bookmarked directory.
    Optionally restores stored environment variables and runs
    stored init code.
.PARAMETER Name
    The bookmark name to jump to.
.PARAMETER RestoreEnv
    Restore the environment snapshot stored with this bookmark.
.PARAMETER NoInit
    Skip running the stored init code.
.EXAMPLE
    jump myproject
    jump myproject -RestoreEnv
    jump myproject -NoInit
#>
function jump {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [switch]$RestoreEnv,
        [switch]$NoInit
    )

    $bookmarks = _Load-Bookmarks

    if (-not $bookmarks.Contains($Name)) {
        Write-Error "Bookmark '$Name' not found. Use 'marks' to list bookmarks."
        return
    }

    $entry = $bookmarks[$Name]

    if (-not (Test-Path -LiteralPath $entry.path)) {
        Write-Warning "Bookmarked path no longer exists: $($entry.path)"
    }

    if ($RestoreEnv -and $entry.env) {
        foreach ($key in $entry.env.PSObject.Properties.Name) {
            Set-Item -Path "Env:$key" -Value $entry.env.$key
        }
        Write-Verbose "Restored env snapshot for '$Name'"
    } elseif ($RestoreEnv -and -not $entry.env) {
        Write-Warning "Bookmark '$Name' has no stored env snapshot."
    }

    if (-not $NoInit -and $entry.init) {
        Write-Verbose "Running init code for '$Name'"
        try {
            Invoke-Expression $entry.init -ErrorAction Stop
        } catch {
            Write-Warning "Init code for '$Name' failed: $_"
        }
    }

    Set-Location -LiteralPath $entry.path
    Write-Verbose "Jumped to: $($entry.path)"
}

<#
.SYNOPSIS
    Removes a stored bookmark.
.DESCRIPTION
    Deletes a named bookmark. Does not affect the directory itself.
.PARAMETER Name
    The bookmark name to remove.
.EXAMPLE
    unmark myproject
#>
function unmark {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name
    )

    $bookmarks = _Load-Bookmarks

    if (-not $bookmarks.Contains($Name)) {
        Write-Warning "Bookmark '$Name' not found."
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Remove bookmark")) {
        $bookmarks.Remove($Name)
        _Save-Bookmarks $bookmarks
        Write-Host "  Removed bookmark: $Name" -ForegroundColor Green
    }
}
