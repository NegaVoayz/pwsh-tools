# tempenv.ps1 — Temporary environment variable tracking and permanentization.
#
# Module-scoped state lives for the duration of the PowerShell session.
# _TempEnvVars tracks vars explicitly set via Set-TempEnv (permanentizable).
# _EnvBaseline is a snapshot of all env vars at module load (detects changes).

# Module-scoped state
$script:_TempEnvVars = [System.Collections.Generic.Dictionary[string,string]]::new()
$script:_EnvBaseline = $null

# Capture baseline snapshot once at module load
function _Init-Baseline {
    if ($null -ne $script:_EnvBaseline) { return }
    $script:_EnvBaseline = [System.Collections.Generic.Dictionary[string,string]]::new()
    $all = [Environment]::GetEnvironmentVariables('Process')
    foreach ($key in $all.Keys) {
        $script:_EnvBaseline[$key] = [string]$all[$key]
    }
}
_Init-Baseline

# Sensitive-var pattern: names containing these keywords have values masked.
$script:_SecretPatterns = @('*TOKEN*', '*SECRET*', '*KEY*', '*PASSWORD*', '*CREDENTIAL*')

function _Is-SecretName {
    param([string]$Name)
    foreach ($pat in $script:_SecretPatterns) {
        if ($Name -like $pat) { return $true }
    }
    return $false
}

<#
.SYNOPSIS
    Sets a temporary environment variable. (tracked, permanentizable).
.DESCRIPTION
    Sets a process-scope environment variable and adds it to the
    temporary tracking list. Tracked vars can be permanentized later
    with Save-Env, or listed with Get-TempEnv.
.PARAMETER Name
    The environment variable name.
.PARAMETER Value
    The value to set.
.EXAMPLE
    Set-TempEnv DEBUG_MODE 1
    Set-TempEnv API_URL "https://staging.example.com"
#>
function Set-TempEnv {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$Value
    )

    if ($PSCmdlet.ShouldProcess("Process env", "Set temp $Name=$Value")) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
        $script:_TempEnvVars[$Name] = $Value
        Write-Verbose "Set temporary env: $Name=$Value"
    }
}

<#
.SYNOPSIS
    Permanentizes temporary environment variables.
.DESCRIPTION
    Promotes tracked temp environment variables (set via Set-TempEnv)
    from Process scope to persistent User scope in the registry.
    Permanentized vars are removed from tracking.
.PARAMETER Name
    Specific temp env var names to permanentize.
.PARAMETER All
    Permanentize ALL tracked temp env vars.
.EXAMPLE
    Save-Env -Name DEBUG_MODE, API_URL
    Save-Env -All
#>
function Save-Env {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='ByName', Position=0)]
        [string[]]$Name,
        [Parameter(Mandatory=$true, ParameterSetName='All')]
        [switch]$All
    )

    $toSave = @()
    if ($All) {
        $toSave = @($script:_TempEnvVars.Keys)
    } else {
        foreach ($n in $Name) {
            if ($script:_TempEnvVars.ContainsKey($n)) {
                $toSave += $n
            } else {
                Write-Warning "'$n' is not a tracked temp env var. Use Set-TempEnv first or check the name."
            }
        }
    }

    if ($toSave.Count -eq 0) {
        Write-Host "  (no temp env vars to save)" -ForegroundColor DarkGray
        return
    }

    foreach ($varName in $toSave) {
        $value = $script:_TempEnvVars[$varName]
        if ($PSCmdlet.ShouldProcess("User env", "Save $varName=$value")) {
            [Environment]::SetEnvironmentVariable($varName, $value, 'User')
            $null = $script:_TempEnvVars.Remove($varName)
            Write-Host "  Saved -> User scope: $varName" -ForegroundColor Green
        }
    }
}

<#
.SYNOPSIS
    Clears the temp env tracking list.
.DESCRIPTION
    Removes all variables from the temp tracking list without
    permanentizing them. The process-scope env vars themselves
    remain set for the current session.
.EXAMPLE
    Clear-TempEnv
#>
function Clear-TempEnv {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($script:_TempEnvVars.Count -eq 0) {
        Write-Host "  (no temp env vars to clear)" -ForegroundColor DarkGray
        return
    }

    if ($PSCmdlet.ShouldProcess("Temp env tracking", "Clear $($script:_TempEnvVars.Count) entries")) {
        $count = $script:_TempEnvVars.Count
        $script:_TempEnvVars.Clear()
        Write-Host "  Cleared $count temp env tracking entries(s)" -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Removes temporary environment variables from tracking and the session.
.DESCRIPTION
    Removes the specified temp environment variable from both the
    tracking list and the process scope. Unlike Remove-Env, this also
    cleans up the temp tracking entry. Unlike Clear-TempEnv, this
    actually removes the variable value.
.PARAMETER Name
    The temp env var name(s) to remove.
.EXAMPLE
    Remove-TempEnv DEBUG_MODE
    Remove-TempEnv API_URL, DEBUG_MODE
#>
function Remove-TempEnv {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$Name
    )

    $removed = 0
    foreach ($n in $Name) {
        $wasTracked = $script:_TempEnvVars.ContainsKey($n)
        if (-not $wasTracked) {
            Write-Warning "'$n' is not a tracked temp env var."
            continue
        }

        if ($PSCmdlet.ShouldProcess("Process env + tracking", "Remove $n")) {
            [Environment]::SetEnvironmentVariable($n, $null, 'Process')
            $null = $script:_TempEnvVars.Remove($n)
            Write-Host "  Removed temp env: $n" -ForegroundColor Green
            $removed++
        }
    }

    if ($removed -gt 0) {
        Write-Verbose "Removed $removed temp env var(s)"
    }
}
