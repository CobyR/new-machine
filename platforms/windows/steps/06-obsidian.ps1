<#
Reminds you to finish Obsidian setup by hand. Deliberately does not touch
Obsidian's config.

An earlier version registered a vault path in %APPDATA%\obsidian\obsidian.json
so Obsidian would skip its vault chooser. That's the wrong default when the
vault comes from Sync: you want the chooser, so you can sign in and pull the
vault down from the remote rather than pointing Obsidian at a local folder that
may not exist yet. Obsidian now starts clean and prompts, and this step just
tells you what's left.

Turn the reminder off with `obsidian.remindAboutSync: false` in config.json.
#>

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig

if (-not $config.PSObject.Properties['obsidian']) { return }
if (-not $config.obsidian.remindAboutSync)        { return }

# Only worth mentioning if Obsidian is actually on the machine.
# The per-user Electron install lands in LOCALAPPDATA\Programs, not
# LOCALAPPDATA directly - missing that is why this step silently never fired.
$installed = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe')
    (Join-Path $env:LOCALAPPDATA 'Obsidian\Obsidian.exe')
    (Join-Path $env:ProgramFiles  'Obsidian\Obsidian.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-NMHeader 'Obsidian'

if (-not $installed) {
    Write-NMSkip 'Obsidian not installed yet - re-run this step after step 01'
    return
}

Write-NMInfo 'Installed. Obsidian will prompt for a vault on first launch -'
Write-NMInfo 'set it up from there:'
Write-NMInfo '  1. Open Obsidian and sign in (Settings > Account)'
Write-NMInfo '  2. Turn on Sync (Settings > Sync > Connect)'
Write-NMInfo '  3. Choose your remote vault and let the first sync finish'
Write-NMInfo '     before editing anything on this machine'
