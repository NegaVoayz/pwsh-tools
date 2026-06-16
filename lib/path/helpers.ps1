# helpers.psm1 — Internal PATH utilities (package-private).
# Dot-sourced by export.psm1; never imported directly.

function _Normalize-PathEntry {
    param([string]$Entry)
    return $Entry.Trim().TrimEnd('\').Replace('/', '\')
}

function _Resolve-PathEntry {
    param([string]$Entry)
    $trimmed = $Entry.Trim().TrimEnd('\').Replace('/', '\')
    if ([System.IO.Path]::IsPathRooted($trimmed)) { return $trimmed }
    return [System.IO.Path]::GetFullPath($trimmed)
}

function _Get-PathEntries {
    param([string]$Scope)
    $raw = _Get-PathRaw -Scope $Scope
    return $raw -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() }
}

function _Get-PathRaw {
    param([string]$Scope)
    $value = [Environment]::GetEnvironmentVariable('PATH', $Scope)
    if ($null -eq $value) { return '' } else { return $value }
}

function _Set-PathEntries {
    param([string[]]$Entries, [string]$Scope)
    $raw = ($Entries -join ';').TrimEnd(';')
    [Environment]::SetEnvironmentVariable('PATH', $raw, $Scope)
    if ($Scope -ne 'Process') {
        $userPath    = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $parts = @($machinePath, $userPath) | Where-Object { $_ }
        $env:PATH = $parts -join ';'
    }
}
