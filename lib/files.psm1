# files.psm1 - Filesystem operations (touch, ln).

<#
.SYNOPSIS
    Create an empty file or update its last-write timestamp.
.DESCRIPTION
    Without -Time, creates the file if missing and bumps LastWriteTime
    to now. With -Time, sets an explicit timestamp.
.PARAMETER Path
    One or more file paths. Accepts wildcards.
.PARAMETER Time
    Explicit timestamp to set. Defaults to now.
.PARAMETER NoCreate
    Do not create the file if it does not exist (like touch -c).
.EXAMPLE
    touch foo.txt
    touch bar.txt -Time (Get-Date "2025-01-01")
    touch *.cs -NoCreate
#>
function touch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string[]]$Path,
        [datetime]$Time,
        [switch]$NoCreate
    )
    process {
        foreach ($p in $Path) {
            $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
            if ($resolved) {
                foreach ($r in $resolved) {
                    if ($PSCmdlet.ShouldProcess($r.Path, "touch")) {
                        $(Get-Item $r.Path).LastWriteTime = if ($Time) { $Time } else { Get-Date }
                    }
                }
            } elseif (-not $NoCreate) {
                if ($PSCmdlet.ShouldProcess($p, "touch (create)")) {
                    $dir = Split-Path $p -Parent
                    if ($dir -and -not (Test-Path $dir)) {
                        New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    }
                    $file = New-Item -ItemType File -Path $p -Force
                    if ($Time) { $file.LastWriteTime = $Time }
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Create a symbolic link.
.DESCRIPTION
    Mirrors Unix `ln -s`. Requires Administrator or Developer Mode.
.PARAMETER Target
    The existing path the link should point to.
.PARAMETER Link
    The path of the new symlink to create.
.EXAMPLE
    ln -Target C:\tools\script.ps1 -Link C:\bin\script.ps1
#>
function ln {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Target,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$Link
    )
    $Target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target)
    if (Test-Path $Link -PathType Container) {
        $Link = Join-Path $Link (Split-Path $Target -Leaf)
    }
    if ($PSCmdlet.ShouldProcess($Link, "ln -s $Target")) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-Host "  $Link -> $Target"
    }
}

Export-ModuleMember -Function @('touch', 'ln')
