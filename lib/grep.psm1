# grep.psm1 - Pattern search in files and pipeline input.

<#
.SYNOPSIS
    Search files for a pattern.
.DESCRIPTION
    Wraps Select-String with familiar Unix grep flags.
    Reads from files or pipeline.
.PARAMETER Pattern
    The regex pattern to search for.
.PARAMETER Path
    File path(s) or wildcard. If omitted, reads from stdin.
.PARAMETER IgnoreCase
    Case-insensitive search (like grep -i).
.PARAMETER Invert
    Show lines that do NOT match (like grep -v).
.PARAMETER Recurse
    Recurse into subdirectories (like grep -r).
.PARAMETER LineNumber
    Show line numbers (like grep -n).
.PARAMETER FilesWithMatches
    Show only file names with matches (like grep -l).
.PARAMETER Count
    Show match count per file (like grep -c).
.EXAMPLE
    grep TODO *.ps1
    grep "function \w+" -Recurse lib\
    Get-Content log.txt | grep ERROR -IgnoreCase
    grep FIXME -Recurse -FilesWithMatches lib\
#>
function grep {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Pattern,
        [Parameter(Position=1, ParameterSetName='Path')]
        [string[]]$Path,
        [Parameter(ValueFromPipeline=$true, ParameterSetName='Input')]
        [string]$InputObject,
        [switch]$IgnoreCase,
        [switch]$Invert,
        [switch]$Recurse,
        [switch]$LineNumber,
        [switch]$FilesWithMatches,
        [switch]$Count
    )
    begin { $lines = @() }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Input') { $lines += $InputObject }
    }
    end {
        $selectArgs = @{
            Pattern       = $Pattern
            CaseSensitive = (-not $IgnoreCase)
            NotMatch      = $Invert
        }
        if ($FilesWithMatches) { $selectArgs.List = $true }

        if ($PSCmdlet.ParameterSetName -eq 'Input') {
            if (-not $lines) { return }
            $results = $lines | Select-String @selectArgs
            if ($Count) { Write-Host $results.Count }
            else {
                $results | ForEach-Object {
                    if ($LineNumber) { Write-Host "$($_.LineNumber): $($_.Line)" }
                    else { Write-Host $_.Line }
                }
            }
            return
        }
        if (-not $Path) { return }
        if ($Recurse) {
            $files = @(foreach ($p in $Path) { Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue })
            if (-not $files) { return }
            $Path = $files | ForEach-Object { $_.FullName }
        }
        if ($Count) {
            foreach ($p in $Path) {
                if (-not (Test-Path $p -PathType Leaf)) { continue }
                $c = @(Select-String @selectArgs -Path $p).Count
                if ($c -gt 0) { Write-Host "$c $p" }
            }
        } else {
            $results = Select-String @selectArgs -Path $Path
            $results | ForEach-Object {
                if ($FilesWithMatches) { Write-Host $_.Path }
                elseif ($LineNumber) { Write-Host "$($_.Filename):$($_.LineNumber): $($_.Line)" }
                else { Write-Host "$($_.Filename): $($_.Line)" }
            }
        }
    }
}

Export-ModuleMember -Function @('grep')
