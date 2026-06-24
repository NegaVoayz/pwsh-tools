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
            $ext = [System.IO.Path]::GetExtension($f.Name)
            if (-not (_Get-ImageFormat $ext) -and -not (_Is-WebPExtension $ext)) {
                Write-Warning "Unsupported format, skipping: $($f.FullName)"
                continue
            }
            $files += $f
        }
    }
    return $files
}

# Throws if the given format name does not support quality encoding (JPEG or WebP).
function _Assert-QualityFormat {
    param([string]$FormatName)
    if (_Is-WebPExtension $FormatName) { return }
    $fmt = _Get-ImageFormat $FormatName
    if ($fmt -and $fmt.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
        throw '-Quality can only be used with JPEG or WebP output format.'
    }
}

# Filters file list to quality-compatible formats (JPEG, WebP). Warns on skipped files.
function _Filter-QualityFiles {
    param([System.IO.FileInfo[]]$Files)
    $valid = @()
    foreach ($f in $Files) {
        $ext = $f.Extension
        if (_Is-WebPExtension $ext) {
            $valid += $f
            continue
        }
        $fmt = _Normalize-FormatName $ext
        $fmtObj = _Get-ImageFormat $fmt
        if ($fmtObj -and $fmtObj.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
            Write-Warning "Skipping '$($f.FullName)': -Quality only valid for JPEG or WebP output."
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

# -- Per-file processing wrappers (exported, usable from ForEach-Object -Parallel) --

# Processes a single file through the resize pipeline and saves the result.
# Returns a result object with InputPath, OutputPath, InputSize, OutputSize,
# or $null if the file was skipped.
function Invoke-ResizeFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int[]]$Size,
        [string]$OutputPath,
        [string]$Suffix,
        [switch]$Force,
        [switch]$InPlace,
        [string]$FileOutputPath
    )
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $inExt = [System.IO.Path]::GetExtension($file.FullName)
    if (-not (_Get-ImageFormat $inExt) -and -not (_Is-WebPExtension $inExt)) {
        Write-Warning "Unsupported format, skipping: $($file.FullName)"; return $null
    }

    $effectiveOutputPath = if ($FileOutputPath) { $FileOutputPath }
                           elseif ($InPlace) { $file.DirectoryName }
                           else { $OutputPath }
    $effectiveSuffix = if ($InPlace) { '' } else { $Suffix }
    $effectiveForce = $Force -or $InPlace

    $inSize = $file.Length
    $bitmap = $null; $image = $null
    try {
        $image = _Read-ImageFile $file.FullName
        $info = _Build-ResizeResult $image $file.FullName $Size
        $bitmap = $info.Bitmap
        $image.Dispose(); $image = $null
        $imgObj = _New-ImageObject -Bitmap $bitmap -SourcePath $file.FullName

        $r = _Save-ImageObject -ImageObject $imgObj `
            -OutputPath $effectiveOutputPath -Quality 0 -OutExt $info.OutExt `
            -Force:$effectiveForce -Suffix $effectiveSuffix
        if (-not $r) { $bitmap = $null; return $null }
        $bitmap = $null
        $outSize = (Get-Item -LiteralPath $r.OutputPath).Length
        if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
            Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
        }
        return [PSCustomObject]@{ InputPath = $r.InputPath; OutputPath = $r.OutputPath;
                                  InputSize = $inSize; OutputSize = $outSize }
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
        if ($image)  { $image.Dispose() }
    }
}

# Processes a single file through the compress pipeline and saves the result.
# Returns a result object with InputPath, OutputPath, InputSize, OutputSize,
# or $null if the file was skipped.
function Invoke-CompressFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Format,
        [int]$Quality,
        [string]$OutputPath,
        [string]$Suffix,
        [switch]$Force,
        [switch]$InPlace,
        [string]$FileOutputPath,
        [switch]$HasQuality
    )
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $inExt = [System.IO.Path]::GetExtension($file.FullName)
    if (-not (_Get-ImageFormat $inExt) -and -not (_Is-WebPExtension $inExt)) {
        Write-Warning "Unsupported format, skipping: $($file.FullName)"; return $null
    }

    $outFmt = if ($Format) { _Normalize-FormatName $Format }
              else { _Normalize-FormatName $inExt }
    if ($HasQuality) {
        try { _Assert-QualityFormat $outFmt } catch {
            Write-Warning "Skipping '$($file.FullName)': $_"; return $null
        }
    }

    $effectiveOutputPath = if ($FileOutputPath) { $FileOutputPath }
                           elseif ($InPlace) { $file.DirectoryName }
                           else { $OutputPath }
    $effectiveSuffix = if ($InPlace) { '' } else { $Suffix }
    $effectiveForce = $Force -or $InPlace
    $quality = if ($HasQuality) { $Quality } else { 0 }

    $inSize = $file.Length
    $bitmap = $null; $image = $null
    try {
        $image = _Read-ImageFile $file.FullName
        $info = _Build-CompressResult $image $file.FullName $Format
        $bitmap = $info.Bitmap
        $image.Dispose(); $image = $null
        $imgObj = _New-ImageObject -Bitmap $bitmap -SourcePath $file.FullName
        if ($Format) { $imgObj.Format = $outFmt }

        $r = _Save-ImageObject -ImageObject $imgObj `
            -OutputPath $effectiveOutputPath -Quality $quality `
            -OutExt $info.OutExt -Force:$effectiveForce -Suffix $effectiveSuffix
        if (-not $r) { $bitmap = $null; return $null }
        $bitmap = $null
        $outSize = (Get-Item -LiteralPath $r.OutputPath).Length
        if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
            Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
        }
        return [PSCustomObject]@{ InputPath = $r.InputPath; OutputPath = $r.OutputPath;
                                  InputSize = $inSize; OutputSize = $outSize }
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
        if ($image)  { $image.Dispose() }
    }
}

