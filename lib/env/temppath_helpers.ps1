# temppath_helpers.ps1 — Internal PATH manipulation helpers for temp path.
# Self-contained: does NOT depend on the 'path' package.

# Trims, removes trailing backslash, normalizes forward slashes.
function _Normalize-PathEntry {
    param([string]$Entry)
    $e = $Entry.Trim()
    if ($e -match '^".+"$') { $e = $e.Substring(1, $e.Length - 2).Trim() }
    $e = $e -replace '/', '\'
    $e = $e.TrimEnd('\')
    if ($e -eq '') { $e = '\' }
    return $e
}

# Resolves relative paths to absolute, then normalizes.
function _Resolve-TempPath {
    param([string]$Path)
    $normalized = _Normalize-PathEntry $Path
    try {
        $resolved = [System.IO.Path]::GetFullPath($normalized)
        return _Normalize-PathEntry $resolved
    } catch {
        return $normalized
    }
}

# Returns the current process PATH as an array of cleaned entries.
function _Get-ProcessPathEntries {
    $raw = [Environment]::GetEnvironmentVariable('PATH', 'Process')
    if (-not $raw) { return @() }
    return $raw -split ';' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ }
}

# Rebuilds the process PATH from an array of entries.
function _Set-ProcessPathEntries {
    param([string[]]$Entries)
    $joined = $Entries -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $joined, 'Process')
    $env:PATH = $joined
}

# Adds entries to the persistent User PATH, deduplicating, and rebuilds process PATH.
function _Set-UserPathWithEntries {
    param([string[]]$NewEntries)
    $existing = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $existingEntries = if ($existing) {
        $existing -split ';' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ }
    } else { @() }

    $existingSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $existingEntries) { $null = $existingSet.Add($e) }

    $toAdd = @()
    foreach ($entry in $NewEntries) {
        $resolved = _Resolve-TempPath $entry
        if (-not $existingSet.Contains($resolved)) {
            $toAdd += $resolved
            $null = $existingSet.Add($resolved)
        }
    }

    if ($toAdd.Count -eq 0) { return }

    $final = $existingEntries + $toAdd
    $joined = $final -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $joined, 'User')

    # Rebuild process PATH = Machine + updated User
    $machineRaw = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $machineEntries = if ($machineRaw) {
        $machineRaw -split ';' | ForEach-Object { _Normalize-PathEntry $_ } | Where-Object { $_ }
    } else { @() }
    $processFinal = $machineEntries + $final
    $processJoined = $processFinal -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $processJoined, 'Process')
    $env:PATH = $processJoined
}
