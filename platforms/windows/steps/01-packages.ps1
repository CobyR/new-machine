# Installs everything in manifest/packages.json matching config.packages.tags,
# then VS Code extensions from manifest/vscode-extensions.txt.

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig
Write-NMHeader "Packages  [tags: $($config.packages.tags -join ', ')]"

if (-not (Test-NMCommand 'winget')) {
    Write-NMFail 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
    return
}

$manifest = Get-Content (Join-Path $Global:NM.RepoRoot 'manifest\packages.json') -Raw | ConvertFrom-Json
$wanted   = $config.packages.tags

$selected = @($manifest.packages | Where-Object {
    $_.winget -and ($_.tags | Where-Object { $wanted -contains $_ })
})

Write-NMInfo "$($selected.Count) package(s) selected"

# One `winget list` beats one probe per package - it's a slow command.
$installedIds = @{}
if (-not $Global:NM.DryRun) {
    $listing = Invoke-NMNative -Command 'winget' -Arguments @('list', '--accept-source-agreements')
    if ($listing.Success) {
        foreach ($pkg in $selected) {
            if ($listing.Output -match [regex]::Escape($pkg.winget)) { $installedIds[$pkg.winget] = $true }
        }
    } else {
        Write-NMWarn "couldn't enumerate installed packages; falling back to per-package checks"
    }
}

foreach ($pkg in $selected) {
    $already = $installedIds.ContainsKey($pkg.winget) -or ($pkg.check -and (Test-NMCommand $pkg.check))
    if ($already) {
        Write-NMSkip "$($pkg.name)"
        continue
    }

    # Capture into locals: the scriptblock below runs in Invoke-NMAction's scope.
    $id    = $pkg.winget
    $label = $pkg.name

    Invoke-NMAction -Description "install $label ($id)" -Action {
        $result = Invoke-NMNative -Command 'winget' -Arguments @(
            'install', '--id', $id, '--exact',
            '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--disable-interactivity'
        )
        # 0x8A15002B = "no applicable upgrade / already installed" - not a failure.
        if (-not $result.Success -and $result.Output -notmatch '0x8A15002B') {
            throw "winget exited $($result.ExitCode)`n$($result.Output.Trim())"
        }
    } | Out-Null
}

Update-NMPath

# --- VS Code extensions -------------------------------------------------------
$extFile = Join-Path $Global:NM.RepoRoot 'manifest\vscode-extensions.txt'
if (-not (Test-Path $extFile)) { return }

if (-not (Test-NMCommand 'code')) {
    Write-NMWarn 'VS Code CLI not on PATH yet - re-run this step in a new terminal to install extensions'
    return
}

Write-NMHeader 'VS Code extensions'

$listResult = Invoke-NMNative -Command 'code' -Arguments @('--list-extensions')
$installed  = @($listResult.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$wantedExt = Get-Content $extFile |
    Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') } |
    ForEach-Object { $_.Trim() }

foreach ($ext in $wantedExt) {
    if ($installed -contains $ext) { Write-NMSkip $ext; continue }
    $extId = $ext
    Invoke-NMAction -Description "install extension $extId" -Action {
        $result = Invoke-NMNative -Command 'code' -Arguments @('--install-extension', $extId, '--force')
        if (-not $result.Success) { throw "code --install-extension exited $($result.ExitCode)" }
    } | Out-Null
}
