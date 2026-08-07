# pwsh-tools

A package-based PowerShell tool framework with Unix-like commands,
PATH management, and a self-documenting help system.

> **License:** [MIT](LICENSE)
## Quick Start

```powershell
# Clone anywhere — the path is resolved dynamically
git clone <repo-url> C:\pwsh-tools
cd C:\pwsh-tools

# One-time setup (idempotent, safe to re-run)
.\setup.ps1

# Restart your shell, or load immediately:
. .\profile.ps1
```

`setup.ps1` does four things:
- Creates a `local` branch off `master` for your personal customizations
- Adds a hook to your `$PROFILE` that calls `profile.ps1` on every shell start
- Adds `C:\pwsh-tools\bin` to your persistent user `PATH`
- Creates `custom.ps1` (gitignored) with defaults if it does not exist
- All operations are idempotent — run it twice, nothing breaks

## What You Get

On every new shell:
```
  pwsh-tools - Run 'Show-Manual' for available commands.
```

Run `Show-Manual` to see everything:

```
  pwsh-tools packages
  --------------------------------------------------

  [basics]    df, du, grep, head, ln, sudo, tail, touch, wc, which
  [env]       Get-Env, Remove-Env, Set-Env
  [man]       Show-Manual
  [path]      Add-Path, Get-Path, Remove-Path, Show-Path
```

### basics — Unix-like commands
```powershell
which git                  # locate a command
head log.txt -N 20         # first 20 lines
tail app.log -Follow       # follow a log
grep TODO -Recurse lib\    # recursive search
wc script.ps1              # count lines, words, chars
df                         # disk free space
du .\node_modules          # directory size
touch newfile.txt          # create or update timestamp
ln -Target C:\src -Link C:\link  # symlink
sudo whoami                # run elevated, capture output
"data" | sudo Out-File -Append C:\protected\file.txt  # pipe into sudo
```

### path — PATH management
```powershell
Add-Path C:\my-tools\bin -Permanent     # persist to registry
Remove-Path C:\old\tools -Scope User    # remove from user PATH
Get-Path -Scope Machine -Raw            # raw PATH string
Show-Path -Scope User -Check            # display with existence check
```

### env — environment variables
```powershell
Set-Env JAVA_HOME "C:\Java\jdk-17" -Permanent
Get-Env JAVA_HOME -Scope User
Remove-Env TEMP_DEBUG
```

All mutation functions support `-Permanent` (shorthand for `-Scope User`, persists via registry without admin) and explicit `-Scope Process/User/Machine`. `-WhatIf` is supported everywhere.

## User Customization

Two ways to add personal code that runs on every shell start:

### Inline (in `profile.ps1`)
```powershell
#region User Customization
Set-Alias -Name ll -Value Get-ChildItem
#endregion
```

### External file (`custom.ps1`, gitignored)
```powershell
# C:\pwsh-tools\custom.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
```

`custom.ps1` is sourced after the inline region, so it can override anything.
Opt out of the startup hint: `$env:PWSH_TOOLS_QUIET = '1'` in your custom file.

## Updating pwsh-tools

The framework lives on your `local` branch (created by `setup.ps1`).
Upstream changes are pulled from the `master` branch and merged automatically.

```powershell
# Pull the latest framework updates
Update-PwshTools
```

`Update-PwshTools` does three things:
1. Commits any local changes to tracked files via `Save-PwshToolsLocal`
2. Fetches the latest `origin/master`
3. Merges `origin/master` into your current branch

### Saving local changes

```powershell
# Commit your customizations manually
Save-PwshToolsLocal -Message "local: added my aliases"
```

`Save-PwshToolsLocal` stages changes to all tracked files (modifications,
deletions, renames) and commits them. Untracked files (like new modules
you are working on) are never added — add those manually with `git add`.

### Merge conflicts

If `Update-PwshTools` encounters a merge conflict, it will list the
conflicted files and pause. Resolve conflicts manually:

