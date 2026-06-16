# env.psm1 - Environment variable management for Windows PowerShell 5.1
#
# Provides functions for managing PATH and general environment variables
# at Process, User, and Machine scopes.
#
# Scope reference:
#   Process  - Current session only ($env:VAR). Lost on shell exit.
#   User     - Persistent via HKCU:\Environment. No admin required.
#   Machine  - Persistent via HKLM\...\Environment. Requires admin.

# ============================================================================
# PATH Management Functions
# ============================================================================

<#
.SYNOPSIS
    Adds a directory to a PATH scope.

.DESCRIPTION
    Adds a directory to the PATH environment variable at the specified scope.
    Deduplicates entries (case-insensitive, normalized comparison).
    Optionally specifies insertion position (beginning or end).

.PARAMETER Path
    The directory path to add. Can be relative (will be resolved).

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.
    User and Machine scopes also update the current session.

.PARAMETER Permanent
    Shorthand for -Scope User. Saves the change persistently (no admin required).
    Ignored if -Scope is also specified explicitly.

.PARAMETER Position
    Where to insert: Beginning (prepend) or End (append). Default is End.

.EXAMPLE
    Add-Path -Path "C:\my-tools\bin" -Permanent
    Add-Path -Path "C:\my-tools\bin" -Scope User -Position Beginning
#>
function Add-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,

        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',

        [switch]$Permanent,

        [ValidateSet('Beginning', 'End')]
        [string]$Position = 'End'
    )

    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) {
        $Scope = 'User'
    }

    $resolved = _Resolve-PathEntry $Path
    $current  = _Get-PathEntries -Scope $Scope

    # Dedup check (case-insensitive, normalized)
    $alreadyExists = $current | Where-Object {
        (_Normalize-PathEntry $_) -eq (_Normalize-PathEntry $resolved)
    }

    if ($alreadyExists) {
        Write-Verbose "PATH entry already present: $resolved (scope: $Scope)"
        return
    }

    if ($Position -eq 'Beginning') {
        $newEntries = @($resolved) + $current
    } else {
        $newEntries = $current + @($resolved)
    }

    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add $resolved")) {
        _Set-PathEntries -Entries $newEntries -Scope $Scope
        Write-Verbose "Added to $Scope PATH: $resolved"
    }
}

<#
.SYNOPSIS
    Removes a directory from a PATH scope.

.DESCRIPTION
    Removes a directory from the PATH environment variable at the specified scope.
    Matching is case-insensitive with path normalization.

.PARAMETER Path
    The directory path to remove. Matched against individual entries via
    normalized comparison.

.PARAMETER Permanent
    Shorthand for -Scope User. Removes from persistent User PATH.
    Ignored if -Scope is also specified explicitly.

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.

.EXAMPLE
    Remove-Path -Path "C:\my-tools\bin" -Permanent
    Remove-Path -Path "C:\my-tools\bin" -Scope User
#>
function Remove-Path {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,

        [Parameter(Position=1)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',

        [switch]$Permanent
    )

    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) {
        $Scope = 'User'
    }

    $current  = _Get-PathEntries -Scope $Scope
    $target   = _Normalize-PathEntry $Path
    $count    = $current.Count

    $newEntries = $current | Where-Object {
        (_Normalize-PathEntry $_) -ne $target
    }

    $removed = $count - $newEntries.Count
    if ($removed -eq 0) {
        Write-Verbose "PATH entry not found: $Path (scope: $Scope)"
        return
    }

    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Remove $Path ($removed entries)")) {
        _Set-PathEntries -Entries $newEntries -Scope $Scope
        Write-Verbose "Removed from $Scope PATH: $Path ($removed match(es))"
    }
}

<#
.SYNOPSIS
    Gets PATH entries for a scope.

.DESCRIPTION
    Returns PATH entries as an array of strings, one per directory.
    Also supports returning the raw semicolon-separated string.

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.

.PARAMETER Raw
    If specified, returns the raw semicolon-separated string instead of an array.

.EXAMPLE
    Get-Path -Scope User | ForEach-Object { Write-Host $_ }
    Get-Path -Scope Machine -Raw
#>
function Get-Path {
    [CmdletBinding()]
    param(
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',

        [switch]$Raw
    )

    if ($Raw) {
        return _Get-PathRaw -Scope $Scope
    }
    return _Get-PathEntries -Scope $Scope
}

<#
.SYNOPSIS
    Displays PATH entries in a readable numbered list.

.DESCRIPTION
    Shows PATH entries with index numbers, scope label, and optional
    existence checks. Missing directories are highlighted.
    Purely for display — use Get-Path for programmatic access.

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.

.PARAMETER Check
    If specified, checks whether each PATH entry exists on disk and
    marks missing directories with a warning.

.EXAMPLE
    Show-Path
    Show-Path -Scope User -Check
