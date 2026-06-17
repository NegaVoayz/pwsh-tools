# update/init.psm1 -- Init module for update package.
# Imported by bootstrap/init.ps1 on every shell start.
# Checks for pwsh-tools updates once per day via git fetch.

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $repoRoot '.git'))) { return }

$dataDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pwsh-tools'
$stampFile = Join-Path $dataDir 'last_update_check'
$now = Get-Date

# Only check once per day
if (Test-Path $stampFile) {
    try {
        $lastCheck = [DateTime]::Parse((Get-Content $stampFile -Raw -ErrorAction Stop).Trim())
        if (($now - $lastCheck).TotalHours -lt 24) { return }
    } catch { }
}

if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force -ErrorAction SilentlyContinue | Out-Null
}

Push-Location $repoRoot
$connected = $false
$behind = 0

try {
    $fetchResult = git fetch --quiet 2>&1
    if ($LASTEXITCODE -eq 0) {
        $connected = $true
        $behindResult = git rev-list --count 'HEAD..@{u}' 2>&1
        if ($LASTEXITCODE -eq 0) {
            $behind = [int]$behindResult
        }
    }
} catch {
    # Best-effort; ignore errors
} finally {
    Pop-Location
}

# Report status and set retry interval
if (-not $connected) {
    Write-Host "  pwsh-tools: unable to check for updates (retrying in 2h)." -ForegroundColor DarkGray
    # Set stamp 22h ago so next check is in ~2h instead of 24h
    $stampValue = $now.AddHours(-22)
} elseif ($behind -gt 0) {
    Write-Host "  pwsh-tools: $behind update(s) available -- run 'Update-PwshTools' to update." -ForegroundColor Yellow
    $stampValue = $now
} else {
    Write-Host "  pwsh-tools: up to date." -ForegroundColor Green
    $stampValue = $now
}

# Update timestamp
try {
    Set-Content -Path $stampFile -Value $stampValue.ToString('o') -Encoding UTF8 -ErrorAction SilentlyContinue
} catch { }
