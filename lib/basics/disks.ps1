# disks.psm1 - Disk usage commands (df, du).

<#
.SYNOPSIS
    Show disk free space.
.DESCRIPTION
    Shows drive letter, total size, used, free, and use percentage
    for all fixed drives, or for the drive containing a given path.
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

<#
.SYNOPSIS
    Show directory size.
.DESCRIPTION
    Recursively sums file sizes. Defaults to current directory.
.PARAMETER Path
    Directory path(s). Defaults to current directory.
.PARAMETER Depth
    How deep to recurse (default 0 = just the directory).
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
    process { if ($PSBoundParameters.ContainsKey('Path')) { $paths += $Path } }
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
