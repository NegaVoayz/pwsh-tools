# basics.psm1 - Unix-like commands frequently missing from PowerShell.
#
# Each function mirrors its Unix counterpart in name and flag conventions
# while routing to native PowerShell cmdlets under the hood.

# ============================================================================
# touch
# ============================================================================
<#
.SYNOPSIS
    Create an empty file or update its last-write timestamp.
.DESCRIPTION
    Mirrors Unix `touch`. Without -Time, creates the file if missing
    and bumps LastWriteTime to now. With -Time, sets an explicit timestamp.
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

# ============================================================================
# which
# ============================================================================
<#
.SYNOPSIS
    Show the full path of a command.
.DESCRIPTION
    Mirrors Unix `which`. Searches PATH for executables and also
    resolves PowerShell cmdlets, functions, and aliases.
.PARAMETER Name
    The command name to locate.
.PARAMETER All
    Show all matches (not just the first one), like which -a.
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
        if ($All) {
            $results | ForEach-Object { Write-Host $_.Source }
        } else {
            Write-Host $results[0].Source
        }
    }
}

# ============================================================================
# head
# ============================================================================
<#
.SYNOPSIS
    Output the first N lines of input.
.DESCRIPTION
    Mirrors Unix `head`. Reads from files or pipeline.
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
        } else {
            $lines += $InputObject
        }
    }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'Input') { $lines | Select-Object -First $N }
    }
}

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
        } else {
            $lines += $InputObject
        }
    }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'Input') { $lines | Select-Object -Last $N }
    }
}

# ============================================================================
# tail
# ============================================================================
<#
.SYNOPSIS
    Output the last N lines of input.
.DESCRIPTION
    Mirrors Unix `tail`. Reads from files or pipeline.
.PARAMETER Path
    File path(s). If omitted, reads from stdin.
.PARAMETER N
    Number of lines (default 10).
.PARAMETER Follow
    Wait for new lines appended to the file (like tail -f).

# ============================================================================
# wc
# ============================================================================
<#
.SYNOPSIS
    Count lines, words, and characters.
.DESCRIPTION
    Mirrors Unix `wc`. Reads from files or pipeline.
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
                if ($Lines) { $r = ((Get-Content $p | Measure-Object -Line).Lines) }
                elseif ($Words) { $r = (($c -split '\s+' | Where-Object { $_ }).Count) }
                elseif ($Chars) { $r = $c.Length }
                else {
                    $l = (Get-Content $p | Measure-Object -Line).Lines
                    $w = (($c -split '\s+' | Where-Object { $_ }).Count)
                    $ch = $c.Length
                    $r = "$l $w $ch"
                }
                Write-Host "$r $p"
            }
        } else {
            $content += $InputObject
        }
    }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'Input') {
            $c = ($content | Out-String)
            if ($Lines) { return (@($content) | Measure-Object -Line).Lines }
            elseif ($Words) { return (($c -split '\s+' | Where-Object { $_ }).Count) }
            elseif ($Chars) { return $c.Length }
            else {
                $l = (@($content) | Measure-Object -Line).Lines
                $w = (($c -split '\s+' | Where-Object { $_ }).Count)
                $ch = $c.Length
                Write-Host "$l $w $ch"
            }
        }
    }
}

# ============================================================================
# sudo
# ============================================================================
<#
.SYNOPSIS
    Run a command elevated (as Administrator) and capture its output.
.DESCRIPTION
    Mirrors Unix `sudo`. Runs the given command in an elevated process
    and captures stdout + stderr back to the current console. The current
    shell blocks until the command completes (like real sudo).

    If no command is given, opens an interactive elevated PowerShell window
    (output cannot be captured in interactive mode).

    For GUI programs (notepad, regedit, etc.), use -Gui to avoid blocking.

.PARAMETER Command
    The command/script to run elevated. If omitted, opens an elevated
    PowerShell prompt in a new window.

.PARAMETER ArgumentList
    Arguments to pass to the command.

.PARAMETER Gui
    Launch without capturing output (useful for GUI programs). The
    elevated process runs in its own window.

