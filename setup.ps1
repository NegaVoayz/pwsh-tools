# setup.ps1 - One-time idempotent setup for pwsh-tools
# Safe to run multiple times.

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot

# --- 1. Create required directories ---
$dirs = @("$ScriptRoot\bin", "$ScriptRoot\lib")
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[+] Created directory: $dir"
    } else {
        Write-Host "[=] Directory exists: $dir"
    }
}

# --- 2. Add dot-source hook to profile ---
$profilePath = $PROFILE.CurrentUserCurrentHost
$hookComment = '# pwsh-tools hook'
$hookBody   = "if (Test-Path `"$ScriptRoot\profile.ps1`") { . `"$ScriptRoot\profile.ps1`" }"
$hookBlock  = "$hookComment`n$hookBody"

# Ensure profile directory exists
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not $Force) {
    $existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }
    if ($existing -match [regex]::Escape($hookComment)) {
        Write-Host "[=] Profile hook already present: $profilePath"
    } else {
        $newContent = $existing.TrimEnd() + "`r`n`r`n" + $hookBlock + "`r`n"
        Set-Content -Path $profilePath -Value $newContent -Encoding UTF8
        Write-Host "[+] Added hook to profile: $profilePath"
    }
} else {
    # Force: always append regardless
    $existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }
    $newContent = $existing.TrimEnd() + "`r`n`r`n" + $hookBlock + "`r`n"
    Set-Content -Path $profilePath -Value $newContent -Encoding UTF8
    Write-Host "[+] Force-added hook to profile: $profilePath"
}

# --- 3. Add C:\pwsh-tools\bin to persistent user PATH ---
$binPath = "$ScriptRoot\bin"
$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($null -eq $currentPath) { $currentPath = '' }
$entries = $currentPath -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() }

# Case-insensitive check with normalized comparison
$normalizedBin = $binPath.TrimEnd('\').Replace('/', '\')
$alreadyPresent = $entries | Where-Object {
    $_.TrimEnd('\').Replace('/', '\') -eq $normalizedBin
}

if (-not $alreadyPresent) {
    $entries += $binPath
    $newPath = ($entries -join ';').TrimEnd(';')
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    # Also update current process
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $parts = @($machinePath, $userPath) | Where-Object { $_ }
    $env:PATH = $parts -join ';'
    Write-Host "[+] Added to user PATH: $binPath"
} else {
    Write-Host "[=] Already in user PATH: $binPath"
}

# --- 4. Load tools into current session ---
Write-Host "`nLoading pwsh-tools..."
. "$ScriptRoot\profile.ps1"
Write-Host ""

Show-Manual
Write-Host "Setup complete — you're ready to go!" -ForegroundColor Green
