# auto.ps1 -- Auto-bookmark: trigger bookmarks automatically on cd.
#
# Enable-AutoBookmark overrides Set-Location to check for bookmarks
# marked with -Auto. Disable-AutoBookmark restores the original.

$script:_OriginalSetLocation = $null
$script:_AutoEnabled = $false
$script:_ActiveAutoBm = $null     # currently active auto-bookmark entry
$script:_SavedAutoEnv = $null     # env values saved before auto-apply

# Finds the first auto-bookmark matching the given path.
# Returns a hashtable with keys: entry (the bookmark), name (its key).
function _Find-AutoBookmark {
    param([string]$TargetPath)
    $bookmarks = _Load-Bookmarks
    $normalized = $TargetPath.TrimEnd('\')
    foreach ($key in $bookmarks.Keys) {
        $bm = $bookmarks[$key]
        if (-not $bm.auto) { continue }
        $bmPath = $bm.path.TrimEnd('\')
        if ($bm.recurse) {
            if ($normalized.StartsWith($bmPath, [StringComparison]::OrdinalIgnoreCase)) {
                return @{ entry = $bm; name = $key }
            }
        } else {
            if ($normalized -eq $bmPath) {
                return @{ entry = $bm; name = $key }
            }
        }
    }
    return $null
}

# Checks whether a path is still within an active auto-bookmark's scope.
function _StillInScope {
    param($bm, [string]$Path)
    $normalized = $Path.TrimEnd('\')
    $bmPath = $bm.path.TrimEnd('\')
    if ($bm.recurse) {
        return $normalized.StartsWith($bmPath, [StringComparison]::OrdinalIgnoreCase)
    }
    return $normalized -eq $bmPath
}

# Saves current process env values for the given var names.
function _Save-EnvValues {
    param([string[]]$Names)
    $saved = @{}
    foreach ($n in $Names) {
        $saved[$n] = [string][Environment]::GetEnvironmentVariable($n, 'Process')
    }
    return $saved
}

# Restores env values and cleans up any vars not in the saved set.
function _Restore-EnvValues {
    param($Saved, $Applied)
    # Restore original values
    foreach ($key in $Saved.Keys) {
        [Environment]::SetEnvironmentVariable($key, $Saved[$key], 'Process')
    }
    # Remove any vars that were applied but weren't in the original env
    if ($Applied) {
        foreach ($key in $Applied.PSObject.Properties.Name) {
            if (-not $Saved.ContainsKey($key)) {
                [Environment]::SetEnvironmentVariable($key, $null, 'Process')
            }
        }
    }
}

<#
.SYNOPSIS
    Enables auto-bookmarks: runs init code automatically on cd.
.DESCRIPTION
    Overrides Set-Location (cd) to check for bookmarks marked with
    -Auto. When you cd into a matching directory, the bookmark's init
    code runs automatically (env restoration is NOT automatic -- use
    Use-Bookmark -RestoreEnv for that).
.EXAMPLE
    Enable-AutoBookmark
    cd C:\projects\myapp   # init code runs if bookmark has -Auto
    Disable-AutoBookmark
#>
function Enable-AutoBookmark {
    [CmdletBinding()]
    param()

    if ($script:_AutoEnabled) {
        Write-Warning "Auto-bookmarks are already enabled."
        return
    }

    $script:_OriginalSetLocation = Get-Command Microsoft.PowerShell.Management\Set-Location -CommandType Cmdlet -ErrorAction SilentlyContinue
    $script:_AutoEnabled = $true

    # Wrap Set-Location with auto-bookmark enter/leave logic.
    # On entering a matched directory: save env, apply bookmark env, run init.
    # On leaving: roll back env to saved values.
    $wrapper = {
        [CmdletBinding()]
        param(
            [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [string]$Path,
            [switch]$PassThru,
            [switch]$LiteralPath,
            [string]$StackName
        )
        Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
        $mod = Get-Module bookmark
        if (-not $mod) { return }

        $newPath = (Get-Location).Path
        $match = & $mod { _Find-AutoBookmark $newPath }
        $active = & $mod { $script:_ActiveAutoBm }
        $saved = & $mod { $script:_SavedAutoEnv }

        # Rollback: leaving the active bookmark's scope
        if ($active) {
            if ($match -and $match.name -eq $active.name) {
                # Still within same bookmark — keep active, nothing to do
                return
            }
            # Leaving scope — restore env
            $applied = $active.entry.env
            & $mod { _Restore-EnvValues $saved $applied; $script:_ActiveAutoBm = $null; $script:_SavedAutoEnv = $null }
            Write-Verbose "[bookmark] Left auto-bookmark scope, env restored"
        }

        # Enter: new bookmark matched (only if not already active for same one)
        if ($match) {
            $bm = $match.entry
            # Save current env for vars the bookmark would touch
            $varsToSave = @()
            if ($bm.env) { $varsToSave += $bm.env.PSObject.Properties.Name }
            $newSaved = & $mod { _Save-EnvValues $varsToSave }
            # Apply env snapshot
            if ($bm.env) {
                foreach ($key in $bm.env.PSObject.Properties.Name) {
                    Set-Item -Path "Env:$key" -Value $bm.env.$key
                }
                Write-Verbose "[bookmark] Auto-applied env snapshot"
            }
            # Run init
            if ($bm.init) {
                try { Invoke-Expression $bm.init -ErrorAction Stop }
                catch { Write-Host "[bookmark] Auto-init failed: $_" -ForegroundColor Red }
            }
            & $mod { $script:_ActiveAutoBm = $match; $script:_SavedAutoEnv = $newSaved }
        }
    }
    Set-Item -Path function:global:Set-Location -Value $wrapper -Force
    Write-Host "  Auto-bookmarks enabled -- bookmarks with -Auto will trigger on cd." -ForegroundColor Green
}

<#
.SYNOPSIS
    Disables auto-bookmarks and restores the original Set-Location.
#>
function Disable-AutoBookmark {
    [CmdletBinding()]
    param()

    if (-not $script:_AutoEnabled) {
        Write-Warning "Auto-bookmarks are not enabled."
        return
    }

    Remove-Item function:\global:Set-Location -Force -ErrorAction SilentlyContinue
    $script:_AutoEnabled = $false
    Write-Host "  Auto-bookmarks disabled." -ForegroundColor Green
}
