# core.ps1 -- Core environment variable commands (Set-Env, Get-Env, Remove-Env).
#
# Scope reference:
#   Process  - Current session only ($env:VAR). Lost on shell exit.
#   User     - Persistent via HKCU:\Environment. No admin required.
#   Machine  - Persistent via HKLM\...\Environment. Requires admin.

<#
.SYNOPSIS
    Sets an environment variable.
.DESCRIPTION
    Sets an environment variable at the specified scope.
    User and Machine scopes also update the current session.
.PARAMETER Name
    The environment variable name.
.PARAMETER Value
    The value to set.
.PARAMETER Permanent
    Shorthand for -Scope User. Ignored if -Scope is also specified.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.EXAMPLE
    Set-Env -Name "JAVA_HOME" -Value "C:\Java\jdk-17" -Permanent
    Set-Env -Name "JAVA_HOME" -Value "C:\Java\jdk-17" -Scope User
#>
function Set-Env {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$Value,
        [Parameter(Position=2)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Permanent
    )
    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) { $Scope = 'User' }
    $envTarget = switch ($Scope) { 'Machine' { 'Machine' } 'User' { 'User' } default { 'Process' } }
    if ($PSCmdlet.ShouldProcess("$Scope env", "Set $Name=$Value")) {
        [Environment]::SetEnvironmentVariable($Name, $Value, $envTarget)
        Write-Verbose "Set $Scope environment variable: $Name=$Value"
    }
}

<#
.SYNOPSIS
    Gets an environment variable.
.DESCRIPTION
    Process scope reads from $env: (User + Machine merged).
    User and Machine scopes read directly from the registry.
.PARAMETER Name
    The environment variable name.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.EXAMPLE
    Get-Env -Name "JAVA_HOME" -Scope User
#>
function Get-Env {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process'
    )
    return [Environment]::GetEnvironmentVariable($Name, $Scope)
}

<#
.SYNOPSIS
    Removes an environment variable.
.DESCRIPTION
    Sets the variable to $null at the specified scope.
    User and Machine scopes also update the current session.
.PARAMETER Name
    The environment variable name.
.PARAMETER Permanent
    Shorthand for -Scope User. Ignored if -Scope is also specified.
.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
.EXAMPLE
    Remove-Env -Name "TEMP_DEBUG" -Permanent
    Remove-Env -Name "TEMP_DEBUG" -Scope Process
#>
function Remove-Env {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name,
        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',
        [switch]$Permanent
    )
    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) { $Scope = 'User' }
    $envTarget = switch ($Scope) { 'Machine' { 'Machine' } 'User' { 'User' } default { 'Process' } }
    if ($PSCmdlet.ShouldProcess("$Scope env", "Remove $Name")) {
        [Environment]::SetEnvironmentVariable($Name, $null, $envTarget)
        Write-Verbose "Removed $Scope environment variable: $Name"
    }
}
