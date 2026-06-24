# helpers.ps1 -- Internal utilities for image loading, resizing, format mapping,
# and saving. Never exported; dot-sourced by Img-Convert.psm1.

# -- ImageSharp assembly detection (WebP support) --
# WebP requires PowerShell 7+ (Core) because ImageSharp targets modern .NET.
# In Windows PowerShell 5.1 (Desktop), WebP is always disabled.
$script:_ImageSharpAvailable = $false
if ($PSVersionTable.PSEdition -eq 'Core') {
    try {
        $dllDirs = @($PSScriptRoot, (Join-Path $PSScriptRoot 'deps'))
        $imageSharpDll = $null
        foreach ($dir in $dllDirs) {
            $candidate = Join-Path $dir 'SixLabors.ImageSharp.dll'
            if (Test-Path $candidate -PathType Leaf) { $imageSharpDll = $candidate; break }
        }
        if ($imageSharpDll) {
            [System.Reflection.Assembly]::LoadFrom($imageSharpDll) | Out-Null
            $script:_ImageSharpAvailable = $true
        }
    } catch {
        $script:_ImageSharpAvailable = $false
    }
}

# Maps extension or format name to System.Drawing.Imaging.ImageFormat.
# Returns $null for unsupported formats.
function _Get-ImageFormat {
    param([string]$ExtOrName)
    $key = $ExtOrName.TrimStart('.').ToLowerInvariant()
    switch ($key) {
        'jpg'   { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        'jpeg'  { return [System.Drawing.Imaging.ImageFormat]::Jpeg }
        'png'   { return [System.Drawing.Imaging.ImageFormat]::Png }
        'gif'   { return [System.Drawing.Imaging.ImageFormat]::Gif }
        'bmp'   { return [System.Drawing.Imaging.ImageFormat]::Bmp }
        'tiff'  { return [System.Drawing.Imaging.ImageFormat]::Tiff }
        'ico'   { return [System.Drawing.Imaging.ImageFormat]::Icon }
        'wmf'   { return [System.Drawing.Imaging.ImageFormat]::Wmf }
        default { return $null }
    }
}

# Returns $true if the extension is .webp (case-insensitive, dot optional).
function _Is-WebPExtension {
    param([string]$Ext)
    return ($Ext.TrimStart('.').ToLowerInvariant() -eq 'webp')
}

# Normalizes a format string to ImageObject.Format canonical name.
# e.g., 'jpg', '.jpeg', 'Jpeg' all become 'Jpeg'.
function _Normalize-FormatName {
    param([string]$Name)
    if (_Is-WebPExtension $Name) { return 'Webp' }
    $fmt = _Get-ImageFormat $Name
    if (-not $fmt) { return $null }
    $map = @{
        ([System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) = 'Jpeg'
        ([System.Drawing.Imaging.ImageFormat]::Png.Guid)  = 'Png'
        ([System.Drawing.Imaging.ImageFormat]::Gif.Guid)  = 'Gif'
        ([System.Drawing.Imaging.ImageFormat]::Bmp.Guid)  = 'Bmp'
        ([System.Drawing.Imaging.ImageFormat]::Tiff.Guid) = 'Tiff'
        ([System.Drawing.Imaging.ImageFormat]::Icon.Guid) = 'Icon'
        ([System.Drawing.Imaging.ImageFormat]::Wmf.Guid)  = 'Wmf'
    }; return $map[$fmt.Guid]
}

# Returns the JPEG ImageCodecInfo for quality encoding, or $null.
function _Get-EncoderInfo {
    $encoders = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
    foreach ($enc in $encoders) {
        if ($enc.MimeType -eq 'image/jpeg') { return $enc }
    }
    return $null
}
# Resizes an Image to fit within size constraints (1 or 2 numbers).
# Never upscales. Returns new Bitmap (caller must dispose).
function _Resize-Bitmap {
    param(
        [System.Drawing.Image]$Image,
        [int[]]$Size
    )
    $width  = $Image.Width
    $height = $Image.Height

    if ($Size.Count -eq 1) {
        $longEdge = [Math]::Max($width, $height)
        if ($Size[0] -ge $longEdge) {
            $clone = New-Object System.Drawing.Bitmap($width, $height)
            $clone.SetResolution($Image.HorizontalResolution, $Image.VerticalResolution)
            $g = [System.Drawing.Graphics]::FromImage($clone)
            $g.DrawImage($Image, 0, 0); $g.Dispose()
            return $clone
        }
        $scale = $Size[0] / $longEdge
        $newW = [int]($width  * $scale)
        $newH = [int]($height * $scale)
    } else {
        $sorted = @($Size | Sort-Object -Descending)
        $bigger  = $sorted[0]
        $smaller = $sorted[1]
        if ($width -ge $height) {
            $maxW = $bigger; $maxH = $smaller
        } else {
            $maxW = $smaller; $maxH = $bigger
        }

        $scaleX = $maxW / $width
        $scaleY = $maxH / $height
        $scale  = [Math]::Min($scaleX, $scaleY)

        if ($scale -ge 1.0) {
            # Don't upscale — return a clone of the original
            $clone = New-Object System.Drawing.Bitmap($width, $height)
            $clone.SetResolution($Image.HorizontalResolution, $Image.VerticalResolution)
            $g = [System.Drawing.Graphics]::FromImage($clone)
            $g.DrawImage($Image, 0, 0)
            $g.Dispose()
            return $clone
        }

        $newW = [int]($width  * $scale)
        $newH = [int]($height * $scale)
    }

    $bitmap = New-Object System.Drawing.Bitmap($newW, $newH)
    $bitmap.SetResolution($Image.HorizontalResolution, $Image.VerticalResolution)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($Image, 0, 0, $newW, $newH)
    $graphics.Dispose()
    return $bitmap
}

# Wraps a Bitmap in an ImageObject for pipeline output.
function _New-ImageObject {
    param([System.Drawing.Bitmap]$Bitmap, [string]$SourcePath)
    if (_Is-WebPExtension ([System.IO.Path]::GetExtension($SourcePath))) {
        $fmtName = 'Webp'
    } else {
        $fmtName = _Normalize-FormatName $Bitmap.RawFormat.ToString()
        if (-not $fmtName) { $fmtName = 'Png' }
    }

    return [PSCustomObject]@{
        PSTypeName = 'ImageObject'
        Image      = $Bitmap
        SourcePath = $SourcePath
        Width      = $Bitmap.Width
        Height     = $Bitmap.Height
        Format     = $fmtName
    }
}

# Formats a byte count to a human-readable string.
function _Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes/1MB,1)) MB" }
    if ($Bytes -ge 1KB) { return "$([math]::Round($Bytes/1KB,1)) KB" }
    return "$Bytes B"
}

