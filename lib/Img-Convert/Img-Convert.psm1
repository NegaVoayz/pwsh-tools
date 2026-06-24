# Img-Convert/Img-Convert.psm1 -- Image conversion and resizing package entry point.

Add-Type -AssemblyName System.Drawing

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\process.ps1"
. "$PSScriptRoot\resize.ps1"
. "$PSScriptRoot\compress.ps1"

Export-ModuleMember -Function @('Resize-Image', 'Compress-Image')
