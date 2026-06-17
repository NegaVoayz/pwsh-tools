# navigate.ps1 — Directory navigation commands (package-private).

<#
.SYNOPSIS
    Creates a directory and enters it.
.DESCRIPTION
    Creates a directory (recursively, like 'mkdir -p') and immediately
    changes the current location into it. Returns the created directory.
.PARAMETER Path
    The directory path to create and enter.
.EXAMPLE
    mkcd C:\projects\new-app
    mkcd "C:\path with spaces\subdir"
    mkcd ../relative/deep/nested -WhatIf
#>
function mkcd {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path
    )

    if ($PSCmdlet.ShouldProcess($Path, "Create and enter directory")) {
        $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
        $resolved = Resolve-Path $Path -ErrorAction Stop
        Set-Location -LiteralPath $resolved.Path
        Write-Verbose "Created and entered: $($resolved.Path)"
    }
}
