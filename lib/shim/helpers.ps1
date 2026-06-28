# shim/helpers.ps1 -- Internal utilities for the shim package.
#
# Private functions: _Get-BinRoot, _Unquote-YamlValue,
# _Test-ConfigNameCollision, _Strip-ToolExtension.
#
# Dot-sourced by shim.psm1. Not exported.

function _Get-BinRoot {
    # Returns the absolute path to the bin/ directory (repo root / bin).
    # $PSScriptRoot is lib/shim/ -- go up two levels, then into bin/.
    $binPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'bin'
    return (Resolve-Path $binPath -ErrorAction SilentlyContinue).Path ?? $binPath
}

function _Unquote-YamlValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Value
    )

    # Strips matching surrounding single or double quotes from a YAML scalar.
    # Returns the inner content unchanged if the value is not quoted.

    $trimmed = $Value.Trim()

    if ($trimmed.Length -ge 2) {
        $first = $trimmed[0]
        $last  = $trimmed[$trimmed.Length - 1]

        if (($first -eq '"' -and $last -eq '"') -or
            ($first -eq "'" -and $last -eq "'")) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }

    return $Value
}

function _Test-ConfigNameCollision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Existing,

        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$SourceFile
    )

    # Checks whether a tool name is already registered and warns about
    # collisions. The last config loaded wins (deterministic alphabetically).

    if ($Existing.ContainsKey($ToolName)) {
        $previous = $Existing[$ToolName]
        Write-Warning "[shim] '$ToolName' already registered by '$previous'; overwritten by '$SourceFile'"
    }

    $Existing[$ToolName] = $SourceFile
}

function _Strip-ToolExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$FileName
    )

    # Returns the tool base name without its extension.
    # "exiftool.exe" -> "exiftool", "ffprobe.exe" -> "ffprobe"

    return [System.IO.Path]::GetFileNameWithoutExtension($FileName)
}
