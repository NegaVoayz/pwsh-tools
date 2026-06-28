# shim/proxy.ps1 -- Proxy function generation and lifecycle.
#
# Private functions: _New-ShimProxy, _Install-ShimProxies,
# _Uninstall-ShimProxies, _New-LazyStub, _Install-LazyStubs.
#
# Public functions (exported): Install-Shim, Uninstall-Shim, Get-ShimConfig.
#
# Dot-sourced by shim.psm1 (after helpers.ps1 and config.ps1).

$script:_ProxyTemplate = @'
<#
.SYNOPSIS
    Shim for {{ToolPath}} ({{PackageName}} v{{Version}}).
.DESCRIPTION
    Runs {{ToolPath}} with its directory naturally discovered by Windows
    via the full path, so DLL dependencies resolve. All arguments are
    forwarded directly to the underlying executable.

    Pipe input (stdin) is forwarded via $input.
    {{DescriptionDetail}}
#>
$input | & "{{ToolPath}}" @args
'@

function _New-ShimProxy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$ToolPath,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [string]$Version = '',

        [string]$Description = ''
    )

    # Generates a proxy function scriptblock for a single tool.
    # Returns a [scriptblock] ready to install into global scope.

    $descDetail = if ($Description) {
        "`n    Package: $Description"
    } else { '' }

    $body = $script:_ProxyTemplate.
        Replace('{{ToolPath}}', $ToolPath).
        Replace('{{PackageName}}', $PackageName).
        Replace('{{Version}}', $Version).
        Replace('{{DescriptionDetail}}', $descDetail)

    return [scriptblock]::Create($body)
}

function _Install-ShimProxies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Configs,

        [hashtable]$CollisionTracker = @{},

        [switch]$Force
    )

    # Generates and installs proxy functions into the global scope for
    # each valid config. Tracks name collisions and warns (unless -Force).

    $installed = @()

    foreach ($config in $Configs) {
        if (-not $config.Valid) { continue }

        foreach ($tool in $config.Tools) {
            $toolName   = _Strip-ToolExtension $tool
            $toolPath   = Join-Path $config.Path $tool

            if (-not $Force) {
                _Test-ConfigNameCollision -Existing $CollisionTracker `
                    -ToolName $toolName -SourceFile $config.SourceFile
            }

            $sb = _New-ShimProxy -ToolName $toolName -ToolPath $toolPath `
                -PackageName $config.Name -Version $config.Version `
                -Description $config.Description

            Set-Item -Path "function:global:$toolName" -Value $sb -Force
            Write-Verbose "[shim] Installed proxy: $toolName -> $toolPath"
            $installed += [PSCustomObject]@{ Name = $toolName; Path = $toolPath; Package = $config.Name }
        }
    }

    return $installed
}

function _Uninstall-ShimProxies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    # Removes all proxy functions associated with a single config from global scope.
    # Returns the list of removed function names.

    $removed = @()

    foreach ($tool in $config.Tools) {
        $toolName = _Strip-ToolExtension $tool
        try {
            Remove-Item -Path "function:global:$toolName" -Force -ErrorAction Stop
            $removed += $toolName
        } catch {
            Write-Verbose "[shim] No proxy to remove for '$toolName': not installed"
        }
    }

    return $removed
}

function _New-LazyStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    # Generates a lightweight stub function that resolves its package on
    # first use. The stub calls Install-Shim to generate the real proxy
    # (which replaces the stub), then re-invokes with the original args.
    #
    # Uses .GetNewClosure() to capture the parameter values into the
    # returned scriptblock without retaining other scope variables.

    return {
        # Lazy-load: resolve this package, replacing all its stubs with
        # real proxies. Install-Shim is a public exported function.
        Install-Shim -Name $PackageName -Force

        # Now re-invoke with the newly-installed real proxy
        & $ToolName @args
    }.GetNewClosure()
}

function _Install-LazyStubs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Configs,

        [hashtable]$CollisionTracker = @{}
    )

    # Installs lightweight lazy-load stubs into the global scope for each
    # tool in each valid config. Real proxies are generated on first use.

    $installed = @()

    foreach ($config in $Configs) {
        if (-not $config.Valid) { continue }

        foreach ($tool in $config.Tools) {
            $toolName    = _Strip-ToolExtension $tool
            $packageName = $config.Name

            _Test-ConfigNameCollision -Existing $CollisionTracker `
                -ToolName $toolName -SourceFile $config.SourceFile

            $sb = _New-LazyStub -ToolName $toolName -PackageName $packageName
            Set-Item -Path "function:global:$toolName" -Value $sb -Force
            Write-Verbose "[shim] Lazy stub: $toolName (package: $packageName)"
            $installed += [PSCustomObject]@{ Name = $toolName; Package = $packageName }
        }
    }

    return $installed
}

