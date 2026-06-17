# env_diff.ps1 -- Permanent vs temporary env diff (Compare-Env).

# Builds a merged permanent view: Machine + User (User overrides Machine).
function _Get-PermanentEnv {
    $result = [System.Collections.Generic.Dictionary[string,string]]::new()
    # Machine first, then User overrides
    $machine = [Environment]::GetEnvironmentVariables('Machine')
    foreach ($key in $machine.Keys) { $result[$key] = [string]$machine[$key] }
    $user = [Environment]::GetEnvironmentVariables('User')
    foreach ($key in $user.Keys) { $result[$key] = [string]$user[$key] }
    return $result
}

<#
.SYNOPSIS
    Compares process (temporary) env vars against permanent (registry).
.DESCRIPTION
    Shows environment variable differences between the current process
    scope and the permanent User/Machine registry values. Useful for
    seeing which temp vars would be lost on shell exit, or which
    permanent vars have been overridden this session.
.PARAMETER ShowSecrets
    Display values of sensitive variables (names containing TOKEN,
    SECRET, KEY, PASSWORD, CREDENTIAL).
.EXAMPLE
    Compare-Env
    Compare-Env -ShowSecrets
#>
function Compare-Env {
    [CmdletBinding()]
    param(
        [switch]$ShowSecrets
    )

    $permanent = _Get-PermanentEnv
    $process = [Environment]::GetEnvironmentVariables('Process')

    $allNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $permanent.Keys) { $null = $allNames.Add($key) }
    foreach ($key in $process.Keys) { $null = $allNames.Add($key) }

    if ($allNames.Count -eq 0) {
        Write-Host "  (no env vars to compare)" -ForegroundColor DarkGray
        return
    }

    # System vars that are always process-scoped (never in registry)
    $noisePatterns = @(
        'ALLUSERSPROFILE', 'APPDATA', 'CommonProgramFiles*', 'COMPUTERNAME',
        'ComSpec', 'HOMEDRIVE', 'HOMEPATH', 'LOCALAPPDATA', 'LOGONSERVER',
        'NUMBER_OF_PROCESSORS', 'OS', 'PATHEXT', 'PROCESSOR_*',
        'ProgramData', 'ProgramFiles*', 'ProgramW6432', 'PSModulePath',
        'PUBLIC', 'SESSIONNAME', 'SystemDrive', 'SystemRoot',
        'TEMP', 'TMP', 'USERDOMAIN*', 'USERNAME', 'USERPROFILE', 'windir'
    )

    function _Is-NoiseVar {
        param([string]$n)
        if ($n.StartsWith('_')) { return $true }
        foreach ($p in $noisePatterns) { if ($n -like $p) { return $true } }
        return $false
    }

    $sorted = $allNames | Sort-Object
    $rows = @()

    foreach ($varName in $sorted) {
        if (_Is-NoiseVar $varName) { continue }
        $processVal = [string][Environment]::GetEnvironmentVariable($varName, 'Process')
        $hasPermanent = $permanent.ContainsKey($varName)

        if (-not $hasPermanent) {
            # Process-only (temp)
            $mask = -not $ShowSecrets -and (_Is-SecretName $varName)
            $rows += [PSCustomObject]@{
                VarName   = $varName
                Status    = 'Temp only'
                Current   = if ($mask) { '***' } else { $processVal }
                Permanent = '-'
            }
        } elseif ($processVal -ne $permanent[$varName]) {
            $mask = -not $ShowSecrets -and (_Is-SecretName $varName)
            $rows += [PSCustomObject]@{
                VarName   = $varName
                Status    = 'Overridden'
                Current   = if ($mask) { '***' } else { $processVal }
                Permanent = if ($mask) { '***' } else { $permanent[$varName] }
            }
        }
        # Skip entries that are identical (nothing to show)
    }

    # Also show permanent-only vars (in registry but not in process)
    foreach ($key in $permanent.Keys) {
        if (-not $process.ContainsKey($key) -and -not (_Is-NoiseVar $key)) {
            $mask = -not $ShowSecrets -and (_Is-SecretName $key)
            $rows += [PSCustomObject]@{
                VarName   = $key
                Status    = 'Permanent only'
                Current   = '-'
                Permanent = if ($mask) { '***' } else { $permanent[$key] }
            }
        }
    }

    if ($rows.Count -eq 0) {
        Write-Host "  Process env matches permanent env (no differences)." -ForegroundColor Green
        return
    }

    $sorted = $rows | Sort-Object VarName
    $secretCount = if (-not $ShowSecrets) {
        ($sorted | Where-Object { _Is-SecretName $_.VarName }).Count
    } else { 0 }

    $sorted | Format-Table VarName, Status, Current, Permanent -AutoSize | Out-String | Write-Host

    if ($secretCount -gt 0) {
        Write-Host "  ($secretCount sensitive value(s) masked. Use -ShowSecrets to reveal.)" -ForegroundColor DarkGray
    }
}