# Unified image file loader. Routes .webp files through ImageSharp; all other
# formats go through System.Drawing. Returns a System.Drawing.Image.
function _Read-ImageFile {
    param([string]$Path)
    if (_Is-WebPExtension ([System.IO.Path]::GetExtension($Path))) {
        return _WebPToBitmap $Path
    }
    return [System.Drawing.Image]::FromFile($Path)
}

# Decodes a .webp file to a System.Drawing.Bitmap via ImageSharp.
# Uses an in-memory PNG stream as the interchange format (lossless pixel copy).
function _WebPToBitmap {
    param([string]$Path)
    if (-not $script:_ImageSharpAvailable) {
        throw @"
WebP support requires PowerShell 7+ (pwsh.exe) and the SixLabors.ImageSharp assembly.
Place SixLabors.ImageSharp.dll in '$PSScriptRoot\deps\' or in the module directory.
Install via: dotnet add package SixLabors.ImageSharp
"@
    }
    $imageSharp = $null; $ms = $null
    try {
        $imageSharp = [SixLabors.ImageSharp.Image]::Load($Path)
        $ms = New-Object System.IO.MemoryStream
        $pngEncoder = New-Object SixLabors.ImageSharp.Formats.Png.PngEncoder
        $imageSharp.Save($ms, $pngEncoder)
        $ms.Position = 0
        $bitmap = New-Object System.Drawing.Bitmap($ms)
        return $bitmap
    } finally {
        if ($ms)         { $ms.Dispose() }
        if ($imageSharp) { $imageSharp.Dispose() }
    }
}

