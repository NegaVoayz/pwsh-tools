# shim/register.ps1 -- Auto-discovery and config generation.
#
# Public function (exported): Register-ShimPackage.
#
# Dot-sourced by shim.psm1 (after helpers.ps1, config.ps1, proxy.ps1).

$script:_DefaultExcludePatterns = @(
    'unins*.exe',
    'uninstall.exe',
    'vcredist*.exe',
    'vc_redist*.exe',
    'setup.exe',
    'install.exe'
)

function _Discover-Executables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolDir,

        [string[]]$ExcludePattern,

        [switch]$Recurse
    )

    # Scans a tool directory and its immediate subdirectories (when -Recurse)
    # for executable files, filtering out helper utilities via exclude patterns.
    # Returns sorted array of file names (not full paths).

    $exes = @()
    $dirsToScan = @($ToolDir)

    if ($Recurse) {
        $dirsToScan += @(Get-ChildItem -Path $ToolDir -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    }

    foreach ($dir in $dirsToScan) {
        # -Include requires a wildcard in -Path to work (e.g., dir\*)
        $searchPath = Join-Path $dir '*'
        $files = @(Get-ChildItem -Path $searchPath -Include @('*.exe', '*.bat', '*.cmd') -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $excluded = $false
            foreach ($pattern in $ExcludePattern) {
                if ($file.Name -like $pattern) {
                    Write-Verbose "[shim] Excluded: $($file.Name) (matches '$pattern')"
                    $excluded = $true
                    break
                }
            }
            if (-not $excluded) {
                $exes += $file.Name
            }
        }
    }

    return @($exes | Sort-Object -Unique)
}

function _New-ShimConfigYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [string]$Description,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string[]]$Tools
    )

    # Generates the YAML content for a shim config file.

    $descLine = if ($Description) { "description: `"$Description`"" } else { '' }
    $verLine  = if ($Version)     { "version: `"$Version`"" }        else { '' }

    $yaml = @"
# $Name — $Description
name: $Name
$verLine
$descLine
path: $ConfigPath
tools:
"@

    foreach ($tool in $Tools) {
        $yaml += "`n  - $tool"
    }

    return $yaml + "`n"
}

function Register-ShimPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$Path,

        [string]$Version = '',

        [string]$Description = '',

        [string[]]$Exclude = @(),

        [switch]$NoDefaultExcludes,

        [switch]$Recurse,

        [switch]$PassThru
    )

<#
.SYNOPSIS
    Auto-discovers executables in a tool directory and registers them as a shim package.
.DESCRIPTION
    Scans the given tool directory (and its immediate subdirectories with -Recurse)
    for .exe, .bat, and .cmd files, generates a YAML config in bin/<Name>.yml, and
    automatically installs proxy functions.

    By default, common helper executables are excluded:
    unins*.exe, uninstall.exe, vcredist*.exe, vc_redist*.exe, setup.exe, install.exe.
    Use -NoDefaultExcludes to include them, or -Exclude to add additional patterns.

    Use -PassThru to preview what would be registered without writing the config file.
.PARAMETER Name
    Package name. The config is saved as bin/<Name>.yml.
.PARAMETER Path
    Path to the tool directory. Relative paths resolve from bin/.
    Absolute paths are used as-is.
.PARAMETER Version
    Optional version string for the config.
.PARAMETER Description
    Optional description for the config.
.PARAMETER Exclude
    Additional wildcard patterns to exclude (e.g. '*_debug.exe').
    Supports -like wildcards (* and ?).
.PARAMETER NoDefaultExcludes
    Skip the default exclude patterns. All executables are included.
.PARAMETER Recurse
    Also scan immediate subdirectories (e.g., a bin/ subdirectory within the tool).
.PARAMETER PassThru
    Preview the discovered tools without writing a config file or installing proxies.
.EXAMPLE
    Register-ShimPackage -Name ffmpeg -Path ffmpeg-7.1-full_build -Version "7.1"
