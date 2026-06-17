# helpers.ps1 — Bookmark internal utilities.

# Returns the directory where bookmark data lives ($HOME\.pwsh-tools).
# Creates it if it doesn't exist.
function _Get-BookmarkDir {
    $dir = Join-Path $HOME '.pwsh-tools'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        Write-Verbose "Created bookmark directory: $dir"
    }
    return $dir
}

# Returns the full path to bookmarks.json.
function _Get-BookmarkFile {
    return Join-Path (_Get-BookmarkDir) 'bookmarks.json'
}

# System-noise env var patterns to exclude from snapshots.
$script:_NoisePatterns = @(
    'ALLUSERSPROFILE', 'APPDATA', 'Chocolatey*', 'CommonProgramFiles*',
    'CommonProgramW6432', 'COMPUTERNAME', 'ComSpec', 'DriverData',
    'HOMEDRIVE', 'HOMEPATH', 'LOCALAPPDATA', 'LOGONSERVER',
    'NUMBER_OF_PROCESSORS', 'OS', 'Path', 'PATHEXT', 'PROCESSOR_*',
    'ProgramData', 'ProgramFiles*', 'ProgramW6432', 'PSModulePath',
    'PUBLIC', 'SESSIONNAME', 'SystemDrive', 'SystemRoot',
    'TEMP', 'TMP', 'USERDOMAIN*', 'USERNAME', 'USERPROFILE',
    'windir', 'WSL*'
)

# Captures a filtered snapshot of current process env vars.
# Returns a hashtable suitable for JSON serialization.
function _Capture-EnvSnapshot {
    $snapshot = @{}
    $all = [Environment]::GetEnvironmentVariables('Process')
    foreach ($key in $all.Keys) {
        # Skip noise vars
        $skip = $false
        if ($key.StartsWith('_')) { $skip = $true }
        if (-not $skip) {
            foreach ($pat in $script:_NoisePatterns) {
                if ($key -like $pat) { $skip = $true; break }
            }
        }
        if (-not $skip) {
            $snapshot[$key] = [string]$all[$key]
        }
    }
    return $snapshot
}
