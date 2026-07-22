<#
Links (or copies) everything in dotfiles/links.json into place.

Existing real files are backed up to <target>.bak-<timestamp> before being
replaced, so this is non-destructive on a machine that already has config.

  .\02-dotfiles.ps1            link repo -> machine
  .\02-dotfiles.ps1 -Export    pull 'copy'-mode files machine -> repo
#>
param([switch]$Export)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Write-NMHeader $(if ($Export) { 'Dotfiles (export: machine -> repo)' } else { 'Dotfiles' })

$links = (Get-Content (Join-Path $Global:NM.RepoRoot 'dotfiles\links.json') -Raw | ConvertFrom-Json).windows
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$plannedDirs = [System.Collections.Generic.HashSet[string]]::new()

function Test-NMSameContent {
    # Raw compare that tolerates missing/empty files (Get-Content on an empty
    # file returns $null, which Compare-Object refuses).
    param([string]$A, [string]$B)
    if (-not (Test-Path $A) -or -not (Test-Path $B)) { return $false }
    $ca = Get-Content $A -Raw -ErrorAction SilentlyContinue
    $cb = Get-Content $B -Raw -ErrorAction SilentlyContinue
    return ([string]$ca -eq [string]$cb)
}

function Get-NMLinkTarget {
    # .LinkType / .Target aren't present on every item shape; probe safely.
    param($Item)
    if (-not $Item) { return $null }
    if (-not $Item.PSObject.Properties['LinkType']) { return $null }
    if ($Item.LinkType -ne 'SymbolicLink') { return $null }
    if (-not $Item.PSObject.Properties['Target']) { return $null }
    return @($Item.Target)
}

# Symlinks need Developer Mode or elevation; find out once rather than per file.
$canSymlink = Test-NMAdmin
if (-not $canSymlink) {
    $devKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
    $canSymlink = [bool]($devKey -and $devKey.PSObject.Properties['AllowDevelopmentWithoutDevLicense'] `
                         -and $devKey.AllowDevelopmentWithoutDevLicense -eq 1)
}
if (-not $canSymlink) {
    Write-NMWarn 'no symlink privilege (not admin, Developer Mode off) - linking as copies instead'
    Write-NMInfo  'run 04-os-tweaks elevated to enable Developer Mode, then re-run this step'
}

foreach ($link in $links) {
    $source = Join-Path $Global:NM.RepoRoot ($link.source -replace '/', '\')
    $target = Expand-NMPath $link.target
    $label  = Split-Path $link.target -Leaf

    # ---- export mode: copy the machine's version back into the repo ----------
    if ($Export) {
        if ($link.mode -ne 'copy') { continue }
        if (-not (Test-Path $target)) { Write-NMSkip "$label (nothing on machine)"; continue }
        if (Test-NMSameContent $source $target) { Write-NMSkip "$label (identical)"; continue }

        $src = $source; $tgt = $target
        Invoke-NMAction -Description "export $label -> $($link.source)" -Action {
            New-Item -ItemType Directory -Path (Split-Path $src -Parent) -Force | Out-Null
            Copy-Item -Path $tgt -Destination $src -Force
        } | Out-Null
        continue
    }

    # ---- normal mode: repo -> machine ---------------------------------------
    if (-not (Test-Path $source)) { Write-NMWarn "$label - missing source $($link.source)"; continue }

    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path $targetDir) -and -not $plannedDirs.Contains($targetDir)) {
        # Windows Terminal's LocalState only exists once Terminal has run once.
        if ($targetDir -match 'WindowsTerminal') {
            Write-NMSkip "$label (Windows Terminal not installed/launched yet)"; continue
        }
        New-NMDirectory $targetDir
        # In a dry run nothing was actually created, so remember it - otherwise
        # two files sharing a directory each report creating it.
        $plannedDirs.Add($targetDir) | Out-Null
    }

    $existing   = Get-Item $target -Force -ErrorAction SilentlyContinue
    $linkTarget = Get-NMLinkTarget $existing

    # Already the symlink we want?
    if ($linkTarget -and ($linkTarget -contains $source)) { Write-NMSkip "$label (already linked)"; continue }
    # Already an identical copy?
    if ($existing -and -not $linkTarget -and $link.mode -eq 'copy' -and (Test-NMSameContent $source $target)) {
        Write-NMSkip "$label (identical)"; continue
    }

    $useLink  = ($link.mode -eq 'link') -and $canSymlink
    $src      = $source
    $tgt      = $target
    $isLink   = [bool]$linkTarget
    $hadFile  = [bool]$existing
    $backup   = "$target.bak-$stamp"

    Invoke-NMAction -Description "$(if ($useLink) { 'link' } else { 'copy' }) $($link.source) -> $target" -Action {
        if ($hadFile) {
            if ($isLink) { Remove-Item $tgt -Force }
            else         { Move-Item $tgt $backup -Force }
        }
        if ($useLink) { New-Item -ItemType SymbolicLink -Path $tgt -Target $src -Force | Out-Null }
        else          { Copy-Item -Path $src -Destination $tgt -Force }
    } | Out-Null
}

if ($Export) { return }

# --- machine-local git identity ----------------------------------------------
# The tracked .gitconfig includes ~/.gitconfig.local; identity lives there so
# the shared dotfile stays machine-agnostic.
$config = Get-NMConfig
$localGitConfig = Get-NMGitLocalPath

# Set the two identity keys individually rather than rewriting the file. This
# step does not own ~/.gitconfig.local: step 03 writes the signing settings
# there and step 04 writes core.longpaths. Overwriting wholesale wiped them on
# every run, and `-Only 02` left signing broken until step 03 ran again.
if (-not (Test-Path $localGitConfig)) {
    $p = $localGitConfig
    Invoke-NMAction -Description 'create ~/.gitconfig.local' -Action {
        Set-Content -Path $p -Value '# Generated by new-machine bootstrap. Machine-specific; not tracked.' -Encoding utf8
    } | Out-Null
}

Set-NMGitLocal -Key 'user.name'  -Value $config.identity.name
Set-NMGitLocal -Key 'user.email' -Value $config.identity.email
