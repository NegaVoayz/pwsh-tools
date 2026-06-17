# tempenv_view.ps1 — Temp env display (Get-TempEnv).

<#
.SYNOPSIS
    Lists temporary and changed environment variables.
.DESCRIPTION
    Shows all environment variables that differ from the baseline
    captured at module load, plus all vars explicitly tracked via
    Set-TempEnv. Sensitive values (names containing TOKEN, SECRET,
    KEY, PASSWORD, CREDENTIAL) are masked as '***' unless -ShowSecrets
    is used.
.PARAMETER Name
    Show details for a specific variable only.
.PARAMETER ShowSecrets
    Display values of sensitive variables.
.EXAMPLE
    Get-TempEnv
    Get-TempEnv -Name DEBUG_MODE
    Get-TempEnv -ShowSecrets
#>
function Get-TempEnv {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Name,
        [switch]$ShowSecrets
    )

    if ($Name) {
        _Show-SingleTempEnv -Name $Name -ShowSecrets:$ShowSecrets
        return
    }

    # Collect all var names that are either tracked or changed
    $allNames = [System.Collections.Generic.HashSet[string]]::new()

    # Tracked names
    foreach ($key in $script:_TempEnvVars.Keys) { $null = $allNames.Add($key) }

    # Changed names (current differs from baseline)
    foreach ($key in $script:_EnvBaseline.Keys) {
        $current = [string][Environment]::GetEnvironmentVariable($key, 'Process')
        $baselineVal = $script:_EnvBaseline[$key]
        if ($current -ne $baselineVal) {
            $null = $allNames.Add($key)
        }
    }

    # Vars that exist now but weren't in baseline
    $allCurrent = [Environment]::GetEnvironmentVariables('Process')
    foreach ($key in $allCurrent.Keys) {
        if (-not $script:_EnvBaseline.ContainsKey($key)) {
            $null = $allNames.Add($key)
        }
    }

    if ($allNames.Count -eq 0) {
        Write-Host "  (no temp or changed environment variables)" -ForegroundColor DarkGray
        return
    }

    $sorted = $allNames | Sort-Object
    $rows = @()

    foreach ($varName in $sorted) {
        $isTracked = $script:_TempEnvVars.ContainsKey($varName)
        $current = [string][Environment]::GetEnvironmentVariable($varName, 'Process')
        $inBaseline = $script:_EnvBaseline.ContainsKey($varName)
        $changed = $false
        $original = ''
        if ($inBaseline) {
            $original = $script:_EnvBaseline[$varName]
            if ($current -ne $original) { $changed = $true }
        } else {
            $original = '(did not exist)'
            # New vars: only "changed" if not explicitly tracked via Set-TempEnv
            $changed = (-not $isTracked)
        }

        if (-not $isTracked -and -not $changed) { continue }

        if ($isTracked -and $changed) {
            $type = 'Both'
        } elseif ($isTracked) {
            $type = 'New'
        } else {
            $type = 'Changed'
        }

        $mask = -not $ShowSecrets -and (_Is-SecretName $varName)
        $displayCurrent = if ($mask) { '***' } else { $current }
        $displayOriginal = if ($mask) { '***' } else { $original }

        $rows += [PSCustomObject]@{
            VarName  = $varName
            Type     = $type
            Current  = $displayCurrent
            Original = $displayOriginal
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host "  (no temp or changed environment variables)" -ForegroundColor DarkGray
        return
    }

    $secretCount = if (-not $ShowSecrets) {
        ($rows | Where-Object { _Is-SecretName $_.VarName }).Count
    } else { 0 }

    $rows | Format-Table VarName, Type, Current, Original -AutoSize | Out-String | Write-Host

    if ($secretCount -gt 0) {
        Write-Host "  ($secretCount sensitive value(s) masked. Use -ShowSecrets to reveal.)" -ForegroundColor DarkGray
    }
}

function _Show-SingleTempEnv {
    param([string]$Name, [switch]$ShowSecrets)

    $isTracked = $script:_TempEnvVars.ContainsKey($Name)
    $current = [string][Environment]::GetEnvironmentVariable($Name, 'Process')
    $inBaseline = $script:_EnvBaseline.ContainsKey($Name)
    $original = if ($inBaseline) { $script:_EnvBaseline[$Name] } else { $null }

    $mask = -not $ShowSecrets -and (_Is-SecretName $Name)

    Write-Host ""
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host "  $(('-' * 50))" -ForegroundColor DarkGray
    Write-Host ""

    if ($isTracked) {
        $val = if ($mask) { '***' } else { $script:_TempEnvVars[$Name] }
        Write-Host "  Status  : Tracked (Set-TempEnv)" -ForegroundColor Yellow
        Write-Host "  Value   : $val"
    }

    if ($inBaseline) {
        if ($current -ne $script:_EnvBaseline[$Name]) {
            $origVal = if ($mask) { '***' } else { $script:_EnvBaseline[$Name] }
            $currVal = if ($mask) { '***' } else { $current }
            Write-Host "  Status  : Changed from baseline" -ForegroundColor Yellow
            Write-Host "  Original: $origVal"
            Write-Host "  Current : $currVal"
        } elseif (-not $isTracked) {
            Write-Host "  Status  : Unchanged (matches baseline)" -ForegroundColor DarkGray
            $currVal = if ($mask) { '***' } else { $current }
            Write-Host "  Value   : $currVal"
        }
    } elseif (-not $isTracked) {
        $currVal = if ($mask) { '***' } else { $current }
        Write-Host "  Status  : New (not in baseline, not tracked)" -ForegroundColor DarkGray
        Write-Host "  Value   : $currVal"
    }

    Write-Host ""
}
