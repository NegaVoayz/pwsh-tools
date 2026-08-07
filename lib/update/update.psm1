# update/update.psm1 -- Auto-update package.
#
# Save-PwshToolsLocal  -- commit tracked changes on the current branch
# Update-PwshTools     -- auto-commit, fetch origin/master, and merge
#
# User customizations live on the 'local' branch; upstream updates are
# pulled from origin/master and merged in automatically.

$script:_RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

<#
.SYNOPSIS
    Commits staged changes to tracked files on the current branch.
.DESCRIPTION
    Stages only changes to already-tracked files (git add -u) and
    commits them. Untracked files are never added. If there are no
    local changes, nothing is committed.
.PARAMETER Message
    Commit message to use. Defaults to "local: auto-save".
.EXAMPLE
    Save-PwshToolsLocal
    Save-PwshToolsLocal -Message "local: my settings tweaks"
#>
function Save-PwshToolsLocal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Message = 'local: auto-save'
    )

    $repoRoot = $script:_RepoRoot

    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        Write-Error "pwsh-tools repo not found at '$repoRoot'. Is this a git clone?"
        return @{ Success = $false; Committed = $false }
    }

    Push-Location $repoRoot
    try {
        # Stage changes to tracked files only (never untracked)
        $null = git add -u 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git add -u failed. Is git installed and on PATH?"
            return @{ Success = $false; Committed = $false }
        }

        # Check if there is anything staged
        git diff --cached --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  No local changes to save." -ForegroundColor DarkGray
            return @{ Success = $true; Committed = $false }
        }

        # Commit
        if ($PSCmdlet.ShouldProcess("Tracked files on current branch", "git commit -m '$Message'")) {
            $commitResult = git commit -m $Message 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "git commit failed:`n$commitResult"
                return @{ Success = $false; Committed = $false }
            }
            Write-Host "  Local changes saved: $Message" -ForegroundColor Green
        }

        return @{ Success = $true; Committed = $true; Message = $Message }
    } finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
    Updates pwsh-tools by merging upstream changes from origin/master.
.DESCRIPTION
    Automatically commits local changes (via Save-PwshToolsLocal),
    fetches origin/master, and merges it into the current branch.
    Handles merge conflicts gracefully by reporting affected files
    and abort instructions.
.PARAMETER Force
    Accepted for backward compatibility. In previous versions this
    suppressed the uncommitted-changes confirmation; auto-commit now
    handles that case.
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
        # --- Step 1: Auto-commit local changes ---
        Write-Host "`n  Checking for local changes..." -ForegroundColor Cyan
        $saveResult = Save-PwshToolsLocal
        if (-not $saveResult.Success) {
            Write-Error "Failed to save local changes. Update aborted."
            return
        }

        # --- Step 2: Fetch upstream ---
        Write-Host "  Fetching updates from origin..." -ForegroundColor Cyan
        $fetchResult = git fetch origin 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git fetch failed -- check your network connection.`n$fetchResult"
            return
        }

        # --- Step 3: Merge origin/master ---
        Write-Host "  Merging origin/master..." -ForegroundColor Cyan
        $mergeResult = git merge origin/master 2>&1

        if ($LASTEXITCODE -ne 0) {
            # Check for merge conflicts specifically
            $conflictFiles = git diff --name-only --diff-filter=U 2>&1
            if ($conflictFiles) {
                Write-Warning "Merge conflicts detected in $((@($conflictFiles) -split "`n" | Where-Object { $_ }).Count) file(s):"
                foreach ($file in (@($conflictFiles) -split "`n" | Where-Object { $_ })) {
                    Write-Host "    $file" -ForegroundColor Yellow
                }
                Write-Host ""
                Write-Warning "Your local changes have been auto-committed and the merge was attempted."
                Write-Host "  To resolve conflicts:" -ForegroundColor DarkGray
                Write-Host "    1. Edit the conflicted files (search for '<<<<<<<')" -ForegroundColor DarkGray
                Write-Host "    2. Stage resolved files: git add <file>" -ForegroundColor DarkGray
                Write-Host "    3. Complete the merge:  git commit" -ForegroundColor DarkGray
                Write-Host "  To abort the merge and go back: git merge --abort" -ForegroundColor DarkGray
                return
            } else {
                Write-Error "git merge failed:`n$mergeResult"
                return
            }
        }

        # --- Step 4: Report results ---
        Write-Host $mergeResult

        if ($mergeResult -match 'Already up to date') {
            Write-Host "  pwsh-tools is already up to date." -ForegroundColor Green
            return
        }

        Write-Host "  Update applied. Restart your shell or run:" -ForegroundColor Green
        Write-Host "  . `"$repoRoot\profile.ps1`"" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

Export-ModuleMember -Function @('Update-PwshTools', 'Save-PwshToolsLocal')