# -- Public functions (exported) --

function Get-ShimConfig {
    [CmdletBinding()]
    param(
        [switch]$Raw
    )

<#
.SYNOPSIS
    Lists all discovered shim configurations.
.DESCRIPTION
    Displays registered tool packages from bin/*.yml, bin/*.yaml, and
    bin/*.json config files. Shows the package name, version, tool count,
    resolved path, and validity status.

    Use -Raw to return the raw config objects for scripting.
.EXAMPLE
    Get-ShimConfig
.EXAMPLE
    Get-ShimConfig -Raw | Where-Object { -not $_.Valid }
#>

    $configs = @($script:_ShimConfigs)

    if ($Raw) {
        return $configs
    }

    if ($configs.Count -eq 0) {
        Write-Host "  [shim] No tool configs found in bin/." -ForegroundColor DarkGray
        Write-Host "  Place a .yml config file in bin/ to register tools." -ForegroundColor DarkGray
        return
    }

    $configs | Format-Table -Property @(
        @{ Label = 'Name';    Expression = { $_.Name };           Width = 16 }
        @{ Label = 'Version'; Expression = { $_.Version };        Width = 10 }
        @{ Label = 'Tools';   Expression = { $_.Tools.Count };    Width = 7 }
        @{ Label = 'Valid';   Expression = { $_.Valid };          Width = 7 }
        @{ Label = 'Path';    Expression = { $_.Path };           Width = 50 }
    ) | Out-String | Write-Host
}

function Install-Shim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$Force
    )

<#
.SYNOPSIS
    Installs proxy functions from shim configs.
.DESCRIPTION
    Re-discovers config files in bin/ and installs (or re-installs)
    proxy functions into the global scope. Use after adding or editing
    a config file to pick up changes without restarting the shell.

    With -Name, installs only proxies for the named package.
    With -Force, overwrites existing functions without collision warnings.
.EXAMPLE
    Install-Shim
.EXAMPLE
    Install-Shim -Name ffmpeg -Force
#>

    $binRoot = _Get-BinRoot
    $files = _Find-ShimConfigs -BinRoot $binRoot

    if ($files.Count -eq 0) {
        Write-Host "  [shim] No config files found in bin/." -ForegroundColor DarkGray
        return
    }

    $configs = @(foreach ($file in $files) {
        $cfg = _Read-ShimConfig -FilePath $file -BinRoot $binRoot
        if ($cfg) { $cfg }
    })

    $targetConfigs = if ($Name) {
        @($configs | Where-Object { $_.Name -eq $Name })
    } else {
        @($configs | Where-Object { $_.Valid })
    }

    if ($targetConfigs.Count -eq 0) {
        if ($Name) {
            Write-Warning "[shim] Package '$Name' not found."
        } else {
            Write-Host "  [shim] No valid configs found." -ForegroundColor DarkGray
        }
        return
    }

    if ($PSCmdlet.ShouldProcess("$($targetConfigs.Count) package(s)", "Install proxy functions")) {
        $tracker = @{}
        $installed = _Install-ShimProxies -Configs $targetConfigs -CollisionTracker $tracker -Force:$Force
        Write-Host "  [shim] Installed $($installed.Count) proxy function(s)." -ForegroundColor Green
    }

    # Refresh the stored config list
    $script:_ShimConfigs = $configs
}

function Uninstall-Shim {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

<#
.SYNOPSIS
    Removes proxy functions for a shim package.
.DESCRIPTION
    Removes all generated proxy functions for the named package from
    the global scope. The config file is not deleted.
.EXAMPLE
    Uninstall-Shim -Name exiftool
#>

    $config = @($script:_ShimConfigs | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1

    if ($null -eq $config) {
        Write-Warning "[shim] Package '$Name' not found."
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Remove proxy functions")) {
        $removed = _Uninstall-ShimProxies -Config $config
        Write-Host "  [shim] Removed $($removed.Count) proxy function(s) for '$Name'." -ForegroundColor Green
    }

    # Refresh the stored config list
    $binRoot = _Get-BinRoot
    $files = _Find-ShimConfigs -BinRoot $binRoot
    $script:_ShimConfigs = @(foreach ($file in $files) {
        $cfg = _Read-ShimConfig -FilePath $file -BinRoot $binRoot
        if ($cfg) { $cfg }
    })
}