#>
function Show-Path {
    [CmdletBinding()]
    param(
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'Process',

        [switch]$Check
    )

    $entries = _Get-PathEntries -Scope $Scope
    if ($entries.Count -eq 0) {
        Write-Host "[$Scope PATH] (empty)"
        return
    }

    Write-Host "[$Scope PATH] ($($entries.Count) entries):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $idx   = "{0,3}" -f ($i + 1)
        $entry = $entries[$i]

        if ($Check) {
            # Skip check for entries that use environment variable references
            if ($entry -match '%\w+%') {
                Write-Host "  $idx. $entry" -ForegroundColor Yellow
            } elseif (Test-Path $entry) {
                Write-Host "  $idx. $entry" -ForegroundColor Green
            } else {
                Write-Host "  $idx. $entry (missing)" -ForegroundColor Red
            }
        } else {
            Write-Host "  $idx. $entry"
        }
    }
}

# ============================================================================
# General Environment Variable Functions
# ============================================================================

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
    Shorthand for -Scope User. Saves the variable persistently (no admin required).
    Ignored if -Scope is also specified explicitly.

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.

.EXAMPLE
    Set-Env -Name "JAVA_HOME" -Value "C:\Program Files\Java\jdk-17" -Permanent
    Set-Env -Name "JAVA_HOME" -Value "C:\Program Files\Java\jdk-17" -Scope User
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

    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) {
        $Scope = 'User'
    }

    $envTarget = switch ($Scope) {
        'Machine' { 'Machine' }
        'User'    { 'User' }
        default   { 'Process' }
    }

    if ($PSCmdlet.ShouldProcess("$Scope env", "Set $Name=$Value")) {
        [Environment]::SetEnvironmentVariable($Name, $Value, $envTarget)
        Write-Verbose "Set $Scope environment variable: $Name=$Value"
    }
}

<#
.SYNOPSIS
    Gets an environment variable.

.DESCRIPTION
    Gets an environment variable from the specified scope.
    Process scope reads from $env: (which includes both User and Machine merged).
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
    Removes an environment variable from the specified scope by setting it to $null.
    User and Machine scopes also update the current session.

.PARAMETER Name
    The environment variable name.

.PARAMETER Permanent
    Shorthand for -Scope User. Removes the variable from persistent User scope.
    Ignored if -Scope is also specified explicitly.

.PARAMETER Scope
    Process, User, or Machine. Defaults to Process.

.EXAMPLE
    Remove-Env -Name "TEMP_DEBUG" -Permanent
    Remove-Env -Name "TEMP_DEBUG" -Scope Process

.NOTES
    For a complete function listing with synopses, use: Show-Manual env
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

    if ($Permanent -and -not $PSBoundParameters.ContainsKey('Scope')) {
        $Scope = 'User'
    }

    $envTarget = switch ($Scope) {
        'Machine' { 'Machine' }
        'User'    { 'User' }
        default   { 'Process' }
    }

    if ($PSCmdlet.ShouldProcess("$Scope env", "Remove $Name")) {
        [Environment]::SetEnvironmentVariable($Name, $null, $envTarget)
        Write-Verbose "Removed $Scope environment variable: $Name"
    }
}

# ============================================================================
# Internal Helper Functions (not exported)
# ============================================================================

# Normalizes a single PATH entry for comparison:
#   - Trims whitespace
#   - Trims trailing backslash
#   - Converts forward slashes to backslashes
# Does NOT resolve to full path — preserves %VAR% references.
function _Normalize-PathEntry {
    param([string]$Entry)
    return $Entry.Trim().TrimEnd('\').Replace('/', '\')
}

# Resolves a user-provided path to an absolute form.
# Only resolves relative paths — absolute paths and %VAR% references
# are returned as-is after trim/normalize.
function _Resolve-PathEntry {
    param([string]$Entry)
    $trimmed = $Entry.Trim().TrimEnd('\').Replace('/', '\')
    if ([System.IO.Path]::IsPathRooted($trimmed)) {
        return $trimmed
    }
    return [System.IO.Path]::GetFullPath($trimmed)
}

# Returns PATH entries as a string array (no empty entries)
function _Get-PathEntries {
    param([string]$Scope)
    $raw = _Get-PathRaw -Scope $Scope
    return $raw -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() }
}

# Returns the raw semicolon-separated PATH string for a scope
function _Get-PathRaw {
    param([string]$Scope)
    $value = [Environment]::GetEnvironmentVariable('PATH', $Scope)
    if ($null -eq $value) { return '' } else { return $value }
}

# Sets PATH entries (string array) back to the specified scope.
# User/Machine scopes also rebuild the process PATH so the user
# sees the effect immediately without a shell restart.
function _Set-PathEntries {
    param(
        [string[]]$Entries,
        [string]$Scope
    )
    $raw = ($Entries -join ';').TrimEnd(';')

    [Environment]::SetEnvironmentVariable('PATH', $raw, $Scope)

    # When setting User or Machine scope, rebuild process PATH from registry
    # so changes are visible in the current session.
    if ($Scope -ne 'Process') {
        $userPath    = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $parts = @($machinePath, $userPath) | Where-Object { $_ }
        $env:PATH = $parts -join ';'
    }
}

# ============================================================================
# Module Exports
# ============================================================================
Export-ModuleMember -Function @(
    'Add-Path',
    'Remove-Path',
    'Get-Path',
    'Show-Path',
    'Set-Env',
    'Get-Env',
    'Remove-Env'
)
