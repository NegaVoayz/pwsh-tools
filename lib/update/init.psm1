# update/init.psm1 -- Init module for update package.
# Imported by bootstrap/init.ps1 on every shell start.
# Checks for pwsh-tools updates once per day via git fetch.

$repoRoot = Split-Path $PSScriptRoot -Parent
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
try {
    git fetch --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return }

    $behind = git rev-list --count HEAD..@{u} 2>&1
    if ($LASTEXITCODE -ne 0) { return }

    if ([int]$behind -gt 0) {
        Write-Host "  pwsh-tools: $behind update(s) available -- run 'Update-PwshTools' to update." -ForegroundColor Yellow
    }
} catch { } finally {
    Pop-Location
}

try {
    Set-Content -Path $stampFile -Value $now.ToString('o') -Encoding UTF8 -ErrorAction SilentlyContinue
} catch { }
