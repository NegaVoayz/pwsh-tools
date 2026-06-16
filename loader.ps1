# loader.ps1 - Scans lib\*\export.psm1 and imports each package.
# Called from profile.ps1 on every shell start.

$libPath = Join-Path $PSScriptRoot 'lib'

if (-not (Test-Path $libPath)) {
    Write-Warning "[pwsh-tools] lib\ directory not found: $libPath"
    return
}

$exports = @(Get-ChildItem -Path $libPath -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "$($_.Name).psm1" } |
    Where-Object { Test-Path $_ } |
    Sort-Object)

if ($exports.Count -eq 0) {
    return
}

foreach ($exportPath in $exports) {
    $packageName = Split-Path (Split-Path $exportPath -Parent) -Leaf
    try {
        Import-Module -Name $exportPath -Force -ErrorAction Stop
        Write-Verbose "[pwsh-tools] Loaded package: $packageName" -Verbose:$false
    } catch {
        Write-Warning "[pwsh-tools] Failed to load package '$packageName': $_"
    }
}
