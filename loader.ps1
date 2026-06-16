# loader.ps1 - Scans lib\ for .psm1 files and imports them.
# Called from profile.ps1 on every shell start.

$libPath = Join-Path $PSScriptRoot 'lib'

if (-not (Test-Path $libPath)) {
    Write-Warning "[pwsh-tools] lib\ directory not found: $libPath"
    return
}

$moduleFiles = Get-ChildItem -Path $libPath -Filter '*.psm1' -ErrorAction SilentlyContinue

if (-not $moduleFiles -or $moduleFiles.Count -eq 0) {
    # Empty lib directory is not an error — just means no modules installed yet
    return
}

foreach ($moduleFile in $moduleFiles) {
    $moduleName = $moduleFile.BaseName
    try {
        Import-Module -Name $moduleFile.FullName -Force -ErrorAction Stop
        Write-Verbose "[pwsh-tools] Loaded module: $moduleName" -Verbose:$false
    } catch {
        Write-Warning "[pwsh-tools] Failed to load module '$moduleName': $_"
    }
}
