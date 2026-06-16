# wc.psm1 - Count lines, words, and characters.

<#
.SYNOPSIS
    Count lines, words, and characters.
.DESCRIPTION
    Reads from files or pipeline.
.PARAMETER Path
    File path(s). If omitted, reads from stdin.
.PARAMETER Lines
    Count lines only (like wc -l).
.PARAMETER Words
    Count words only (like wc -w).
.PARAMETER Chars
    Count characters only (like wc -c).
.EXAMPLE
    wc script.ps1
    cat script.ps1 | wc -Lines
    wc *.ps1 -Words
#>
function wc {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Position=0, ParameterSetName='Path')]
        [string[]]$Path,
        [Parameter(ValueFromPipeline=$true, ParameterSetName='Input')]
        [object]$InputObject,
        [switch]$Lines,
        [switch]$Words,
        [switch]$Chars
    )
    begin { $content = @() }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($p in $Path) {
                $c = Get-Content $p -Raw
                if ($Lines)      { $r = ((Get-Content $p | Measure-Object -Line).Lines) }
                elseif ($Words)  { $r = (($c -split '\s+' | Where-Object { $_ }).Count) }
                elseif ($Chars)  { $r = $c.Length }
                else {
                    $l = (Get-Content $p | Measure-Object -Line).Lines
                    $w = (($c -split '\s+' | Where-Object { $_ }).Count)
                    $ch = $c.Length
                    $r = "$l $w $ch"
                }
                Write-Host "$r $p"
            }
        } else { $content += $InputObject }
    }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'Input') {
            $c = ($content | Out-String)
            if ($Lines)      { return (@($content) | Measure-Object -Line).Lines }
            elseif ($Words)  { return (($c -split '\s+' | Where-Object { $_ }).Count) }
            elseif ($Chars)  { return $c.Length }
            else {
                $l = (@($content) | Measure-Object -Line).Lines
                $w = (($c -split '\s+' | Where-Object { $_ }).Count)
                $ch = $c.Length
                Write-Host "$l $w $ch"
            }
        }
    }
}

Export-ModuleMember -Function @('wc')
