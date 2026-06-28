# shim/shim.psm1 -- Executable proxy shim package.
#
# Auto-discovers tool configs from bin/*.yml, bin/*.yaml, bin/*.json
# and creates PowerShell proxy functions that call tools by their
# full absolute path so DLL dependencies resolve correctly.
#
# Public functions: Get-ShimConfig, Install-Shim, Uninstall-Shim,
# Register-ShimPackage.

. "$PSScriptRoot\helpers.ps1"
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\proxy.ps1"
. "$PSScriptRoot\register.ps1"

# -- Auto-discover and install proxies at module load time --
$script:_ShimConfigs = @()
try {
    $binRoot = _Get-BinRoot
    $configFiles = _Find-ShimConfigs -BinRoot $binRoot

    $script:_ShimConfigs = @(foreach ($file in $configFiles) {
        $cfg = _Read-ShimConfig -FilePath $file -BinRoot $binRoot
        if ($cfg) { $cfg }
    })

    $validConfigs = @($script:_ShimConfigs | Where-Object { $_.Valid })

    if ($validConfigs.Count -gt 0) {
        $tracker = @{}
        $null = _Install-LazyStubs -Configs $validConfigs -CollisionTracker $tracker
    }
} catch {
    Write-Warning "[shim] Failed to install lazy stubs: $_"
}

Export-ModuleMember -Function @(
    'Get-ShimConfig',
    'Install-Shim',
    'Uninstall-Shim',
    'Register-ShimPackage'
)
