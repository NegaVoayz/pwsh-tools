# compress.ps1 -- Image compress and format conversion command.

<#
.SYNOPSIS
    Compress and/or convert image format.
.DESCRIPTION
    Sets JPEG compression quality and/or converts between image formats.
    Accepts file paths, FileInfo objects, or ImageObjects from the pipeline.
    Outputs an ImageObject (for further piping) or saves to disk when
    -OutputPath is specified.
.PARAMETER PathOrImage
    File path(s), FileInfo object(s), or ImageObject(s) from the pipeline.
    Wildcards supported for file paths.
.PARAMETER Quality
    JPEG/WebP compression quality from 0 (lowest) to 100 (highest).
    Only valid when output format is JPEG or WebP.
    Ignored (with an error) for other output formats.
.PARAMETER Format
    Output image format: jpg, jpeg, png, gif, bmp, tiff, ico, wmf, webp.
    Default: same format as the input image.
.PARAMETER OutputPath
    Directory or file path for output. When a directory, all output files
    are saved there. When a single file path, used as the exact output name.
    When omitted, an ImageObject is output to the pipeline.
.PARAMETER Suffix
    Explicit suffix appended to the base filename before the extension.
.PARAMETER EnableSuffix
    Append an auto-generated descriptive suffix (e.g. '_q80').
.PARAMETER Force
    Allow overwriting the original file.
.PARAMETER InPlace
    Overwrite the original file (shortcut for -Force with no suffix).
.EXAMPLE
    Compress-Image photo.jpg -Quality 50
    Compress-Image photo.png -Format jpg
    Compress-Image *.png -Format jpg -Quality 80 -OutputPath C:\out\
    Get-ChildItem *.jpg | Resize-Image -Size 800 | Compress-Image -Quality 70
