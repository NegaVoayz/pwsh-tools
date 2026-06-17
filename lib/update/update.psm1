# update/update.psm1 -- Auto-update package.
#
# Update-PwshTools pulls the latest from git without touching
# user-added modules (untracked files in lib/ are always safe).

$script:_RepoRoot = Split-Path $PSScriptRoot -Parent

<#
.SYNOPSIS
    Updates pwsh-tools from the git repository.
.DESCRIPTION
    Pulls the latest changes from the remote git repository and
    reloads all packages. User-added modules (untracked files in
    lib/) are never removed by git pull.
.PARAMETER Force
    Skip the confirmation prompt when uncommitted changes exist.
.EXAMPLE
    Update-PwshTools
    Update-PwshTools -Force
#>
function Update-PwshTools {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force
    )

    $repoRoot = $script:_RepoRoot

    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        Write-Error "pwsh-tools repo not found at '$repoRoot'. Is this a git clone?"
        return
    }

    Push-Location $repoRoot
    try {
        $status = git status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git status failed. Is git installed and on PATH?`n$status"
            return
        }

        $changed = @($status | Where-Object { $_ -match '^\s*[MADRCU]' })
        $untracked = @($status | Where-Object { $_ -match '^\?\?' })

        if ($changed.Count -gt 0) {
            Write-Warning "You have uncommitted changes to $($changed.Count) tracked file(s)."
            Write-Host "  Changed files:" -ForegroundColor DarkGray
            foreach ($line in $changed) {
                Write-Host "    $line" -ForegroundColor Yellow
            }
            Write-Host "  git pull may fail or merge. Consider committing or stashing first." -ForegroundColor DarkGray
            if (-not $Force) {
                $confirm = Read-Host "Continue anyway? (y/N)"
                if ($confirm -notmatch '^[yY]') {
                    Write-Host "  Update cancelled." -ForegroundColor DarkGray
                    return
                }
            }
        }

        if ($untracked.Count -gt 0) {
            Write-Host "  ($($untracked.Count) untracked file(s) in repo -- these will not be touched)" -ForegroundColor DarkGray
        }

        Write-Host "`n  Pulling latest changes..." -ForegroundColor Cyan
        $pullResult = git pull 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "git pull failed:`n$pullResult"
            return
        }

        Write-Host $pullResult

        if ($pullResult -match 'Already up to date') {
            Write-Host "  pwsh-tools is already up to date." -ForegroundColor Green
            return
        }

        Write-Host "`n  Reloading packages..." -ForegroundColor Cyan
        $profilePath = Join-Path $repoRoot 'profile.ps1'
        if (Test-Path $profilePath) {
            . $profilePath
        }
        Write-Host "  Update complete." -ForegroundColor Green

    } finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    Checks for pwsh-tools updates once per day.
.DESCRIPTION
    Called automatically on shell start (via the bootstrap init-hook
    system). Does a lightweight 'git fetch' once every 24 hours and
    prints a hint if updates are available. Does NOT auto-update.
#>
function Invoke-OnInit {
    $repoRoot = $script:_RepoRoot
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) { return }

    $dataDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pwsh-tools'
    $stampFile = Join-Path $dataDir 'last_update_check'
    $now = Get-Date

    # Only check once per day
    if (Test-Path $stampFile) {
        try {
            $lastCheck = [DateTime]::Parse((Get-Content $stampFile -Raw -ErrorAction Stop).Trim())
            if (($now - $lastCheck).TotalHours -lt 24) { return }
        } catch {
            # Corrupt stamp file — check now
        }
    }

    # Create data dir if needed (should already exist if bookmarks are used)
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force -ErrorAction SilentlyContinue | Out-Null
    }

    Push-Location $repoRoot
    try {
        $fetchResult = git fetch --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { return }

        $behind = git rev-list --count HEAD..@{u} 2>&1
        if ($LASTEXITCODE -ne 0) { return }

        if ([int]$behind -gt 0) {
            Write-Host "  pwsh-tools: $behind update(s) available — run 'Update-PwshTools' to update." -ForegroundColor Yellow
        }
    } catch {
        # Silently ignore — update check is best-effort
    } finally {
        Pop-Location
    }

    # Update timestamp
    try {
        Set-Content -Path $stampFile -Value $now.ToString('o') -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

Export-ModuleMember -Function @('Update-PwshTools', 'Invoke-OnInit')
