<#
Creates the dev folder layout and clones the selected repo sets.

  .\05-dev-dirs.ps1
  .\05-dev-dirs.ps1 -ProjectsRoot 'E:\code'
  .\05-dev-dirs.ps1 -Repos Personal,SayWhatTech
  .\05-dev-dirs.ps1 -Repos all
  .\05-dev-dirs.ps1 -Repos none        # directories only, no clones
#>
param(
    [string]$ProjectsRoot,
    [string[]]$Repos
)

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig
$dev = $config.dev

# Precedence: this script's parameter > value bootstrap.ps1 stashed > config.json.
if (-not $ProjectsRoot -and $Global:NM.Contains('ProjectsRoot')) { $ProjectsRoot = $Global:NM.ProjectsRoot }
if (-not $Repos         -and $Global:NM.Contains('RepoSets'))     { $Repos = $Global:NM.RepoSets }

# --- resolve the projects root ------------------------------------------------
Write-NMHeader 'Dev directories'

$root = Resolve-NMProjectsRoot -Override $ProjectsRoot -Config $dev
Write-NMInfo "projects root: $root"

if (Test-Path $root) {
    Write-NMSkip $root
} else {
    $r = $root
    Invoke-NMAction -Description "create $r" -Action { New-Item -ItemType Directory -Path $r -Force | Out-Null } | Out-Null
}

foreach ($sub in $dev.subdirs) {
    $path = Join-Path $root $sub
    if (Test-Path $path) { Write-NMSkip $path; continue }
    $p = $path
    Invoke-NMAction -Description "create $p" -Action { New-Item -ItemType Directory -Path $p -Force | Out-Null } | Out-Null
}

# --- which repo sets? ---------------------------------------------------------
$available = @($dev.repoSets.PSObject.Properties.Name)

if (-not $Repos) { $Repos = @($dev.defaultRepoSets) }

if ($Repos.Count -eq 1 -and $Repos[0] -eq 'none') {
    Write-NMSkip 'repo cloning (-Repos none)'
    return
}
if ($Repos.Count -eq 1 -and $Repos[0] -eq 'all') { $Repos = $available }

$unknown = @($Repos | Where-Object { $available -notcontains $_ })
if ($unknown) {
    Write-NMFail "unknown repo set(s): $($unknown -join ', ')"
    Write-NMInfo  "available: $($available -join ', ')  (or 'all' / 'none')"
    return
}

if (-not (Test-NMCommand 'git')) {
    Write-NMWarn 'git not on PATH yet - re-run this step in a new terminal'
    return
}

# --- clone --------------------------------------------------------------------
foreach ($setName in $Repos) {
    $set = $dev.repoSets.$setName

    Write-NMHeader "Repos: $setName"

    $targetDir = if ($set.PSObject.Properties['path'] -and $set.path) { Join-Path $root $set.path } else { $root }
    # $root itself was handled above; only a set with its own `path` needs one.
    if ($targetDir -ne $root -and -not (Test-Path $targetDir)) {
        $td = $targetDir
        Invoke-NMAction -Description "create $td" -Action { New-Item -ItemType Directory -Path $td -Force | Out-Null } | Out-Null
    }

    $repos = Get-NMRepoList -Set $set -SetName $setName
    if ($null -eq $repos) { continue }          # resolution failed; already reported
    if (-not $repos)      { Write-NMWarn "$setName resolved to no repositories"; continue }

    Write-NMInfo "$($repos.Count) repo(s) -> $targetDir"

    foreach ($slug in $repos) {
        $url  = ConvertTo-NMCloneUrl -Repo $slug -Protocol $dev.cloneProtocol
        $name = ($slug -replace '\.git$', '') -split '[/:]' | Select-Object -Last 1
        $dest = Join-Path $targetDir $name

        if (Test-Path (Join-Path $dest '.git')) { Write-NMSkip "$name (already cloned)"; continue }
        if (Test-Path $dest) {
            Write-NMWarn "$name - $dest exists but isn't a git repo; leaving it alone"
            continue
        }

        $u = $url; $d = $dest
        Invoke-NMAction -Description "clone $u -> $d" -Action {
            $r = Invoke-NMNative -Command 'git' -Arguments @('clone', $u, $d)
            if (-not $r.Success) {
                throw "git clone exited $($r.ExitCode) (SSH key not authorized yet? run step 03): $($r.Output.Trim())"
            }
        } | Out-Null
    }
}
