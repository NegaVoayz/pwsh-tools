# sudo.psm1 - Run commands elevated and capture output.

<#
.SYNOPSIS
    Run a command elevated (as Administrator) and capture its output.
.DESCRIPTION
    Runs the given command in an elevated process and captures stdout
    + stderr back to the current console. The current shell blocks
    until the command completes.

    If no command is given, opens an interactive elevated PowerShell window.

    For GUI programs, use -Gui to avoid blocking.
.PARAMETER Command
    The command/script to run elevated. If omitted, opens an elevated
    PowerShell prompt in a new window.
.PARAMETER ArgumentList
    Arguments to pass to the command.
.PARAMETER Gui
    Launch without capturing output (useful for GUI programs).
.PARAMETER KeepOpen
    Keep elevated window open (only meaningful with -Gui or no command).
.EXAMPLE
    sudo whoami
    sudo .\install-service.ps1 -Force
    sudo notepad C:\Windows\System32\drivers\etc\hosts -Gui
    "127.0.0.1 foo" | sudo Out-File -Append C:\Windows\System32\drivers\etc\hosts
    sudo
#>
function sudo {
    [CmdletBinding(DefaultParameterSetName='Capture')]
    param(
        [Parameter(Position=0)]
        [string]$Command,
        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$ArgumentList,
        [Parameter(ValueFromPipeline=$true)]
        [object]$InputObject,
        [Parameter(ParameterSetName='Gui')]
        [switch]$Gui,
        [switch]$KeepOpen
    )
    begin { $stdin = @() }
    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) { $stdin += $InputObject }
    }
    end {
        if (-not $Command) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -Command cd '$PWD'"
            return
        }
        if ($Gui) {
            $allArgs = $ArgumentList -join ' '
            Start-Process $Command -Verb RunAs -ArgumentList $allArgs
            return
        }
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $cmdArgs = ''
        foreach ($a in $ArgumentList) { $cmdArgs += " '$($a -replace "'","''")'" }
        if ($stdin.Count -gt 0) {
            $stdinText = ($stdin | Out-String).TrimEnd()
            $psCommand = "Set-Location '$PWD'; @'`n$stdinText`n'@ | & '$Command'$cmdArgs *> '$tmpOut'"
        } else {
            $psCommand = "Set-Location '$PWD'; & '$Command'$cmdArgs *> '$tmpOut'"
        }
        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($psCommand)
        $encoded = [Convert]::ToBase64String($bytes)
        try {
            $proc = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
            if (Test-Path $tmpOut) {
                $raw = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
                if ($raw) { Write-Host $raw.TrimEnd() }
            }
            if ($KeepOpen) { Read-Host "Press Enter to close" }
        } finally { Remove-Item $tmpOut -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function @('sudo')