.EXAMPLE
    Register-ShimPackage -Name mytool -Path "C:\Program Files\MyTool" -PassThru
#>

    $binRoot = _Get-BinRoot

    # Resolve the tool directory
    $toolDir = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $binRoot $Path
    }

    if (-not (Test-Path $toolDir -PathType Container)) {
        Write-Error "[shim] Tool directory not found: '$toolDir'"
        return
    }

    # Build exclude list
    $excludePatterns = @($Exclude)
    if (-not $NoDefaultExcludes) {
        $excludePatterns += $script:_DefaultExcludePatterns
    }

    # Discover executables — try the main directory first, then auto-fall
    # back to a bin/ subdirectory if the root has no executables and we
    # aren't already recursing (common layout: ffmpeg-7.1/bin/ffmpeg.exe).
    $tools = _Discover-Executables -ToolDir $toolDir -ExcludePattern $excludePatterns -Recurse:$Recurse

    if ($tools.Count -eq 0 -and -not $Recurse) {
        $binSubDir = Join-Path $toolDir 'bin'
        if (Test-Path $binSubDir -PathType Container) {
            $tools = _Discover-Executables -ToolDir $binSubDir -ExcludePattern $excludePatterns
            if ($tools.Count -gt 0) {
                Write-Verbose "[shim] No executables in root; auto-detected bin/ subdirectory"
                $toolDir = $binSubDir
            }
        }
    }

    if ($tools.Count -eq 0) {
        Write-Warning "[shim] No executables found in '$toolDir'"
        return
    }

    # Determine the config path value (relative to bin/ if possible)
    $configPath = if ($toolDir.StartsWith($binRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $toolDir.Substring($binRoot.Length).TrimStart('\', '/')
    } else {
        $toolDir
    }

    # Generate YAML content
    $yamlContent = _New-ShimConfigYaml -Name $Name -Version $Version `
        -Description $Description -ConfigPath $configPath -Tools $tools

    $configFilePath = Join-Path $binRoot "$Name.yml"

    if ($PassThru) {
        Write-Host "`n  Package : $Name" -ForegroundColor Cyan
        Write-Host "  Path    : $configPath" -ForegroundColor Cyan
        Write-Host "  Tools   : $($tools.Count) found" -ForegroundColor Cyan
        Write-Host ""
        foreach ($tool in $tools) {
            $excludedMark = if ($tool -in $tools) { '  + ' } else { '  - ' }
            Write-Host "    $excludedMark$tool"
        }
        Write-Host ""
        Write-Host "  Config would be written to: $configFilePath" -ForegroundColor DarkGray
        Write-Host "  Run without -PassThru to create the config." -ForegroundColor DarkGray
        return
    }

    if ($PSCmdlet.ShouldProcess($configFilePath, "Create shim config for '$Name' with $($tools.Count) tool(s)")) {
        Set-Content -Path $configFilePath -Value $yamlContent -Encoding UTF8
        Write-Host "  [shim] Registered '$Name' with $($tools.Count) tool(s): $configFilePath" -ForegroundColor Green

        if ($VerbosePreference -eq 'Continue') {
            foreach ($tool in $tools) { Write-Host "    + $tool" -ForegroundColor DarkGray }
        }

        # Refresh config list and auto-install proxies
        _Refresh-ShimConfigs
        Install-Shim -Name $Name -Force
    }
}

function _Refresh-ShimConfigs {
    [CmdletBinding()]
    param()

    # Re-reads all config files and updates $script:_ShimConfigs.
    # Called after Register-ShimPackage writes a new config.

    $binRoot = _Get-BinRoot
    $files   = _Find-ShimConfigs -BinRoot $binRoot

    $script:_ShimConfigs = @(foreach ($file in $files) {
        $cfg = _Read-ShimConfig -FilePath $file -BinRoot $binRoot
        if ($cfg) { $cfg }
    })
}
