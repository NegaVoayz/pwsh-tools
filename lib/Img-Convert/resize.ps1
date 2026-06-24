# resize.ps1 -- Image resize command.

<#
.SYNOPSIS
    Resize images by constraining pixel dimensions.
.DESCRIPTION
    Resizes images by limiting the longest edge (1 number) or fitting
    within a bounding box (2 numbers). Accepts file paths, FileInfo objects,
    or ImageObjects from the pipeline. Outputs an ImageObject (for further
    piping) or saves to disk when -OutputPath is specified.
.PARAMETER PathOrImage
    File path(s), FileInfo object(s), or ImageObject(s) from the pipeline.
    Wildcards supported for file paths.
.PARAMETER Size
    One or two pixel dimensions.
    One number: constrains the longest edge, maintaining aspect ratio.
    Two numbers: constrains as a bounding box. The larger number maps to the
    longer image edge. Image scales down to fit, preserving aspect ratio.
    If omitted, the image is not resized (passed through or saved as-is).
.PARAMETER OutputPath
    Directory or file path for output. When a directory, all output files
    are saved there. When a single file path, used as the exact output name.
    When omitted, an ImageObject is output to the pipeline.
.PARAMETER Suffix
    Explicit suffix appended to the base filename before the extension.
.PARAMETER EnableSuffix
    Append an auto-generated descriptive suffix (e.g. '_800px', '_1920x1080').
.PARAMETER Force
    Allow overwriting the original file.
.PARAMETER InPlace
    Overwrite the original file (shortcut for -Force with no suffix).
.EXAMPLE
    Resize-Image photo.jpg -Size 800
    Resize-Image photo.png -Size 1920,1080
    Resize-Image *.jpg -Size 800 -OutputPath C:\thumbnails\
    Get-ChildItem *.png | Resize-Image -Size 800 | Compress-Image -Quality 80 -Format jpg
#>
function Resize-Image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [object]$PathOrImage,

        [Parameter(Position=1)]
        [ValidateCount(1, 2)]
        [ValidateScript({ foreach ($n in $_) { if ($n -le 0) { throw 'Size values must be positive' } }; $true })]
        [int[]]$Size,

        [string]$OutputPath,
        [string]$Suffix,
        [switch]$EnableSuffix,
        [switch]$Force,
        [switch]$InPlace
    )

    begin {
        $results = @(); $count = 0; $saved = 0; $totalIn = 0L; $totalOut = 0L
        $fileOutputPath = $null

        if ($EnableSuffix -and -not $PSBoundParameters.ContainsKey('Suffix')) {
            if ($Size) {
                $Suffix = if ($Size.Count -eq 1) { "_$($Size[0])px" }
                          else { "_$($Size[0])x$($Size[1])" }
            } else { $Suffix = '' }
        } elseif (-not $PSBoundParameters.ContainsKey('Suffix')) {
            $Suffix = ''
        }

        # If OutputPath looks like a file (has extension), buffer first file
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
            $bitmap = $null
            try {
                if ($Size) {
                    $bitmap = _Resize-Bitmap -Image $PathOrImage.Image -Size $Size
                    $PathOrImage.Image.Dispose()
                    $imgObj = _New-ImageObject -Bitmap $bitmap -SourcePath $PathOrImage.SourcePath
                } else { $imgObj = $PathOrImage }
                if ($OutputPath -or $InPlace) {
                    $outDir = if ($InPlace) { Split-Path $imgObj.SourcePath -Parent } else { $OutputPath }
                    $sfx = if ($InPlace) { '' } else { $Suffix }
                    $ext = '.' + $imgObj.Format.ToLowerInvariant()
                    if ($ext -eq '.jpeg') { $ext = '.jpg' }
                    if ($ext -eq '.icon') { $ext = '.ico' }
                    $r = _Save-ImageObject -ImageObject $imgObj -OutputPath $outDir `
                        -Quality 0 -OutExt $ext -Force:($Force -or $InPlace) -Suffix $sfx
                    if ($r) {
                        $results += $r; $saved++
                        $totalIn  += $imgObj.Width * $imgObj.Height * 4
                        $totalOut += (Get-Item -LiteralPath $r.OutputPath).Length
                        if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
                            Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
                        }
                    }; $bitmap = $null
                } else {
                    Write-Host "  $($imgObj.SourcePath) -> [$($imgObj.Width)x$($imgObj.Height)] (pipeline)"
                    $imgObj; $bitmap = $null
                }
            } catch {
                Write-Error "Failed to process '$($PathOrImage.SourcePath)': $_"
            } finally { if ($bitmap) { $bitmap.Dispose() } }
        } else {
            # File path or FileInfo — resolve and process immediately
            $path = if ($PathOrImage -is [System.IO.FileInfo]) { $PathOrImage.FullName }
                    else { [string]$PathOrImage }
            $files = _Get-FileList @($path)
            foreach ($file in $files) {
                $count++
                if ($fileOutputPath -and $count -gt 1) {
                    throw "Cannot use a file path for -OutputPath with multiple input paths."
                }
                $effectiveOutputPath = if ($fileOutputPath -and $count -eq 1) { $fileOutputPath }
                                      elseif ($InPlace) { $file.DirectoryName }
                                      else { $OutputPath }
                $effectiveSuffix = if ($InPlace) { '' } else { $Suffix }
                $effectiveForce = $Force -or $InPlace
                if ($effectiveOutputPath -and $fileOutputPath -and $PathOrImage -isnot [System.IO.FileInfo]) {
                    $effectiveOutputPath = $OutputPath
                }

                $bitmap = $null
                try {
                    $image = [System.Drawing.Image]::FromFile($file.FullName)
                    $info = _Build-ResizeResult $image $file.FullName $Size
                    $bitmap = $info.Bitmap
                    $image.Dispose(); $image = $null
                    $imgObj = _New-ImageObject -Bitmap $bitmap -SourcePath $file.FullName

                    if ($effectiveOutputPath -or $InPlace) {
                        $r = _Save-ImageObject -ImageObject $imgObj `
                            -OutputPath $effectiveOutputPath -Quality 0 -OutExt $info.OutExt `
                            -Force:$effectiveForce -Suffix $effectiveSuffix
                        if ($r) {
                            $results += $r; $saved++
                            $totalIn  += (Get-Item -LiteralPath $r.InputPath).Length
                            $totalOut += (Get-Item -LiteralPath $r.OutputPath).Length
                            if ($InPlace -and $r.OutputPath -ne $r.InputPath) {
                                Remove-Item -LiteralPath $r.InputPath -Force -ErrorAction SilentlyContinue
                            }
                        }; $bitmap = $null
                    } else {
                        Write-Host "  $($file.FullName) -> [$($imgObj.Width)x$($imgObj.Height)] (pipeline)"
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
