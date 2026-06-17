# view.ps1 — Bookmark listing (marks).

<#
.SYNOPSIS
    Lists stored directory bookmarks.
.DESCRIPTION
    Shows all bookmarked directories with their paths and flags.
    Use -Detail to show env snapshot keys and init code.
.PARAMETER Detail
    Show env snapshot keys and init code for each bookmark.
.EXAMPLE
    marks
    marks -Detail
#>
function marks {
    [CmdletBinding()]
    param(
        [switch]$Detail
    )

    $bookmarks = _Load-Bookmarks

    if ($bookmarks.Count -eq 0) {
        Write-Host "  (no bookmarks)" -ForegroundColor DarkGray
        Write-Host "  Use 'mark <name>' to store the current directory." -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "  Bookmarks" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $maxNameLen = ($bookmarks.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    if ($maxNameLen -lt 4) { $maxNameLen = 4 }

    foreach ($key in $bookmarks.Keys) {
        $entry = $bookmarks[$key]

        $flags = @()
        if ($entry.env) { $flags += 'env' }
        if ($entry.init) { $flags += 'init' }
        $flagStr = if ($flags.Count -gt 0) {
            "  [$($flags -join ', ')]"
        } else { '' }

        $exists = Test-Path -LiteralPath $entry.path -ErrorAction SilentlyContinue
        $pathColor = if ($exists) { 'White' } else { 'Red' }

        Write-Host "  $($key.PadRight($maxNameLen + 2))" -NoNewline -ForegroundColor Yellow
        Write-Host $entry.path -NoNewline -ForegroundColor $pathColor
        if (-not $exists) { Write-Host " (missing)" -NoNewline -ForegroundColor Red }
        if ($flagStr) { Write-Host $flagStr -NoNewline -ForegroundColor DarkGray }
        Write-Host ""

        if ($Detail) {
            if ($entry.env) {
                $envKeys = $entry.env.PSObject.Properties.Name -join ', '
                Write-Host "    env: $envKeys" -ForegroundColor DarkGray
            }
            if ($entry.init) {
                Write-Host "    init: $($entry.init)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
}
