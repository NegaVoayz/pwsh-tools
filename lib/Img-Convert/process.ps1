# process.ps1 -- Shared pipeline file-processing helpers and transform functions.
# Never exported; dot-sourced by Img-Convert.psm1.

# Clones an Image to a new Bitmap with matching resolution.
function _Clone-Bitmap {
    param([System.Drawing.Image]$Image)
    $b = New-Object System.Drawing.Bitmap($Image)
    $b.SetResolution($Image.HorizontalResolution, $Image.VerticalResolution)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.DrawImage($Image, 0, 0); $g.Dispose()
    return $b
}

# Resolves wildcards/literal paths to a flat list of supported image files.
function _Get-FileList {
    param([string[]]$Items)
    $files = @()
    foreach ($item in $Items) {
        $found = @(Get-ChildItem -LiteralPath $item -File -ErrorAction SilentlyContinue)
        if (-not $found) {
            $found = @(Get-ChildItem -Path $item -File -ErrorAction SilentlyContinue)
        }
        if (-not $found) { Write-Warning "No files matched: $item"; continue }
        foreach ($f in $found) {
            if (-not (_Get-ImageFormat ([System.IO.Path]::GetExtension($f.Name)))) {
                Write-Warning "Unsupported format, skipping: $($f.FullName)"
                continue
            }
            $files += $f
        }
    }
    return $files
}

# Throws if the given format name does not resolve to JPEG.
function _Assert-JpegFormat {
    param([string]$FormatName)
    $fmt = _Get-ImageFormat $FormatName
    if ($fmt -and $fmt.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
        throw '-Quality can only be used with JPEG output format.'
    }
}

# Filters file list to only JPEG-compatible formats. Warns on skipped files.
function _Filter-QualityFiles {
    param([System.IO.FileInfo[]]$Files)
    $valid = @()
    foreach ($f in $Files) {
        $fmt = _Normalize-FormatName $f.Extension
        $fmtObj = _Get-ImageFormat $fmt
        if ($fmtObj -and $fmtObj.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
            Write-Warning "Skipping '$($f.FullName)': -Quality only valid for JPEG output."
        } else { $valid += $f }
    }
    return $valid
}

# Transform: resize (or clone) an image for Resize-Image. Returns hashtable
# with Bitmap, OutExt (e.g. '.jpg'), and OutFormat (e.g. 'Jpeg').
function _Build-ResizeResult {
    param($Image, $Path, $Size)
    if ($Size) { $b = _Resize-Bitmap -Image $Image -Size $Size }
    else       { $b = _Clone-Bitmap $Image }
    $fmt = _Normalize-FormatName ([System.IO.Path]::GetExtension($Path))
    $ext = '.' + $fmt.ToLowerInvariant()
    if ($ext -eq '.jpeg') { $ext = '.jpg' }
    if ($ext -eq '.icon') { $ext = '.ico' }
    return @{ Bitmap = $b; OutExt = $ext; OutFormat = $fmt }
}

# Transform: clone + optionally override format for Compress-Image.
function _Build-CompressResult {
    param($Image, $Path, $Format)
    $b = _Clone-Bitmap $Image
    $fmt = if ($Format) { _Normalize-FormatName $Format }
           else { _Normalize-FormatName ([System.IO.Path]::GetExtension($Path)) }
    $ext = '.' + $fmt.ToLowerInvariant()
    if ($ext -eq '.jpeg') { $ext = '.jpg' }
    if ($ext -eq '.icon') { $ext = '.ico' }
    return @{ Bitmap = $b; OutExt = $ext; OutFormat = $fmt }
}

