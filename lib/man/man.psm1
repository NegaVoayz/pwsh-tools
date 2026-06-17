# man/man.psm1 — Help browser package.
#
# Show-Manual discovers all packages under lib/ and presents their
# exported functions. Each package documents itself via standard
# PowerShell comment-based help.

$Script:ManModuleRoot = Split-Path $PSScriptRoot -Parent

<#
.SYNOPSIS
    Browse help for pwsh-tools packages and functions.
.DESCRIPTION
    Without arguments, lists all packages and their functions.
    With a package name, lists only functions from that package.
    With a function name, shows full help (Get-Help -Full).
.PARAMETER Name
    A package name or function name to show help for.
.PARAMETER Full
    When listing, show synopsis for each function.
.EXAMPLE
    Show-Manual
    Show-Manual path
    Show-Manual Show-Path
    Show-Manual -Full
#>
function Show-Manual {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Name,
        [switch]$Full
    )

    $libRoot = $Script:ManModuleRoot

    # Discover packages: each subdirectory with a <name>.psm1 entry point
    $packages = @(Get-ChildItem -Path $libRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).psm1") } |
        Sort-Object Name)

    if ($packages.Count -eq 0) {
        Write-Host "  No pwsh-tools packages found in: $libRoot" -ForegroundColor Yellow
        return
    }

    # Build index: package name -> list of exported functions
    $pkgIndex = @{}
    foreach ($pkg in $packages) {
        $pkgPath = Join-Path $pkg.FullName "$($pkg.Name).psm1"
        $exported = _Get-ExportedFunctions -ExportPath $pkgPath
        if ($exported) { $pkgIndex[$pkg.Name] = $exported }
    }

    # --- Case 1: no argument -> list all packages ---
    if (-not $Name) {
        Write-Host "`n  pwsh-tools packages" -ForegroundColor Cyan
        Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($pkg in $packages) {
            $funcs = $pkgIndex[$pkg.Name]
            if (-not $funcs) { continue }
            Write-Host "  [$($pkg.Name)]" -ForegroundColor Yellow
            if ($Full) {
                $pkgPath = Join-Path $pkg.FullName "$($pkg.Name).psm1"
                foreach ($f in $funcs) {
                    $synopsis = _Get-Synopsis -FunctionName $f.Name -ModulePath $pkgPath
                    Write-Host "    $($f.Name)  " -NoNewline
                    Write-Host $synopsis
                }
            } else {
                $names = ($funcs | ForEach-Object { $_.Name }) -join ', '
                Write-Host "    $names"
            }
            Write-Host ""
        }
        Write-Host "  Use 'Show-Manual <Package>' for details," -ForegroundColor DarkGray
        Write-Host "  or 'Show-Manual <Function>' for full help." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- Case 2: argument is a package name ---
    if ($pkgIndex.ContainsKey($Name)) {
        $funcs = $pkgIndex[$Name]
        $pkgPath = Join-Path $libRoot "$Name\$Name.psm1"
        Write-Host "`n  [$Name] package" -ForegroundColor Cyan
        Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($f in $funcs) {
            $synopsis = _Get-Synopsis -FunctionName $f.Name -ModulePath $pkgPath
            Write-Host "  $($f.Name)" -ForegroundColor Yellow -NoNewline
            Write-Host "  $synopsis"
        }
        Write-Host ""
        return
    }

    # --- Case 3: argument is a function name -> search all packages ---
    foreach ($pkg in $packages) {
        $funcs = $pkgIndex[$pkg.Name]
        if (-not $funcs) { continue }
        $match = $funcs | Where-Object { $_.Name -eq $Name }
        if ($match) {
            Write-Host "`n  $Name  [$($pkg.Name) package]" -ForegroundColor Cyan
            Write-Host "  $(('-' * 50))" -ForegroundColor DarkGray
            Write-Host ""
            Get-Help $Name -Full 2>$null
            return
        }
    }

    Write-Warning "'$Name' is not a recognized package or function name."
    Write-Host "  Available packages: $($pkgIndex.Keys -join ', ')"
}

# Returns exported function names from a package's entry point.
function _Get-ExportedFunctions {
    param([string]$ExportPath)

    # Check if already loaded by matching the module path
    $loaded = Get-Module | Where-Object { $_.Path -eq $ExportPath }
    if ($loaded) {
        return @($loaded.ExportedCommands.Values | Where-Object { $_ -is [System.Management.Automation.FunctionInfo] })
    }

    # Parse Export-ModuleMember from the file
    $content = Get-Content $ExportPath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }

    $exported = @()
    if ($content -match "Export-ModuleMember\s+-Function\s+@\(([^)]+)\)") {
        $raw = $matches[1]
        $names = $raw -split ',' | ForEach-Object {
            $_.Trim() -replace "['`"]", ''
        } | Where-Object { $_ }
        foreach ($n in $names) { $exported += @{ Name = $n } }
    }
    return $exported
}

# Extracts .SYNOPSIS from comment-based help in a package entry point.
function _Get-Synopsis {
    param([string]$FunctionName, [string]$ModulePath)

    $help = Get-Help $FunctionName -ErrorAction SilentlyContinue
    if ($help -and $help.Synopsis -and $help.Synopsis.Trim().Length -gt 0) {
        return $help.Synopsis.Trim() -replace '\n', ' '
    }

    $content = Get-Content $ModulePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return '' }

    $escaped = [regex]::Escape($FunctionName)
    $pattern = "(?s)<#\s*\r?\n(.*?)\r?\n\s*#>\s*\r?\n\s*function\s+$escaped\b"
    if ($content -match $pattern) {
        $block = $matches[1]
        if ($block -match '\.SYNOPSIS\s*\n\s*(.*)') {
            return $matches[1].Trim() -replace '\n', ' '
        }
    }
    return ''
}

Export-ModuleMember -Function @('Show-Manual')
