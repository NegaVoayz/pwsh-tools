# view.psm1 - File content viewing (head, tail).

<#
.SYNOPSIS
    Output the first N lines of input.
.DESCRIPTION
    Reads from files or pipeline.
.PARAMETER Path
    File path(s). If omitted, reads from stdin.
.PARAMETER N
    Number of lines (default 10).
.EXAMPLE
    head log.txt
    head log.txt -N 25
    Get-Content huge.log | head -N 5
#>
function head {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Position=0, ParameterSetName='Path')]
        [string[]]$Path,
        [Parameter(ValueFromPipeline=$true, ParameterSetName='Input')]
        [object]$InputObject,
        [int]$N = 10
    )
    begin { $lines = @() }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($p in $Path) { Get-Content $p -TotalCount $N }
        } else { $lines += $InputObject }
    }
    end { if ($PSCmdlet.ParameterSetName -eq 'Input') { $lines | Select-Object -First $N } }
}

<#
.SYNOPSIS
    Output the last N lines of input.
.DESCRIPTION
    Reads from files or pipeline.
.PARAMETER Path
    File path(s). If omitted, reads from stdin.
.PARAMETER N
    Number of lines (default 10).
.PARAMETER Follow
    Wait for new lines (like tail -f). Single file only.
.EXAMPLE
    tail log.txt
    tail log.txt -N 50
    Get-Content huge.log | tail -N 5
    tail app.log -Follow
#>
function tail {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Position=0, ParameterSetName='Path')]
        [string[]]$Path,
        [Parameter(ValueFromPipeline=$true, ParameterSetName='Input')]
        [object]$InputObject,
        [int]$N = 10,
        [switch]$Follow
    )
    begin { $lines = @() }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path' -and $Follow) {
            Get-Content $Path[0] -Tail $N -Wait
        } elseif ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($p in $Path) { Get-Content $p -Tail $N }
        } else { $lines += $InputObject }
    }
    end { if ($PSCmdlet.ParameterSetName -eq 'Input') { $lines | Select-Object -Last $N } }
}
