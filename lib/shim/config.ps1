# shim/config.ps1 -- Config discovery, parsing, and validation.
#
# Private functions: _Find-ShimConfigs, _Parse-YamlSimple,
# _Parse-YamlConfig, _Parse-JsonConfig, _Validate-ShimConfig,
# _Read-ShimConfig.
#
# Dot-sourced by shim.psm1 (after helpers.ps1). Not exported.

function _Find-ShimConfigs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BinRoot
    )

    # Scans bin/ for *.yml, *.yaml, and *.json config files.
    # Returns full file paths sorted alphabetically (deterministic).

    if (-not (Test-Path $BinRoot)) { return @() }

    $files = @()
    foreach ($ext in @('*.yml', '*.yaml', '*.json')) {
        $files += @(Get-ChildItem -Path $BinRoot -Filter $ext -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    }

    return @($files | Sort-Object)
}

function _Parse-YamlSimple {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    # Minimal YAML subset parser.
    #
    # Handles exactly:
    #   key: value           (scalar -- quoted or unquoted)
    #   key:                 (list header)
    #     - item1            (list items)
    #     - item2
    #   # comment            (lines starting with optional whitespace then #)
    #
    # Limitations (use JSON for complex configs):
    #   - No nesting beyond one list level
    #   - No multi-line strings
    #   - No flow style ({}, [])
    #   - No anchors/aliases

    $result = @{}
    $currentListKey = $null
    $lines = $Content -split '\r?\n'

    foreach ($line in $lines) {
        $trimmed = $line.TrimEnd()

        # Skip empty lines and comment lines
        if ($trimmed -eq '' -or $trimmed -match '^\s*#') { continue }

        # List item: "  - value"
        if ($trimmed -match '^\s*-\s+(.+)$') {
            if ($null -eq $currentListKey) {
                Write-Warning "[shim] YAML list item without a list key: '$trimmed'"
                continue
            }
            $itemValue = _Unquote-YamlValue $Matches[1]
            $result[$currentListKey] += @($itemValue)
            continue
        }

        # Key: value or Key: (list header)
        if ($trimmed -match '^(\w+)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $rawValue = $Matches[2]

            if ($rawValue -eq '') {
                # List header -- subsequent list items belong to this key
                $currentListKey = $key
                $result[$key] = @()
            } else {
                # Scalar value
                $currentListKey = $null

                # Check if value is quoted before stripping inline comments
                $firstChar = $rawValue[0]
                if ($firstChar -eq '"' -or $firstChar -eq "'") {
                    # Quoted -- unquote, do NOT strip inline comments
                    $value = _Unquote-YamlValue $rawValue
                } else {
                    # Unquoted -- strip trailing inline comment (# preceded by whitespace)
                    $value = $rawValue -replace '\s+#.*$', ''
                    $value = $value.Trim()
                }
                $result[$key] = $value
            }
            continue
        }

        # Unknown line format
        Write-Warning "[shim] Skipping unrecognized YAML line: '$trimmed'"
    }

    return $result
}

function _Parse-YamlConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    # Reads a .yml/.yaml file and parses it via the minimal YAML parser.
    # Returns a hashtable of config keys, or $null on failure.

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content -or $content.Trim() -eq '') {
            Write-Warning "[shim] Config file is empty: '$FilePath'"
            return $null
        }
        return (_Parse-YamlSimple -Content $content)
    } catch {
        Write-Warning "[shim] Failed to read YAML config '$FilePath': $_"
        return $null
    }
}

function _Parse-JsonConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    # Reads a .json file and parses it with ConvertFrom-Json.
    # Returns a hashtable with lowercase keys (normalized to match YAML), or $null on failure.

    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content -or $content.Trim() -eq '') {
            Write-Warning "[shim] Config file is empty: '$FilePath'"
            return $null
        }
        $obj = $content | ConvertFrom-Json -ErrorAction Stop
        $result = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $result[$prop.Name.ToLower()] = $prop.Value
        }
        return $result
    } catch {
        Write-Warning "[shim] Failed to parse JSON config '$FilePath': $_"
        return $null
    }
}

function _Validate-ShimConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$BinRoot
    )

    # Validates required fields and resolves paths.
    # Returns $true if the config is usable, $false if it should be skipped.
    # Warnings are emitted for non-fatal issues (missing path, missing .exe).
    # Errors are emitted for fatal issues (missing required key).

    $valid = $true

    # Required: name
    if (-not $Config.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($Config['name'])) {
        Write-Error "[shim] '$SourceFile' is missing required key: 'name'"
        return $false
    }

    # Required: path
    if (-not $Config.ContainsKey('path') -or [string]::IsNullOrWhiteSpace($Config['path'])) {
        Write-Error "[shim] '$SourceFile' is missing required key: 'path'"
        return $false
    }

    # Required: tools (non-empty array)
    if (-not $Config.ContainsKey('tools')) {
        Write-Error "[shim] '$SourceFile' is missing required key: 'tools'"
        return $false
    }
    $tools = $Config['tools']
    if ($tools -isnot [array] -and $tools -isnot [System.Collections.ArrayList]) {
        Write-Error "[shim] '$SourceFile': 'tools' must be a list"
        return $false
    }
    if ($tools.Count -eq 0) {
        Write-Warning "[shim] '$SourceFile': 'tools' list is empty"
        return $false
    }

    # Resolve path: absolute stays absolute; relative resolves from $BinRoot
    $rawPath = $Config['path']
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($rawPath)) {
        $rawPath
    } else {
        Join-Path $BinRoot $rawPath
    }

    if (-not (Test-Path $resolvedPath -PathType Container)) {
        Write-Warning "[shim] Tool directory not found: '$resolvedPath' (from '$SourceFile')"
        $valid = $false
    }

    # Warn about missing executables (non-fatal -- tool might be installed later)
    foreach ($tool in $tools) {
        $toolPath = Join-Path $resolvedPath $tool
        if (-not (Test-Path $toolPath -PathType Leaf)) {
            Write-Warning "[shim] Tool not found: '$tool' in '$resolvedPath' (from '$SourceFile')"
        }
    }

    # Store resolved values on the config hashtable for later use
    $Config['_resolvedPath'] = $resolvedPath
    $Config['_sourceFile']   = $SourceFile
    $Config['_valid']        = $valid

    return $valid
}

function _Read-ShimConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BinRoot
    )

    # Top-level dispatcher: parse + validate a config file.
    # Returns a PSCustomObject with config properties, or $null on failure.

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $config = if ($ext -eq '.json') {
        _Parse-JsonConfig -FilePath $FilePath
    } else {
        _Parse-YamlConfig -FilePath $FilePath
    }

    if ($null -eq $config) { return $null }

    $isValid = _Validate-ShimConfig -Config $config -SourceFile $FilePath -BinRoot $BinRoot

    # Build a clean PSCustomObject for downstream consumers
    return [PSCustomObject]@{
        Name        = ($config['name'] ?? '')
        Version     = ($config['version'] ?? '')
        Description = ($config['description'] ?? '')
        Path        = ($config['_resolvedPath'] ?? '')
        Tools       = @($config['tools'] ?? @())
        SourceFile  = $FilePath
        Valid       = $isValid
    }
}
