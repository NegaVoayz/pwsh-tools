# core.ps1 -- Bookmark management commands (Set-Bookmark, Use-Bookmark, Remove-Bookmark).

<#
.SYNOPSIS
    Stores the current directory as a bookmark.
.DESCRIPTION
    Saves the current location under a name for quick return via
    Use-Bookmark. Optionally captures an environment variable snapshot
    and stores init code to run when jumping back.
.PARAMETER Name
    The bookmark name. Case-insensitive.
.PARAMETER Snapshot
    Capture env vars: All (all non-system), or Temp (only vars
    tracked via Set-TempEnv, permanentizable with Save-Env).
.PARAMETER NoSnapshot
    Remove any stored env snapshot from this bookmark.
.PARAMETER InitCode
    PowerShell code to execute when jumping to this bookmark.
.PARAMETER Auto
    Automatically run init code when cd'ing into this directory
    (requires Enable-AutoBookmark to be called first).
.PARAMETER Recurse
    With -Auto: also trigger in subdirectories of the bookmark.
.EXAMPLE
    Set-Bookmark myproject
    Set-Bookmark myproject -Snapshot Temp -Auto
    Set-Bookmark myproject -Auto -Recurse -InitCode "npx tsc --watch"
#>
function Set-Bookmark {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [ValidateSet('All', 'Temp')]
        [string]$Snapshot,
        [switch]$NoSnapshot,
        [string]$InitCode,
        [switch]$Auto,
        [switch]$Recurse
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
            auto    = $false
            recurse = $false
        }
        $bookmarks[$Name] = $entry
    } else {
        $entry.path = $currentPath
        $entry.created = (Get-Date -Format 'o')
    }

    if ($PSBoundParameters.ContainsKey('Auto')) { $entry.auto = $Auto }
    if ($PSBoundParameters.ContainsKey('Recurse')) { $entry.recurse = $Recurse }

    if ($Snapshot) {
        if ($Snapshot -eq 'Temp') {
            $entry.env = _Capture-TempEnvOnly
        } else {
            $entry.env = _Capture-EnvSnapshot
        }
        Write-Verbose "Captured env snapshot ($Snapshot) for '$Name'"
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
    if ($entry.auto) { $flags += 'auto' }
    if ($entry.recurse) { $flags += 'recurse' }
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
    Use-Bookmark myproject
    Use-Bookmark myproject -RestoreEnv
    Use-Bookmark myproject -NoInit
#>
function Use-Bookmark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [switch]$RestoreEnv,
        [switch]$NoInit
    )

    $bookmarks = _Load-Bookmarks

    if (-not $bookmarks.Contains($Name)) {
        Write-Error "Bookmark '$Name' not found. Use 'Get-Bookmark' to list bookmarks."
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
    Remove-Bookmark myproject
#>
function Remove-Bookmark {
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
