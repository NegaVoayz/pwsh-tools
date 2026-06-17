# core.ps1 -- Batch file rename command.

<#
.SYNOPSIS
    Batch-renames files with pattern-based transformations.
.DESCRIPTION
    Renames files using one or more composable transformations,
    applied in order: regex replace -> case conversion -> trim ->
    prefix -> suffix (before extension).

    Accepts pipeline input from Get-ChildItem. Supports -WhatIf
    for dry-run preview.
.PARAMETER Path
    File paths to rename. Accepts wildcards and pipeline input.
.PARAMETER Find
    Regex pattern to find in the filename.
.PARAMETER Replace
    Replacement text for regex matches. Supports $1, $2, etc. for capture groups.
.PARAMETER Prefix
    Text to prepend to each filename.
.PARAMETER Suffix
    Text to append before the file extension.
.PARAMETER Case
    Convert filename case to Upper or Lower.
.PARAMETER Trim
    Trim leading and trailing whitespace from filenames.
.PARAMETER Filter
    Only rename files matching this wildcard pattern (e.g., '*.txt').
    Applied before transformations.
.PARAMETER Recurse
    Recursively process files in subdirectories.
.EXAMPLE
    Rename-File -Find '\.txt$' -Replace '.log' *.txt
    Rename-File -Prefix 'backup_' -Filter '*.docx'
    Rename-File -Suffix '_v2' -Case Lower *.ps1
    Rename-File -Find '\s+' -Replace '_' -Recurse *.log
    Get-ChildItem *.jpg | Rename-File -Prefix 'IMG_'
    Rename-File -Find 'foo' -Replace 'bar' -WhatIf *.txt
#>
function Rename-File {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('PSPath')]
        [string[]]$Path,

        [string]$Find,
        [string]$Replace = '',
        [string]$Prefix,
        [string]$Suffix,
        [ValidateSet('Upper', 'Lower')]
        [string]$Case,
        [switch]$Trim,
        [string]$Filter = '*',
        [switch]$Recurse
    )

    begin {
        # Collect all paths for processing (resolve wildcards in end block)
        $paths = [System.Collections.Generic.List[string]]::new()

        # Validate that at least one transform is active
        $hasTransform = $Find -or $Prefix -or $Suffix -or $Case -or $Trim
    }

    process {
        foreach ($p in $Path) {
            $paths.Add($p)
        }
    }

    end {
        if ($paths.Count -eq 0) {
            Write-Warning "No paths specified."
            return
        }

        # Resolve paths to files
        $files = @()
        foreach ($p in $paths) {
            if ($Recurse -or (Test-Path $p -PathType Container)) {
                # Directory: get children (with -Recurse if requested)
                $params = @{ Path = $p; File = $true; ErrorAction = 'SilentlyContinue' }
                if ($Recurse) { $params['Recurse'] = $true }
                $children = @(Get-ChildItem @params)
                if ($children.Count -eq 0 -and -not (Test-Path $p -PathType Container)) {
                    # Not a directory -- treat as wildcard
                    $children = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue)
                }
                $files += $children
            } else {
                # Wildcard or explicit file
                $children = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue)
                $files += $children
            }
        }

        if ($files.Count -eq 0) {
            Write-Warning "No files matched the specified path(s)."
            return
        }

        # Filter by wildcard
        if ($Filter -ne '*') {
            $files = @($files | Where-Object { $_.Name -like $Filter })
            if ($files.Count -eq 0) {
                Write-Warning "No files matched filter '$Filter'."
                return
            }
        }

        if (-not $hasTransform) {
            Write-Warning "No transformation specified. Use -Find, -Prefix, -Suffix, -Case, or -Trim."
            return
        }

        # Process each file
        $renamed = 0
        $skipped = 0
        $results = @()

        foreach ($file in $files) {
            $oldFullPath = $file.FullName
            $oldName = $file.Name
            $parentDir = $file.DirectoryName

            $newName = _Transform-FileName -FileName $oldName -Find $Find -Replace $Replace `
                -Prefix $Prefix -Suffix $Suffix -Case $Case -Trim:$Trim

            if ($newName -eq $oldName) {
                Write-Verbose "Skipped (unchanged): $oldName"
                continue
            }

            $newFullPath = Join-Path $parentDir $newName

            # Check for target collision
            if ((Test-Path -LiteralPath $newFullPath -ErrorAction SilentlyContinue) -and
                $newFullPath -ne $oldFullPath) {
                Write-Warning "Skipped: target already exists: $newName"
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($oldFullPath, "Rename to $newName")) {
                try {
                    Rename-Item -LiteralPath $oldFullPath -NewName $newName -ErrorAction Stop
                    Write-Host "  $oldName -> $newName" -ForegroundColor Green
                    $renamed++
                    $results += [PSCustomObject]@{ OldName = $oldName; NewName = $newName }
                } catch {
                    Write-Error "Failed to rename '$oldName': $_"
                    $skipped++
                }
            } else {
                # -WhatIf: show both filenames in original colors
                Write-Host "  [WhatIf] $oldName -> $newName" -ForegroundColor DarkGray
            }
        }

        if ($renamed -gt 0 -or $skipped -gt 0 -or $WhatIfPreference) {
            if ($WhatIfPreference) {
                Write-Host "  ($($files.Count) file(s) would be renamed)" -ForegroundColor DarkGray
            } else {
                $msg = "  $renamed renamed"
                if ($skipped -gt 0) { $msg += ", $skipped skipped" }
                Write-Host $msg -ForegroundColor DarkGray
            }
        }

        if ($results.Count -gt 0) {
            return $results
        }
    }
}
