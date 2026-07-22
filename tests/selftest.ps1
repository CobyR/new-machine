<#
Self-test for the bootstrap library. Runs the REAL (non-dry-run) code paths
against a throwaway sandbox directory and an HKCU scratch key, so nothing on the
machine is touched. Run it after editing anything under platforms/ or manifest/:

    .\tests\selftest.ps1

Exit code is 0 when everything passes.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sandbox = Join-Path $env:TEMP "new-machine-selftest-$PID"
if (Test-Path $sandbox) { Remove-Item $sandbox -Recurse -Force }
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

$Global:NM = [ordered]@{
    DryRun = $false; RepoRoot = $repo; Config = $null
    Changed = [System.Collections.Generic.List[string]]::new()
    Skipped = [System.Collections.Generic.List[string]]::new()
    Failed  = [System.Collections.Generic.List[string]]::new()
}
. (Join-Path $repo 'platforms\windows\lib\common.ps1')

$pass = 0; $fail = 0
function Check($name, $condition) {
    if ($condition) { Write-Host "  PASS  $name" -ForegroundColor Green; $script:pass++ }
    else            { Write-Host "  FAIL  $name" -ForegroundColor Red;   $script:fail++ }
}

Write-Host "`n-- config loading --"
$cfg = Get-NMConfig
Check 'config.json parses'      ([bool]$cfg.identity.name -and [bool]$cfg.identity.email)
Check 'package tags present'    ($cfg.packages.tags.Count -gt 0)
Check 'nested config readable'  ($cfg.osTweaks.PSObject.Properties['darkMode'])
Check 'dev.root set'            ([bool]$cfg.dev.root)
Check 'dev.fallbackRoot set'    ([bool]$cfg.dev.fallbackRoot)

