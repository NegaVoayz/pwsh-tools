# man.psm1 - Unified help browser for pwsh-tools modules.
#
# Show-Manual discovers all modules in ../lib and presents their
# exported functions with synopses. Each module documents itself via
# standard PowerShell comment-based help — no extra registration needed.
#
# Usage:
#   Show-Manual                  List all modules and their functions
#   Show-Manual <ModuleName>     List functions in a specific module
#   Show-Manual <FunctionName>   Show full help for a function
#   Show-Manual -Full            List with descriptions (more detail)

$Script:ManModuleRoot = $PSScriptRoot

<#
.SYNOPSIS
    Browse help for pwsh-tools modules and functions.

.DESCRIPTION
    Without arguments, lists all pwsh-tools modules and their exported
    functions with a one-line synopsis for each.

    With a module name, lists only functions from that module.

    With a function name, shows full comment-based help (Get-Help -Full)
    for that function.

    Each .psm1 file under lib/ documents itself with standard PowerShell
    comment-based help. Write a .SYNOPSIS block above each function
    and Show-Manual discovers them automatically.

.PARAMETER Name
    A module name or function name to show help for.
    Module names are tried first (e.g. 'Show-Manual env' lists env functions).

.PARAMETER Full
    When listing, show the full synopsis instead of a compact view.

.EXAMPLE
    Show-Manual
    Show-Manual env
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

    $libPath = $Script:ManModuleRoot

    # --- Module discovery ---
    $modules = @(Get-ChildItem -Path $libPath -Filter '*.psm1' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -ne 'man' } |
        Sort-Object Name)

    if ($modules.Count -eq 0) {
        Write-Host "  No pwsh-tools modules found in: $libPath" -ForegroundColor Yellow
        return
    }

    # Build index: module name -> list of exported functions
    $moduleIndex = @{}
    foreach ($mod in $modules) {
        $exported = _Get-ExportedFunctions -ModulePath $mod.FullName
        if ($exported) {
            $moduleIndex[$mod.BaseName] = $exported
        }
    }

    # --- Case 1: no argument -> list all modules ---
    if (-not $Name) {
        Write-Host "`n  pwsh-tools modules" -ForegroundColor Cyan
        Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($mod in $modules) {
            $funcs = $moduleIndex[$mod.BaseName]
            if (-not $funcs) { continue }
            Write-Host "  [$($mod.BaseName)]" -ForegroundColor Yellow
            if ($Full) {
                foreach ($f in $funcs) {
                    $synopsis = _Get-Synopsis -FunctionName $f.Name -ModulePath $mod.FullName
                    Write-Host "    $($f.Name)  " -NoNewline
                    Write-Host $synopsis
                }
            } else {
                $names = ($funcs | ForEach-Object { $_.Name }) -join ', '
                Write-Host "    $names"
            }
            Write-Host ""
        }
        Write-Host "  Use 'Show-Manual <Module>' for module details," -ForegroundColor DarkGray
        Write-Host "  or 'Show-Manual <Function>' for full function help." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- Case 2: argument is a module name ---
    if ($moduleIndex.ContainsKey($Name)) {
        $funcs = $moduleIndex[$Name]
        Write-Host "`n  [$Name] module" -ForegroundColor Cyan
        Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($f in $funcs) {
            $synopsis = _Get-Synopsis -FunctionName $f.Name -ModulePath (Join-Path $libPath "$Name.psm1")
            Write-Host "  $($f.Name)" -ForegroundColor Yellow -NoNewline
            Write-Host "  $synopsis"
        }
        Write-Host ""
        return
    }

    # --- Case 3: argument is (probably) a function name -> search all modules ---
    foreach ($mod in $modules) {
        $funcs = $moduleIndex[$mod.BaseName]
        if (-not $funcs) { continue }
        $match = $funcs | Where-Object { $_.Name -eq $Name }
        if ($match) {
            Write-Host "`n  $Name  [$($mod.BaseName) module]" -ForegroundColor Cyan
            Write-Host "  $(('-' * 50))" -ForegroundColor DarkGray
            Write-Host ""
            Get-Help $Name -Full 2>$null
            return
        }
    }

    # --- Not found ---
    Write-Warning "'$Name' is not a recognized module or function name."
    Write-Host "  Available modules: $($moduleIndex.Keys -join ', ')"
}

# ============================================================================
# Internal Helpers
# ============================================================================

# Returns exported function names from a .psm1 file by parsing Export-ModuleMember.
# Falls back to Get-Command if the module is already loaded.
function _Get-ExportedFunctions {
    param([string]$ModulePath)

    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)

    # Prefer Get-Module if already loaded (accurate, less fragile)
    $loaded = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
    if ($loaded) {
        return @($loaded.ExportedCommands.Values | Where-Object { $_ -is [System.Management.Automation.FunctionInfo] })
    }

    # Parse the .psm1 for Export-ModuleMember -Function
    $content = Get-Content $ModulePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }

    # Extract the function list from Export-ModuleMember
    $exported = @()
    if ($content -match "Export-ModuleMember\s+-Function\s+@\(([^)]+)\)") {
        $raw = $matches[1]
        $names = $raw -split ',' | ForEach-Object {
            $_.Trim() -replace "['`"]", ''
        } | Where-Object { $_ }
        foreach ($n in $names) {
            $exported += @{ Name = $n }
        }
    }
    return $exported
}

# Extracts the .SYNOPSIS from comment-based help in a .psm1 file.
# Uses Get-Help if the module is loaded, otherwise parses the file directly.
function _Get-Synopsis {
    param(
        [string]$FunctionName,
        [string]$ModulePath
    )

    # Try Get-Help first (works if module is loaded)
    $help = Get-Help $FunctionName -ErrorAction SilentlyContinue
    if ($help -and $help.Synopsis -and $help.Synopsis.Trim().Length -gt 0) {
        return $help.Synopsis.Trim() -replace '\n', ' '
    }

    # Fallback: parse the .psm1 file for the comment block before the function
    $content = Get-Content $ModulePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return '' }

    # Match: comment-based help block ending right before "function $FunctionName"
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

# ============================================================================
# Module Exports
# ============================================================================
Export-ModuleMember -Function @('Show-Manual')