#>
function Compress-Image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [object]$PathOrImage,

        [Parameter(Position=1)]
        [ValidateRange(0, 100)][int]$Quality,

        [Parameter(Position=2)]
        [ValidateSet('jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'ico', 'wmf', 'webp',
                     IgnoreCase)][string]$Format,

        [string]$OutputPath,
        [string]$Suffix,
        [switch]$EnableSuffix,
        [switch]$Force,
        [switch]$InPlace
    )

    begin {
        $results = @(); $count = 0; $saved = 0; $totalIn = 0L; $totalOut = 0L
        $fileOutputPath = $null
        $hasQuality = $PSBoundParameters.ContainsKey('Quality')

        if ($hasQuality -and $PSBoundParameters.ContainsKey('Format')) {
            _Assert-QualityFormat $Format
        }

        if ($EnableSuffix -and -not $PSBoundParameters.ContainsKey('Suffix')) {
            $Suffix = if ($hasQuality) { "_q$Quality" } else { '' }
        } elseif (-not $PSBoundParameters.ContainsKey('Suffix')) {
            $Suffix = ''
        }

        if ($OutputPath -and [System.IO.Path]::GetExtension($OutputPath)) {
            if (-not (Test-Path $OutputPath -PathType Container)) {
                $fileOutputPath = $OutputPath
            }
        }
    }

    process {
        # ImageObject from pipeline
        if ($PathOrImage -is [PSCustomObject] -and $PathOrImage.Image -and $PathOrImage.SourcePath) {
            $count++
            try {
                $outFmt = if ($Format) { _Normalize-FormatName $Format }
                          else { $PathOrImage.Format }
                if ($hasQuality) { _Assert-QualityFormat $outFmt }
                $imgObj = $PathOrImage
                if ($Format) { $imgObj.Format = $outFmt }
                if ($OutputPath -or $InPlace) {
                    $outDir = if ($InPlace) { Split-Path $imgObj.SourcePath -Parent } else { $OutputPath }
                    $sfx = if ($InPlace) { '' } else { $Suffix }
                    $ext = '.' + $outFmt.ToLowerInvariant()
                    if ($ext -eq '.jpeg') { $ext = '.jpg' }
                    if ($ext -eq '.icon') { $ext = '.ico' }
                    $q = if ($hasQuality) { $Quality } else { 0 }
                    $r = _Save-ImageObject -ImageObject $imgObj -OutputPath $outDir `
                        -Quality $q -OutExt $ext -Force:($Force -or $InPlace) -Suffix $sfx
                    if ($r) {
                        $results += $r; $saved++
                        $totalIn  += (Get-Item -LiteralPath $r.InputPath).Length
                        $totalOut += (Get-Item -LiteralPath $r.OutputPath).Length
                        if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
                            Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    Write-Host "  $($imgObj.SourcePath) -> $($imgObj.Format) (pipeline)"
                    $imgObj
                }
            } catch {
                Write-Error "Failed to process '$($PathOrImage.SourcePath)': $_"
            }
        } else {
            $path = if ($PathOrImage -is [System.IO.FileInfo]) { $PathOrImage.FullName }
                    else { [string]$PathOrImage }
            $files = _Get-FileList @($path)
            foreach ($file in $files) {
                $count++
                if ($fileOutputPath -and $count -gt 1) {
                    throw "Cannot use a file path for -OutputPath with multiple input paths."
                }

                $inExt = [System.IO.Path]::GetExtension($file.FullName)
                if (-not (_Get-ImageFormat $inExt) -and -not (_Is-WebPExtension $inExt)) {
                    Write-Warning "Unsupported format, skipping: $($file.FullName)"; continue
                }

                $outFmt = if ($Format) { _Normalize-FormatName $Format }
                          else { _Normalize-FormatName $inExt }
                if ($hasQuality) {
                    try {
                        _Assert-QualityFormat $outFmt
                    } catch {
                        Write-Warning "Skipping '$($file.FullName)': $_"
                        continue
                    }
                }

                $effectiveOutputPath = if ($fileOutputPath -and $count -eq 1) { $fileOutputPath }
                                      elseif ($InPlace) { $file.DirectoryName }
                                      else { $OutputPath }
                $effectiveSuffix = if ($InPlace) { '' } else { $Suffix }
                $effectiveForce = $Force -or $InPlace
                $quality = if ($hasQuality) { $Quality } else { 0 }

                $bitmap = $null; $image = $null
                try {
                    $image = _Read-ImageFile $file.FullName
                    $info = _Build-CompressResult $image $file.FullName $Format
                    $bitmap = $info.Bitmap
                    $image.Dispose(); $image = $null
                    $imgObj = _New-ImageObject -Bitmap $bitmap -SourcePath $file.FullName
                    if ($Format) { $imgObj.Format = $outFmt }

                    if ($effectiveOutputPath -or $InPlace) {
                        $r = _Save-ImageObject -ImageObject $imgObj `
                            -OutputPath $effectiveOutputPath -Quality $quality `
                            -OutExt $info.OutExt -Force:$effectiveForce -Suffix $effectiveSuffix
                        if ($r) {
                        $results += $r; $saved++
                        $totalIn  += (Get-Item -LiteralPath $r.InputPath).Length
                        $totalOut += (Get-Item -LiteralPath $r.OutputPath).Length
                        if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
                            Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
                        }
                    }; $bitmap = $null
                    } else {
                        Write-Host "  $($file.FullName) -> $($imgObj.Format) (pipeline)"
                        $imgObj; $bitmap = $null
                    }
                } catch {
                    Write-Error "Failed to process '$($file.FullName)': $_"
                } finally {
                    if ($bitmap) { $bitmap.Dispose() }
                    if ($image)  { $image.Dispose() }
                }
            }
        }
    }

    end {
        if ($saved -gt 0) {
            $inStr  = _Format-Size $totalIn
            $outStr = _Format-Size $totalOut
            if ($totalOut -lt $totalIn) {
                $pct = [math]::Round(100 * (1 - $totalOut / $totalIn), 1)
                Write-Host "  $saved file(s): $inStr -> $outStr ($pct% smaller)" -ForegroundColor DarkGray
            } else {
                $pct = [math]::Round(100 * ($totalOut / $totalIn - 1), 1)
                Write-Host "  $saved file(s): $inStr -> $outStr ($pct% larger)" -ForegroundColor DarkGray
            }
        } elseif ($count -gt 0 -and -not $OutputPath -and -not $InPlace) {
            Write-Host "  $count image(s) processed." -ForegroundColor DarkGray
        }
    }
}