.PARAMETER KeepOpen
    Keep the elevated window open after the command finishes
    (only meaningful with -Gui or when Command is omitted).

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
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $stdin += $InputObject
        }
    }
    end {
        # Interactive mode: no command given -> open elevated PowerShell window
        if (-not $Command) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -Command cd '$PWD'"
            return
        }

        # GUI mode
        if ($Gui) {
            $allArgs = $ArgumentList -join ' '
            Start-Process $Command -Verb RunAs -ArgumentList $allArgs
            return
        }

        # Capture mode: run elevated, capture all output to a temp file
        $tmpOut = [System.IO.Path]::GetTempFileName()

        # Build the command to run in the elevated process
        $cmdArgs = ''
        foreach ($a in $ArgumentList) { $cmdArgs += " '$($a -replace "'","''")'" }

        # If pipeline input was provided, pipe it into the elevated command
        if ($stdin.Count -gt 0) {
            $stdinText = ($stdin | Out-String).TrimEnd()
            # Embed as a literal here-string piped to the command
            $psCommand = "Set-Location '$PWD'; @'`n$stdinText`n'@ | & '$Command'$cmdArgs *> '$tmpOut'"
        } else {
            $psCommand = "Set-Location '$PWD'; & '$Command'$cmdArgs *> '$tmpOut'"
        }

        # Encode as base64 to avoid any quoting/escaping issues
        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($psCommand)
        $encoded = [Convert]::ToBase64String($bytes)

        try {
            $proc = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

            # Read captured output and display inline
            if (Test-Path $tmpOut) {
                $raw = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
                if ($raw) { Write-Host $raw.TrimEnd() }
            }

            if ($KeepOpen) { Read-Host "Press Enter to close" }
        } finally {
            Remove-Item $tmpOut -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# ln
# ============================================================================
<#
.SYNOPSIS
    Create a symbolic link.
.DESCRIPTION
    Mirrors Unix `ln -s`. Creates a symbolic link at Link pointing to Target.
    Requires Administrator on Windows (or Developer Mode enabled).
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

# ============================================================================
# df
# ============================================================================
<#
.SYNOPSIS
    Show disk free space.
.DESCRIPTION
    Mirrors Unix `df`. Shows drive letter, total size, used, free, and
    use percentage for all fixed drives (or the specified path).
.PARAMETER Path
    Optional. If provided, shows info only for the drive containing this path.
.EXAMPLE
    df
    df C:\Users
#>
function df {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [string]$Path
    )
    process {
        if ($Path) {
            $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
            if (-not $resolved) { Write-Warning "Path not found: $Path"; return }
            $drive = $resolved.Path.Substring(0, 1) + ':'
            Get-PSDrive -Name $drive[0] -ErrorAction SilentlyContinue |
                Where-Object { $_.Used -gt 0 } |
                Format-Table Name, @{N='Total(GB)';E={[math]::Round(($_.Used+$_.Free)/1GB,1)}},
                              @{N='Used(GB)';E={[math]::Round($_.Used/1GB,1)}},
                              @{N='Free(GB)';E={[math]::Round($_.Free/1GB,1)}},
                              @{N='Use%';E={[math]::Round($_.Used/($_.Used+$_.Free)*100,1)}}
        } else {
            Get-PSDrive -PSProvider FileSystem |
                Where-Object { $_.Used -gt 0 } |
                Format-Table Name, @{N='Total(GB)';E={[math]::Round(($_.Used+$_.Free)/1GB,1)}},
                              @{N='Used(GB)';E={[math]::Round($_.Used/1GB,1)}},
                              @{N='Free(GB)';E={[math]::Round($_.Free/1GB,1)}},
                              @{N='Use%';E={[math]::Round($_.Used/($_.Used+$_.Free)*100,1)}}
        }
    }
}

# ============================================================================
# du
# ============================================================================
<#
.SYNOPSIS
    Show directory size.
.DESCRIPTION
    Mirrors Unix `du -sh`. Recursively sums file sizes in a directory.
    Defaults to the current directory.
.PARAMETER Path
    Directory path(s). Defaults to current directory.
.PARAMETER Depth
    How deep to recurse (default 0 = just the directory itself).
    Use -Depth 1 for a per-subfolder breakdown.
.EXAMPLE
    du
    du .\node_modules
    du -Depth 1
#>
function du {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [string[]]$Path = '.',

        [int]$Depth = 0
    )

    begin {
        function _FormatSize($bytes) {
            if ($bytes -gt 1GB) { return "$([math]::Round($bytes/1GB,2)) GB" }
            if ($bytes -gt 1MB) { return "$([math]::Round($bytes/1MB,2)) MB" }
            if ($bytes -gt 1KB) { return "$([math]::Round($bytes/1KB,2)) KB" }
            return "$bytes B"
        }
        $paths = @()
    }
    process {
        if ($PSBoundParameters.ContainsKey('Path')) { $paths += $Path }
    }
    end {
        if ($paths.Count -eq 0) { $paths = @('.') }
        foreach ($p in $paths) {
            $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
            if (-not $resolved) { Write-Warning "Path not found: $p"; continue }
            $dir = Get-Item $resolved
            if ($Depth -eq 0) {
                $size = (Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum
                Write-Host "$(_FormatSize $size)`t$($dir.FullName)"
            } else {
                $total = (Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                          Measure-Object -Property Length -Sum).Sum
                Write-Host "$(_FormatSize $total)`t$($dir.FullName) (total)"
                Get-ChildItem $dir.FullName -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                                 Measure-Object -Property Length -Sum).Sum
                        Write-Host "  $(_FormatSize $size)`t$($_.Name)"
                    }
            }
        }
    }
}

# ============================================================================
# grep
# ============================================================================
<#
.SYNOPSIS
    Search files for a pattern.
.DESCRIPTION
    Mirrors Unix `grep`. Wraps Select-String with familiar flags.
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
    grep "function \w+" -Recurse *.psm1
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
        if ($PSCmdlet.ParameterSetName -eq 'Input') {
            $lines += $InputObject
        }
    }
    end {
        $selectArgs = @{
            Pattern       = $Pattern
            CaseSensitive = (-not $IgnoreCase)
            NotMatch      = $Invert
        }
        if ($FilesWithMatches) { $selectArgs.List = $true }

        # Pipeline input mode
        if ($PSCmdlet.ParameterSetName -eq 'Input') {
            if (-not $lines) { return }
            $results = $lines | Select-String @selectArgs
            if ($Count) {
                Write-Host $results.Count
            } else {
                $results | ForEach-Object {
                    if ($LineNumber) { Write-Host "$($_.LineNumber): $($_.Line)" }
                    else { Write-Host $_.Line }
                }
            }
            return
        }

        # File search mode
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

# ============================================================================
# Module Exports
# ============================================================================
Export-ModuleMember -Function @(
    'touch',
    'which',
    'head',
    'tail',
    'wc',
    'sudo',
    'ln',
    'df',
    'du',
    'grep'
)
