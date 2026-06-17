# diff.ps1 — Permanent vs temporary PATH diff (Compare-Path).

# Returns merged permanent PATH entries (Machine + User, normalized).
function _Get-PermanentPathEntries {
    $machine = _Get-PathEntries 'Machine' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ }
    $user = _Get-PathEntries 'User' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ }
    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $machine + $user) {
        if (-not $seen.Contains($e)) {
            $result.Add($e)
            $null = $seen.Add($e)
        }
    }
    return $result
}

<#
.SYNOPSIS
    Compares process (temporary) PATH against permanent (registry) PATH.
.DESCRIPTION
    Shows PATH entries that differ between the current process scope
    and the permanent User/Machine registry values. Useful for seeing
    which temp PATH entries would be lost on shell exit.
.PARAMETER Check
    Verify each entry exists on disk (green = exists, red = missing).
.EXAMPLE
    Compare-Path
    Compare-Path -Check
#>
function Compare-Path {
    [CmdletBinding()]
    param(
        [switch]$Check
    )

    $processEntries = @(_Get-PathEntries 'Process' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ })
    $permanentEntries = _Get-PermanentPathEntries

    $processSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $processEntries) { $null = $processSet.Add($e) }

    $permanentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $permanentEntries) { $null = $permanentSet.Add($e) }

    $rows = @()
    $i = 1

    foreach ($entry in $processEntries) {
        $isTemp = -not $permanentSet.Contains($entry)
        $label = if ($isTemp) { 'TEMP' } else { '' }

        if ($Check) {
            $exists = Test-Path -LiteralPath $entry -ErrorAction SilentlyContinue
            if ($exists) {
                $display = $entry
            } else {
                $display = "$entry (missing)"
                $label = if ($isTemp) { 'TEMP, missing' } else { 'missing' }
            }
        } else {
            $display = $entry
        }

        $color = if ($isTemp) { 'Yellow' } else { 'White' }
        $numStr = "$i".PadLeft(3)
        $flagStr = if ($label) { "  [$label]" } else { '' }

        Write-Host "  $numStr. " -NoNewline -ForegroundColor DarkGray
        Write-Host $display -NoNewline -ForegroundColor $color
        if ($label) { Write-Host $flagStr -NoNewline -ForegroundColor Yellow }
        Write-Host ""

        $i++
    }

    # Show permanent-only entries (removed from process)
    $permOnly = @($permanentEntries | Where-Object { -not $processSet.Contains($_) })
    if ($permOnly.Count -gt 0) {
        Write-Host ""
        Write-Host "  Permanent-only (removed from current session):" -ForegroundColor DarkGray
        Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
        foreach ($entry in $permOnly) {
            $display = if ($Check) {
                if (Test-Path -LiteralPath $entry -ErrorAction SilentlyContinue) { $entry } else { "$entry (missing)" }
            } else { $entry }
            Write-Host "    - $display" -ForegroundColor Red
        }
    }

    $tempCount = ($processEntries | Where-Object { -not $permanentSet.Contains($_) }).Count
    if ($tempCount -gt 0) {
        Write-Host ""
        Write-Host "  ($tempCount temp PATH entries — use 'Save-Path -All' to permanentize)" -ForegroundColor DarkGray
    } elseif ($permOnly.Count -eq 0) {
        Write-Host ""
        Write-Host "  Process PATH matches permanent PATH (no differences)." -ForegroundColor Green
    }
}
