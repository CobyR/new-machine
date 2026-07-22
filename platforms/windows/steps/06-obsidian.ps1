<#
Registers your vault with Obsidian so it opens the right one on first launch.

WHAT THIS CAN AND CANNOT DO
  Can:    register the vault path in %APPDATA%\obsidian\obsidian.json, so
          Obsidian opens it instead of showing the "create or open" chooser.
  Cannot: turn on Obsidian Sync. Sync requires signing in to an Obsidian
          account (email + password, possibly 2FA) and picking a remote vault
          from a dialog. There is no CLI, config file, or API for it, and the
          credentials aren't ours to store. The step prints the remaining
          manual actions at the end.

Configured via the `obsidian` block in config.json. Skipped entirely when
`vaultPath` is null.
#>

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig

if (-not $config.PSObject.Properties['obsidian']) { return }
$obs = $config.obsidian

Write-NMHeader 'Obsidian'

if (-not $obs.vaultPath) {
    Write-NMSkip 'no vaultPath set in config.json (nothing to register)'
    Write-NMInfo  'set obsidian.vaultPath to your vault folder to have it registered automatically'
    return
}

$vault = Expand-NMPath $obs.vaultPath

# --- the vault folder itself --------------------------------------------------
if (Test-Path (Join-Path $vault '.obsidian')) {
    Write-NMSkip "vault exists ($vault)"
} elseif (Test-Path $vault) {
    Write-NMWarn "$vault exists but has no .obsidian folder - Obsidian will initialize it on first open"
} elseif ($obs.createIfMissing) {
    $v = $vault
    Invoke-NMAction -Description "create vault folder $v" -Action {
        New-Item -ItemType Directory -Path $v -Force | Out-Null
    } | Out-Null
} else {
    Write-NMWarn "$vault does not exist (set obsidian.createIfMissing to create it, or sync it down first)"
    Write-NMInfo  'registering the path anyway so Obsidian opens it once the folder appears'
}

# --- register it in obsidian.json ---------------------------------------------
# Obsidian keeps its known vaults in a single JSON file keyed by a random id.
# Adding an entry is what makes Obsidian open this vault rather than prompting.
$obsidianDir  = Join-Path $env:APPDATA 'obsidian'
$obsidianJson = Join-Path $obsidianDir 'obsidian.json'

$existing = $null
if (Test-Path $obsidianJson) {
    try { $existing = Get-Content $obsidianJson -Raw | ConvertFrom-Json }
    catch { Write-NMWarn "obsidian.json is not valid JSON - leaving it alone"; return }
}

# Already registered? Compare resolved paths, not raw strings.
$alreadyRegistered = $false
if ($existing -and $existing.PSObject.Properties['vaults']) {
    foreach ($entry in $existing.vaults.PSObject.Properties) {
        $known = $entry.Value.path -replace '/', '\'
        if ($known.TrimEnd('\') -ieq $vault.TrimEnd('\')) { $alreadyRegistered = $true; break }
    }
}

if ($alreadyRegistered) {
    Write-NMSkip "vault already registered with Obsidian"
} else {
    $v = $vault; $dir = $obsidianDir; $jsonPath = $obsidianJson; $current = $existing

    Invoke-NMAction -Description "register $v with Obsidian" -Action {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        # Obsidian's vault keys are 16 hex chars. Any unique value works.
        $vaultId = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })

        if ($current) {
            $doc = $current
            if (-not $doc.PSObject.Properties['vaults']) {
                $doc | Add-Member -NotePropertyName 'vaults' -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            # Back up before touching a file Obsidian owns.
            Copy-Item $jsonPath "$jsonPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
        } else {
            $doc = [pscustomobject]@{ vaults = [pscustomobject]@{} }
        }

        $doc.vaults | Add-Member -NotePropertyName $vaultId -NotePropertyValue ([pscustomobject]@{
            path = $v
            ts   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            open = $true
        }) -Force

        Set-Content -Path $jsonPath -Value ($doc | ConvertTo-Json -Depth 6) -Encoding utf8
    } | Out-Null
}

# --- what has to be done by hand ----------------------------------------------
Write-NMInfo ''
Write-NMInfo 'Obsidian Sync cannot be automated - it needs an interactive login.'
Write-NMInfo 'Finish these in the app:'
Write-NMInfo '  1. Open Obsidian (it should land on your vault)'
Write-NMInfo '  2. Settings > Account > sign in to your Obsidian account'
Write-NMInfo '  3. Settings > Sync > Connect, then choose your remote vault'
Write-NMInfo '  4. Wait for the initial sync to finish before editing on this machine'

if ($obs.openAfterSetup -and -not $Global:NM.DryRun) {
    if (Test-NMCommand 'Obsidian') {
        Invoke-NMAction -Description 'launch Obsidian' -Action { Start-Process 'obsidian' } | Out-Null
    } else {
        Write-NMSkip 'Obsidian not on PATH - open it from the Start menu'
    }
}
