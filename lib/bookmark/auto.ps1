# auto.ps1 -- Auto-bookmark: trigger bookmarks automatically on cd.
#
# Enable-AutoBookmark overrides Set-Location to check for bookmarks
# marked with -Auto. Disable-AutoBookmark restores the original.

$script:_OriginalSetLocation = $null
$script:_AutoEnabled = $false

# Finds the first auto-bookmark matching the given path.
# Returns the bookmark entry or $null.
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
                return $bm
            }
        } else {
            if ($normalized -eq $bmPath) {
                return $bm
            }
        }
    }
    return $null
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

    # Wrap Set-Location with auto-bookmark check.
    # The wrapper calls the original cmdlet, then checks if the new location
    # matches any -Auto bookmark and runs its init code.
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
        if ($mod) {
            $bm = & $mod { _Find-AutoBookmark (Get-Location).Path }
            if ($bm -and $bm.init) {
                try { Invoke-Expression $bm.init -ErrorAction Stop }
                catch { Write-Host "[bookmark] Auto-init failed: $_" -ForegroundColor Red }
            }
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
