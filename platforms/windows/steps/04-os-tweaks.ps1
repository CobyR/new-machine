<#
Windows settings, driven entirely by config.osTweaks - flip a flag to false and
the tweak is skipped. Each tweak declares whether it needs elevation; without
admin those are reported and skipped rather than failing the run.
#>

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig
$t = $config.osTweaks
Write-NMHeader 'Windows settings'

$isAdmin = Test-NMAdmin

$advanced    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

$tweaks = @(
    @{ Enabled = $t.showFileExtensions;      Admin = $false; Desc = 'show file extensions'
       Path = $advanced;    Name = 'HideFileExt';           Value = 0 }

    @{ Enabled = $t.showHiddenFiles;         Admin = $false; Desc = 'show hidden files'
       Path = $advanced;    Name = 'Hidden';                Value = 1 }

    @{ Enabled = $t.explorerLaunchToThisPC;  Admin = $false; Desc = 'Explorer opens to This PC'
       Path = $advanced;    Name = 'LaunchTo';              Value = 1 }

    @{ Enabled = $t.darkMode;                Admin = $false; Desc = 'dark mode (apps)'
       Path = $personalize; Name = 'AppsUseLightTheme';     Value = 0 }

    @{ Enabled = $t.darkMode;                Admin = $false; Desc = 'dark mode (system)'
       Path = $personalize; Name = 'SystemUsesLightTheme';  Value = 0 }

    @{ Enabled = $t.hideTaskbarSearchBox;    Admin = $false; Desc = 'hide taskbar search box'
       Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
       Name = 'SearchboxTaskbarMode';        Value = 0 }

    @{ Enabled = $t.disableBingInStartSearch; Admin = $false; Desc = 'disable Bing results in Start search'
       Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
       Name = 'DisableSearchBoxSuggestions'; Value = 1 }

    @{ Enabled = $t.enableLongPaths;         Admin = $true;  Desc = 'enable NTFS long paths (>260 chars)'
       Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
       Name = 'LongPathsEnabled';            Value = 1 }

    @{ Enabled = $t.enableDeveloperMode;     Admin = $true;  Desc = 'enable Developer Mode (symlinks without admin)'
       Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
       Name = 'AllowDevelopmentWithoutDevLicense'; Value = 1 }
)

$changed = $false
$deferred = @()

foreach ($tweak in $tweaks) {
    if (-not $tweak.Enabled) { Write-NMSkip "$($tweak.Desc) (disabled in config)"; continue }
    if ($tweak.Admin -and -not $isAdmin) { $deferred += $tweak.Desc; continue }

    if (Set-NMRegistryValue -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -Description $tweak.Desc) {
        $changed = $true
    }
}

if ($deferred) {
    Write-NMWarn "needs elevation, skipped: $($deferred -join '; ')"
    Write-NMInfo  'run in an admin terminal:  .\bootstrap.ps1 -Only os-tweaks'
}

# --- git long-path support (pairs with the NTFS setting above) ----------------
if ($t.enableLongPaths -and (Test-NMCommand 'git')) {
    # ~/.gitconfig.local, not --global - see Set-NMGitLocal.
    Set-NMGitLocal -Key 'core.longpaths' -Value 'true'
}

# --- apply --------------------------------------------------------------------
if ($changed -and $t.restartExplorer -and -not $Global:NM.DryRun) {
    Invoke-NMAction -Description 'restart Explorer to apply settings' -Action {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        # Windows relaunches Explorer automatically; give it a moment either way.
        Start-Sleep -Seconds 2
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
    } | Out-Null
} elseif ($changed) {
    Write-NMInfo 'sign out and back in (or restart Explorer) to apply'
}
