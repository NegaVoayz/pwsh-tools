# which.psm1 - Locate a command in PATH or PowerShell.

<#
.SYNOPSIS
    Show the full path of a command.
.DESCRIPTION
    Searches PATH for executables and also resolves PowerShell
    cmdlets, functions, and aliases.
.PARAMETER Name
    The command name to locate.
.PARAMETER All
    Show all matches (like which -a).
.EXAMPLE
    which git
    which python -All
#>
function which {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string]$Name,
        [switch]$All
    )
    process {
        $results = Get-Command $Name -All -ErrorAction SilentlyContinue
        if (-not $results) {
            $exts = ($env:PATHEXT -split ';') + ''
            foreach ($dir in ($env:PATH -split ';' | Where-Object { $_ })) {
                foreach ($ext in $exts) {
                    $candidate = Join-Path $dir ($Name + $ext)
                    if (Test-Path $candidate -PathType Leaf) {
                        Write-Host $candidate
                        if (-not $All) { return }
                    }
                }
            }
            return
        }
        if ($All) { $results | ForEach-Object { Write-Host $_.Source } }
        else      { Write-Host $results[0].Source }
    }
}
