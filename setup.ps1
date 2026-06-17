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

# --- 4. Create custom.ps1 template if missing ---
$customPath = "$ScriptRoot\custom.ps1"
if (-not (Test-Path $customPath)) {
    @'
# custom.ps1 -- Your personal pwsh-tools settings.
# This file is sourced automatically every shell start (after packages load).
# Put your own env vars, aliases, prompts, and one-off setup here.
# It is gitignored -- never committed to the repo.

# Fix Unicode rendering in PowerShell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# Examples (uncomment and edit):
# $env:PWSH_TOOLS_QUIET = '1'                # Suppress startup hint
# Set-Env MY_VAR "value" -Permanent          # Persistent env var
# Set-Alias g git                             # Convenience alias
# oh-my-posh init pwsh | Invoke-Expression   # Prompt theme
'@ | Set-Content -Path $customPath -Encoding UTF8
    Write-Host "[+] Created custom.ps1 -- add your personal settings here: $customPath"
} else {
    Write-Host "[=] custom.ps1 already exists: $customPath"
}

# --- 5. Load tools into current session ---
Write-Host "`nLoading pwsh-tools..."
. "$ScriptRoot\profile.ps1"
Write-Host ""

Show-Manual
Write-Host ""
Write-Host "Setup complete -- you're ready to go!" -ForegroundColor Green
Write-Host "  Add your own env vars, aliases, and settings to:" -ForegroundColor DarkGray
Write-Host "  $customPath" -ForegroundColor Yellow
