# storage.ps1 — JSON persistence for bookmarks.

# Loads bookmarks from JSON. Returns empty ordered dictionary if file is
# missing, empty, or corrupted.
function _Load-Bookmarks {
    $file = _Get-BookmarkFile

    if (-not (Test-Path $file)) {
        return [ordered]@{}
    }

    try {
        $content = Get-Content $file -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content -or $content.Trim().Length -eq 0) {
            return [ordered]@{}
        }
        $data = ConvertFrom-Json $content -ErrorAction Stop

        # Validate version
        if (-not $data.version) {
            Write-Warning "Bookmarks file is missing version info. Treating as empty."
            return [ordered]@{}
        }

        $result = [ordered]@{}
        if ($data.bookmarks) {
            $bm = $data.bookmarks
            if ($bm -is [System.Management.Automation.PSCustomObject]) {
                foreach ($prop in $bm.PSObject.Properties) {
                    $result[$prop.Name] = $prop.Value
                }
            }
        }
        return $result
    } catch {
        Write-Warning "Failed to load bookmarks: $_"
        return [ordered]@{}
    }
}

# Saves bookmarks to JSON with pretty-printing.
function _Save-Bookmarks {
    param([hashtable]$Bookmarks)

    $file = _Get-BookmarkFile
    $dir = _Get-BookmarkDir

    # Convert to serializable object
    $wrapped = [PSCustomObject]@{
        version   = 1
        bookmarks = [PSCustomObject]$Bookmarks
    }

    try {
        $json = ConvertTo-Json $wrapped -Depth 10
        Set-Content -Path $file -Value $json -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Saved bookmarks to: $file"
    } catch {
        Write-Error "Failed to save bookmarks: $_"
        throw
    }
}
