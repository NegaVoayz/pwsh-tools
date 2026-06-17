# update/update.psm1 -- Auto-update package.
#
# Update-PwshTools pulls the latest from git without touching
# user-added modules (untracked files in lib/ are always safe).

$script:_RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

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

    Write-Host "  Update downloaded. Restart your shell or run:" -ForegroundColor Green
    Write-Host "  . `"$repoRoot\profile.ps1`"" -ForegroundColor Yellow

    } finally {
        Pop-Location
    }
}

Export-ModuleMember -Function @('Update-PwshTools')