# Encodes a System.Drawing.Bitmap to a .webp file via ImageSharp.
# Uses an in-memory PNG stream as the interchange format.
function _BitmapToWebP {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutputPath,
        [int]$Quality
    )
    if (-not $script:_ImageSharpAvailable) {
        throw @"
WebP support requires PowerShell 7+ (pwsh.exe) and the SixLabors.ImageSharp assembly.
Place SixLabors.ImageSharp.dll in '$PSScriptRoot\deps\' or in the module directory.
Install via: dotnet add package SixLabors.ImageSharp
"@
    }
    $ms = $null; $imageSharp = $null; $fs = $null
    try {
        $ms = New-Object System.IO.MemoryStream
        $Bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $ms.Position = 0
        $imageSharp = [SixLabors.ImageSharp.Image]::Load($ms)
        $encoder = New-Object SixLabors.ImageSharp.Formats.Webp.WebpEncoder
        if ($Quality -gt 0) {
            $encoder.Quality = $Quality
        }
        $fs = [System.IO.File]::OpenWrite($OutputPath)
        $imageSharp.Save($fs, $encoder)
    } finally {
        if ($ms)         { $ms.Dispose() }
        if ($imageSharp) { $imageSharp.Dispose() }
        if ($fs)         { $fs.Dispose() }
    }
}

# Determines output file path from source path, output dir/file, extension, and suffix.
function _Resolve-OutputPath {
    param([string]$SourcePath, [string]$OutputPath, [string]$Ext, [string]$Suffix)

    $sourceDir  = Split-Path $SourcePath -Parent
    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)

    if ($OutputPath) {
        $normOut = $OutputPath.TrimEnd('\', '/')
        if ((Test-Path $normOut -PathType Container) -or
            (-not [System.IO.Path]::GetExtension($normOut) -and -not (Test-Path $normOut))) {
            return Join-Path $normOut ($sourceBase + $Suffix + $Ext)
        } else {
            $dir = Split-Path $normOut -Parent
            if (-not $dir) { $dir = '.' }
            return Join-Path $dir (Split-Path $normOut -Leaf)
        }
    }
    return Join-Path $sourceDir ($sourceBase + $Suffix + $Ext)
}

# Saves an ImageObject to disk with collision checks and JPEG quality encoding.
# Returns a result object or $null on skip/failure. Disposes .Image after save.
function _Save-ImageObject {
    param(
        [PSCustomObject]$ImageObject,
        [string]$OutputPath,
        [int]$Quality,
        [string]$OutExt,
        [switch]$Force,
        [string]$Suffix
    )

    $bitmap  = $ImageObject.Image
    $inPath  = $ImageObject.SourcePath

    $targetPath = _Resolve-OutputPath -SourcePath $inPath -OutputPath $OutputPath `
        -Ext $OutExt -Suffix $Suffix

    $targetFull = [System.IO.Path]::GetFullPath($targetPath)
    $inputFull  = [System.IO.Path]::GetFullPath($inPath)

    if ($targetFull -eq $inputFull) {
        if (-not $Force) {
            Write-Warning "Skipped: output same as input. Use -Force to overwrite: $inPath"
            return $null
        }
    }

    if ((Test-Path -LiteralPath $targetPath -ErrorAction SilentlyContinue) -and
        $targetFull -ne $inputFull) {
        if (-not $Force) {
            Write-Warning "Skipped: target already exists. Use -Force to overwrite: $targetPath"
            return $null
        }
    }

    $targetDir = Split-Path $targetPath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Force $targetDir | Out-Null
    }

    # WebP output: route through ImageSharp
    if (_Is-WebPExtension $OutExt) {
        try {
            _BitmapToWebP -Bitmap $bitmap -OutputPath $targetPath -Quality $Quality
        } catch {
            Write-Error "Failed to save '$targetPath': $_"
            return $null
        } finally {
            $bitmap.Dispose()
        }
        return [PSCustomObject]@{ InputPath = $inPath; OutputPath = $targetPath }
    }

    $imgFormat = _Get-ImageFormat $OutExt
    if (-not $imgFormat) {
        Write-Error "Unsupported output format: $OutExt"
        return $null
    }

    try {
        $isJpeg = ($imgFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid)
        if ($Quality -and $isJpeg) {
            $encoder = _Get-EncoderInfo
            $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                [System.Drawing.Imaging.Encoder]::Quality, $Quality
            )
            $bitmap.Save($targetPath, $encoder, $encParams)
            $encParams.Dispose()
        } else {
            $bitmap.Save($targetPath, $imgFormat)
        }
    } catch {
        Write-Error "Failed to save '$targetPath': $_"
        return $null
    } finally {
        $bitmap.Dispose()
    }
    return [PSCustomObject]@{ InputPath = $inPath; OutputPath = $targetPath }
}