Write-Host "`n-- all JSON files parse --"
foreach ($j in (Get-ChildItem $repo -Recurse -Include *.json -File | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
    try { Get-Content $j.FullName -Raw | ConvertFrom-Json | Out-Null; Check "parses: $($j.Name)" $true }
    catch { Check "parses: $($j.Name) -- $($_.Exception.Message)" $false }
}

Write-Host "`n-- Expand-NMPath --"
Check '{HOME} expands'      ((Expand-NMPath '{HOME}/x') -eq (Join-Path $env:USERPROFILE 'x'))
Check '~ expands'           ((Expand-NMPath '~/.config/y') -eq (Join-Path $env:USERPROFILE '.config\y'))
Check 'forward slashes flip' ((Expand-NMPath '{REPO}/a/b') -eq "$repo\a\b")
Check '{DOCUMENTS} resolves' ((Expand-NMPath '{DOCUMENTS}') -eq [Environment]::GetFolderPath('MyDocuments'))

Write-Host "`n-- Invoke-NMAction (real execution) --"
$probe = Join-Path $sandbox 'made-by-action.txt'
$ok = Invoke-NMAction -Description 'create a file' -Action { Set-Content -Path $probe -Value 'hello' }
Check 'action ran and reported success' ($ok -and (Test-Path $probe))

$bad = Invoke-NMAction -Description 'action that throws' -Action { throw 'boom' }
Check 'throwing action returns false' (-not $bad)
Check 'failure recorded in summary' ($Global:NM.Failed.Count -eq 1)

Write-Host "`n-- Invoke-NMNative --"
$good = Invoke-NMNative -Command 'git' -Arguments @('--version')
Check 'exit code 0 on success' ($good.Success -and $good.Output -match 'git version')

# The exact shape that killed step 03: a native command writing to stderr.
$noisy = Invoke-NMNative -Command 'git' -Arguments @('rev-parse', '--verify', 'definitely-not-a-ref')
Check 'stderr does not throw'   ($null -ne $noisy)
Check 'nonzero exit -> Success false' (-not $noisy.Success)

Write-Host "`n-- Set-NMRegistryValue (HKCU sandbox key) --"
$key = 'HKCU:\Software\new-machine-selftest'
$changed1 = Set-NMRegistryValue -Path $key -Name 'Probe' -Value 1 -Description 'probe value'
Check 'reports changed on first write' $changed1
Check 'value actually written' ((Get-ItemProperty -Path $key -Name Probe).Probe -eq 1)
$changed2 = Set-NMRegistryValue -Path $key -Name 'Probe' -Value 1 -Description 'probe value'
Check 'idempotent: no change on rerun' (-not $changed2)
# The bug the first dry run hit: reading a value that does not exist on an existing key.
$changed3 = Set-NMRegistryValue -Path $key -Name 'Missing' -Value 7 -Description 'missing value'
Check 'missing value on existing key does not throw' $changed3
Remove-Item $key -Recurse -Force

Write-Host "`n-- symlink vs copy fallback --"
$src = Join-Path $sandbox 'source.txt'; Set-Content $src 'from repo'
$dst = Join-Path $sandbox 'dest.txt'
try {
    New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force -ErrorAction Stop | Out-Null
    $item = Get-Item $dst -Force
    Check 'symlink created and detected' ($item.LinkType -eq 'SymbolicLink')
    Check 'LinkType property present'    ([bool]$item.PSObject.Properties['LinkType'])
} catch {
    Write-Host "  INFO  symlink not permitted here; copy fallback is the path that runs" -ForegroundColor DarkYellow
    Copy-Item $src $dst -Force
    Check 'copy fallback works' ((Get-Content $dst) -eq 'from repo')
    $item = Get-Item $dst -Force
    Check 'non-link has no LinkType value' ($null -eq $item.LinkType -or $item.LinkType -eq '')
}

Write-Host "`n-- backup-before-overwrite --"
$existing = Join-Path $sandbox 'existing.txt'; Set-Content $existing 'original'
$backup = "$existing.bak-test"
Move-Item $existing $backup -Force
Copy-Item $src $existing -Force
Check 'original preserved in backup' ((Get-Content $backup) -eq 'original')
Check 'new content in place'         ((Get-Content $existing) -eq 'from repo')

Write-Host "`n-- Resolve-NMProjectsRoot --"
# Find a drive letter that definitely isn't mounted, to prove the fallback.
$used = (Get-PSDrive -PSProvider FileSystem).Name
$absent = ('QRSTUVWXYZ'.ToCharArray() | Where-Object { $used -notcontains "$_" } | Select-Object -First 1)

$fakeCfg = [pscustomobject]@{ root = "${absent}:/projects"; fallbackRoot = '{HOME}/projects' }
Check 'falls back when drive is absent' ((Resolve-NMProjectsRoot -Config $fakeCfg) -eq (Join-Path $env:USERPROFILE 'projects'))

$realCfg = [pscustomobject]@{ root = '{HOME}/projects'; fallbackRoot = '{HOME}/elsewhere' }
Check 'keeps root when drive exists'  ((Resolve-NMProjectsRoot -Config $realCfg) -eq (Join-Path $env:USERPROFILE 'projects'))
Check 'override beats config'         ((Resolve-NMProjectsRoot -Override 'E:\code' -Config $realCfg) -eq 'E:\code')
Check 'override expands tokens'       ((Resolve-NMProjectsRoot -Override '{HOME}/x' -Config $realCfg) -eq (Join-Path $env:USERPROFILE 'x'))

$noFallback = [pscustomobject]@{ root = "${absent}:/projects" }
Check 'missing fallbackRoot does not throw' ((Resolve-NMProjectsRoot -Config $noFallback) -eq "${absent}:\projects")

Write-Host "`n-- ConvertTo-NMCloneUrl --"
Check 'slug -> ssh'        ((ConvertTo-NMCloneUrl -Repo 'CobyR/foo') -eq 'git@github.com:CobyR/foo.git')
Check 'slug -> https'      ((ConvertTo-NMCloneUrl -Repo 'CobyR/foo' -Protocol 'https') -eq 'https://github.com/CobyR/foo.git')
Check 'trailing .git kept once' ((ConvertTo-NMCloneUrl -Repo 'CobyR/foo.git') -eq 'git@github.com:CobyR/foo.git')
Check 'full ssh url passes through'   ((ConvertTo-NMCloneUrl -Repo 'git@github.com:x/y') -eq 'git@github.com:x/y')
Check 'full https url passes through' ((ConvertTo-NMCloneUrl -Repo 'https://gitlab.com/x/y.git') -eq 'https://gitlab.com/x/y.git')

Write-Host "`n-- Get-NMRepoList (explicit sets, no network) --"
$explicitSet = [pscustomobject]@{ repos = @('a/one', 'a/two') }
Check 'explicit list returned as-is' ((Get-NMRepoList -Set $explicitSet -SetName 'T').Count -eq 2)

$badSet = [pscustomobject]@{ includeAll = $true }
Check 'includeAll without owner returns null' ($null -eq (Get-NMRepoList -Set $badSet -SetName 'T'))

Write-Host "`n-- repo sets in config --"
$sets = $cfg.dev.repoSets.PSObject.Properties.Name
Check 'at least one repo set defined' ($sets.Count -gt 0)
Check 'defaultRepoSets all exist' (-not ($cfg.dev.defaultRepoSets | Where-Object { $sets -notcontains $_ }))
Check "no set named 'all' or 'none'" (-not ($sets | Where-Object { $_ -in @('all', 'none') }))
foreach ($s in $sets) {
    $set = $cfg.dev.repoSets.$s
    $hasSource = ($set.PSObject.Properties['repos'] -and $set.repos) -or
                 ($set.PSObject.Properties['includeAll'] -and $set.includeAll)
    Check "set '$s' has repos or includeAll" $hasSource
    if ($set.PSObject.Properties['includeAll'] -and $set.includeAll) {
        Check "set '$s' includeAll has an owner" ([bool]$set.owner)
    }
}

Write-Host "`n-- run log --"
# Point the library at a sandbox repo so nothing lands in the real logs/.
$logRepo = Join-Path $sandbox 'logrepo'
New-Item -ItemType Directory -Path $logRepo -Force | Out-Null
Copy-Item (Join-Path $repo 'config.json') (Join-Path $logRepo 'config.json')

$realRoot = $Global:NM.RepoRoot
$realCfg  = $Global:NM.Config
try {
    $Global:NM.RepoRoot = $logRepo
    $Global:NM.Config = $null                   # force reload from the sandbox copy
    $sandboxCfg = Get-NMConfig
    $sandboxCfg.log.autoCommit = $false         # never touch git from a test

    $inv = [ordered]@{ dryRun = $false; steps = @('01-packages'); tags = @('core') }
    $res = [ordered]@{ durationSeconds = 12; changed = 2; skipped = 3; failed = 0 }

    Write-NMRunLog -Invocation $inv -Result $res
    $logFile = Join-Path $logRepo 'logs\runs.jsonl'
    Check 'log file created' (Test-Path $logFile)

    $lines = @(Get-Content $logFile)
    Check 'one line per run' ($lines.Count -eq 1)

    $rec = $lines[0] | ConvertFrom-Json
    Check 'records host'        ($rec.host -eq $env:COMPUTERNAME)
    Check 'records user'        ($rec.user -eq $env:USERNAME)
    Check 'records timestamp'   ($rec.timestamp -match '^\d{4}-\d{2}-\d{2}T')
    Check 'records os caption'  ([bool]$rec.os.caption)
    Check 'records powershell'  ([bool]$rec.powershell)
    Check 'records invocation'  ($rec.invocation.steps -contains '01-packages')
    Check 'records result'      ($rec.result.changed -eq 2 -and $rec.result.failed -eq 0)
    Check 'records machineId'   ([bool]$rec.machineId)

    # Appending must not rewrite earlier lines - that is the whole point of JSONL.
    Write-NMRunLog -Invocation $inv -Result $res
    $lines2 = @(Get-Content $logFile)
    Check 'append adds a line'      ($lines2.Count -eq 2)
    Check 'append preserves line 1' ($lines2[0] -eq $lines[0])

    # Dry run must not record.
    $Global:NM.DryRun = $true
    Write-NMRunLog -Invocation $inv -Result $res
    Check 'dry run writes nothing' ((Get-Content $logFile).Count -eq 2)
    $Global:NM.DryRun = $false

    # Disabling in config must be honoured.
    $sandboxCfg.log.enabled = $false
    Write-NMRunLog -Invocation $inv -Result $res
    Check 'log.enabled=false skips' ((Get-Content $logFile).Count -eq 2)

} finally {
    $Global:NM.RepoRoot = $realRoot
    $Global:NM.Config   = $realCfg
    $Global:NM.DryRun   = $false
}

Write-Host "`n-- SSH url rewrite covers every owner we clone from --"
# dotfiles/git/gitconfig rewrites HTTPS -> SSH per owner. Adding an org to
# repoSets without adding its rule would silently leave that org on HTTPS.
$gitconfig = Get-Content (Join-Path $repo 'dotfiles\git\gitconfig') -Raw
$owners = [System.Collections.Generic.HashSet[string]]::new()
foreach ($s in $cfg.dev.repoSets.PSObject.Properties.Name) {
    $set = $cfg.dev.repoSets.$s
    if ($set.PSObject.Properties['owner'] -and $set.owner) { $owners.Add($set.owner) | Out-Null }
    if ($set.PSObject.Properties['repos'] -and $set.repos) {
        foreach ($r in $set.repos) {
            if ($r -notmatch '^(git@|https://|ssh://)' -and $r -match '^([^/]+)/') { $owners.Add($Matches[1]) | Out-Null }
        }
    }
}
Check 'found owners to check' ($owners.Count -gt 0)
foreach ($o in $owners) {
    Check "insteadOf rule for '$o'" ($gitconfig -match [regex]::Escape("insteadOf = https://github.com/$o/"))
}
Check 'no blanket github.com rewrite' ($gitconfig -notmatch 'insteadOf = https://github\.com/\s*$')

Write-Host "`n-- manifest sanity --"
$manifest = Get-Content (Join-Path $repo 'manifest\packages.json') -Raw | ConvertFrom-Json
$dupes = $manifest.packages | Group-Object winget | Where-Object { $_.Count -gt 1 -and $_.Name }
Check 'no duplicate winget IDs' (-not $dupes)
Check 'every package has a name and tags' (-not ($manifest.packages | Where-Object { -not $_.name -or -not $_.tags }))
$links = (Get-Content (Join-Path $repo 'dotfiles\links.json') -Raw | ConvertFrom-Json).windows
$missing = $links | Where-Object { -not (Test-Path (Join-Path $repo ($_.source -replace '/', '\'))) }
Check 'every links.json source file exists' (-not $missing)
if ($missing) { $missing | ForEach-Object { Write-Host "        missing: $($_.source)" -ForegroundColor Red } }

Remove-Item $sandbox -Recurse -Force
Write-Host "`n== $pass passed, $fail failed ==" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit ([int]($fail -gt 0))
