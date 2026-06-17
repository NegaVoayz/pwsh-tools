# helpers.ps1 -- Internal rename transformation utilities.

# Splits a filename into (BaseName, Extension).
# Example: "file.tar.gz" -> ("file.tar", ".gz")
function _Split-Extension {
    param([string]$FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    if ($ext -eq $FileName) {
        return @($ext, '')
    }
    $base = $FileName.Substring(0, $FileName.Length - $ext.Length)
    return @($base, $ext)
}

# Applies all active transformations to a single filename and returns
# the new filename (not full path).
function _Transform-FileName {
    param(
        [string]$FileName,
        [string]$Find,
        [string]$Replace,
        [string]$Prefix,
        [string]$Suffix,
        [string]$Case,
        [switch]$Trim
    )

    $newName = $FileName

    # 1) Regex replace (applied to full filename including extension)
    if ($Find) {
        try {
            $newName = $newName -replace $Find, $Replace
        } catch {
            Write-Warning "Regex error with -Find '$Find': $_"
        }
    }

    # 2) Case conversion (applied to full filename)
    if ($Case -eq 'Upper') {
        $newName = $newName.ToUpperInvariant()
    } elseif ($Case -eq 'Lower') {
        $newName = $newName.ToLowerInvariant()
    }

    # 3) Trim whitespace
    if ($Trim) {
        $newName = $newName.Trim()
    }

    # 4) Prefix
    if ($Prefix) {
        $newName = $Prefix + $newName
    }

    # 5) Suffix (before extension, or end if no extension)
    if ($Suffix) {
        $parts = _Split-Extension $newName
        $base = $parts[0]
        $ext = $parts[1]
        if ($ext) {
            $newName = $base + $Suffix + $ext
        } else {
            $newName = $newName + $Suffix
        }
    }

    return $newName
}