```powershell
# Edit conflicted files (search for <<<<<<<)
git add <resolved-file>
git commit

# Or abort the merge and go back:
git merge --abort
```

Your local changes are always committed before the merge, so you can
safely abort without losing work.

### Daily check

On every shell start, pwsh-tools checks whether `origin/master` has new
commits. If updates are available, you will see a yellow hint:

```
  pwsh-tools: N update(s) available -- run 'Update-PwshTools' to update.
```

## Adding a Package

Every package is a directory under `lib/` with a `<name>.psm1` entry point.
Sub-modules use `.ps1` (dot-sourced internally, never imported directly).

### Minimal single-file package

```
lib/mypkg/
└── mypkg.psm1       # functions + Export-ModuleMember
```

```powershell
# lib/mypkg/mypkg.psm1
<#
.SYNOPSIS
    Does something useful.
#>
function Invoke-Thing {
    param([string]$Name)
    Write-Host "Hello, $Name"
}

Export-ModuleMember -Function @('Invoke-Thing')
```

### Multi-file package with shared internals

```
lib/mypkg/
├── mypkg.psm1        # entry: dot-sources .ps1 files, exports public API
├── core.ps1          # main functions
└── helpers.ps1       # internal utilities (never exported)
```

```powershell
# lib/mypkg/mypkg.psm1
. "$PSScriptRoot\helpers.ps1"   # internal, shared
. "$PSScriptRoot\core.ps1"      # public functions

Export-ModuleMember -Function @('Invoke-Thing', 'Invoke-Other')
```

Rules:
- **Entry point**: `<package>/<package>.psm1` — discovered automatically by `loader.ps1`
- **Internal files**: use `.ps1` extension so `Export-ModuleMember` sees their functions
- **Help**: write standard PowerShell comment-based help (`<# .SYNOPSIS ... #>`) above each function — `Show-Manual` discovers it automatically
- **Exports**: only call `Export-ModuleMember` in the entry `.psm1` file

No registration, no manifests, no build step. Drop the directory in, restart, done.

## Design

```
C:\pwsh-tools\
├── setup.ps1            # one-time: hooks $PROFILE, adds bin\ to PATH
├── profile.ps1           # shell entry: loader → hint → user region → custom.ps1
├── loader.ps1            # imports lib/*/<name>.psm1 with error isolation
├── custom.ps1            # (gitignored) user's personal customizations
├── README.md
├── bin\                  # on PATH — put your own scripts here
└── lib\
    ├── path\             # PATH management package
    │   ├── path.psm1     #   entry, exports Add/Remove/Get/Show-Path
    │   ├── core.ps1      #   Add-Path, Remove-Path
    │   ├── view.ps1      #   Get-Path, Show-Path
    │   └── helpers.ps1   #   internal utilities (package-private)
    ├── env\              # env var management package
    │   └── env.psm1
    ├── man\              # help browser package
    │   └── man.psm1
    └── basics\           # Unix-like commands package
        ├── basics.psm1   #   entry, exports all 10 functions
        ├── disks.ps1     #   df, du
        ├── files.ps1     #   touch, ln
        ├── headtail.ps1  #   head, tail
        ├── grep.ps1      #   grep
        ├── sudo.ps1      #   sudo
        ├── wc.ps1        #   wc
        └── which.ps1     #   which
```

### Startup flow

```
PowerShell starts
  → $PROFILE runs
    → profile.ps1
      → loader.ps1 scans lib/*/<name>.psm1
        → Import-Module each package entry point
      → prints "pwsh-tools — Run 'Show-Manual' ..."
      → runs #region User Customization
      → dot-sources custom.ps1 (if exists)
```

### Constraints

- Every file ≤ 200 lines
- Every package contains exactly one "kind" of functions
- Every function body ≤ 80 lines
- Internal sub-module files use `.ps1`, not `.psm1`

## License

MIT — see [LICENSE](LICENSE).
