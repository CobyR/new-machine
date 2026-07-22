# Shared helpers for every Windows step script.
# Dot-source this at the top of a step so the step can also be run standalone.

Set-StrictMode -Version Latest

# --- state shared with bootstrap.ps1 ------------------------------------------
# Steps read $Global:NM.DryRun / .RepoRoot / .Config rather than taking params,
# so a step is runnable on its own:  .\steps\04-os-tweaks.ps1
if (-not (Get-Variable -Name NM -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:NM = [ordered]@{
        DryRun   = $false
        RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        Config   = $null
        Changed  = [System.Collections.Generic.List[string]]::new()
        Skipped  = [System.Collections.Generic.List[string]]::new()
        Failed   = [System.Collections.Generic.List[string]]::new()
    }
}

function Get-NMConfig {
    <#
    .SYNOPSIS
    Loads config.json, overlaid with config.local.json when present.
    #>
    if ($Global:NM.Config) { return $Global:NM.Config }

    $base = Join-Path $Global:NM.RepoRoot 'config.json'
    if (-not (Test-Path $base)) { throw "config.json not found at $base" }
    $cfg = Get-Content $base -Raw | ConvertFrom-Json

    $local = Join-Path $Global:NM.RepoRoot 'config.local.json'
    if (Test-Path $local) {
        $overlay = Get-Content $local -Raw | ConvertFrom-Json
        $cfg = Merge-NMObject -Base $cfg -Overlay $overlay
        Write-NMInfo "Applied overrides from config.local.json"
    }

    $Global:NM.Config = $cfg
    return $cfg
}

function Merge-NMObject {
    # Shallow-recursive merge: overlay wins, objects merge, everything else replaces.
    param($Base, $Overlay)
    foreach ($prop in $Overlay.PSObject.Properties) {
        $existing = $Base.PSObject.Properties[$prop.Name]
        if ($existing -and $existing.Value -is [pscustomobject] -and $prop.Value -is [pscustomobject]) {
            Merge-NMObject -Base $existing.Value -Overlay $prop.Value | Out-Null
        } else {
            $Base | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
    return $Base
}

# --- output -------------------------------------------------------------------
function Write-NMHeader { param([string]$Text)
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}
function Write-NMInfo    { param([string]$Text) Write-Host "    $Text" -ForegroundColor Gray }
function Write-NMOk      { param([string]$Text) Write-Host "  + $Text" -ForegroundColor Green; $Global:NM.Changed.Add($Text) }
function Write-NMSkip    { param([string]$Text) Write-Host "  = $Text" -ForegroundColor DarkGray; $Global:NM.Skipped.Add($Text) }
function Write-NMWarn    { param([string]$Text) Write-Host "  ! $Text" -ForegroundColor Yellow }
function Write-NMFail    { param([string]$Text) Write-Host "  x $Text" -ForegroundColor Red; $Global:NM.Failed.Add($Text) }

function Invoke-NMAction {
    <#
    .SYNOPSIS
    Runs a scriptblock unless -DryRun, logging what would happen either way.
    Returns $true if the action ran (or would have), $false if it errored.
    #>
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($Global:NM.DryRun) {
        Write-Host "  ~ would: $Description" -ForegroundColor DarkYellow
        return $true
    }
    try {
        & $Action
        Write-NMOk $Description
        return $true
    } catch {
        Write-NMFail "$Description  --  $($_.Exception.Message)"
        return $false
    }
}

# --- environment --------------------------------------------------------------
function Test-NMAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-NMCommand {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-NMNative {
    <#
    .SYNOPSIS
    Runs an external executable and returns its exit code plus combined output.

    .DESCRIPTION
    Windows PowerShell 5.1 wraps a native command's stderr in ErrorRecords when
    you redirect it, which with $ErrorActionPreference='Stop' turns any tool that
    merely *warns* on stderr into a terminating error. (`gh ssh-key list` printing
    an HTTP 404 warning killed a whole step this way.) This isolates that: stderr
    is captured as text, and success is judged by exit code only.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Command @Arguments 2>&1 | Out-String
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
            Success  = ($LASTEXITCODE -eq 0)
        }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Update-NMPath {
    # Package managers extend PATH in the registry; pull it into this session so
    # later steps can actually invoke what earlier steps installed.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Expand-NMPath {
    <#
    .SYNOPSIS
    Expands the platform-neutral tokens used in config.json and links.json.
    Tokens ({HOME}, {DOCUMENTS}, ...) keep those files readable by a future
    bash bootstrap instead of baking in Windows-only environment syntax.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $map = @{
        '{HOME}'         = $env:USERPROFILE
        '{USERPROFILE}'  = $env:USERPROFILE
        '{APPDATA}'      = $env:APPDATA
        '{LOCALAPPDATA}' = $env:LOCALAPPDATA
        # Documents is often redirected to OneDrive - ask Windows, don't guess.
        '{DOCUMENTS}'    = [Environment]::GetFolderPath('MyDocuments')
        '{REPO}'         = $Global:NM.RepoRoot
    }
    foreach ($k in $map.Keys) { $Path = $Path.Replace($k, $map[$k]) }
    if ($Path.StartsWith('~')) { $Path = Join-Path $env:USERPROFILE $Path.Substring(1).TrimStart('/', '\') }
    return $Path -replace '/', '\'
}

function New-NMDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { return }
    if ($Global:NM.DryRun) { Write-Host "  ~ would: create $Path" -ForegroundColor DarkYellow; return }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

# --- projects root and repo sets ----------------------------------------------
function Resolve-NMProjectsRoot {
    <#
    .SYNOPSIS
    Decides where repos live: -ProjectsRoot, else config dev.root, else
    dev.fallbackRoot when dev.root names a drive this machine doesn't have.

    .DESCRIPTION
    Most of these machines have a D: drive, but not all - so a root on a missing
    drive silently falls back rather than creating D:\projects on the system
    drive or failing outright.
    #>
    param(
        [string]$Override,
        [Parameter(Mandatory)]$Config
    )

    if ($Override) { return (Expand-NMPath $Override) }

    $root = Expand-NMPath $Config.root
    $qualifier = Split-Path $root -Qualifier -ErrorAction SilentlyContinue

    if ($qualifier -and -not (Test-Path "$qualifier\")) {
        $hasFallback = $Config.PSObject.Properties['fallbackRoot'] -and $Config.fallbackRoot
        if ($hasFallback) {
            $fallback = Expand-NMPath $Config.fallbackRoot
            Write-NMWarn "drive $qualifier not present - falling back to $fallback"
            return $fallback
        }
        Write-NMWarn "drive $qualifier not present and no fallbackRoot configured"
    }
    return $root
}

function ConvertTo-NMCloneUrl {
    <#
    .SYNOPSIS
    Normalizes a repo entry to a clone URL. Accepts 'owner/name' shorthand or a
    full URL (which is passed through untouched).
    #>
    param(
        [Parameter(Mandatory)][string]$Repo,
        [string]$Protocol = 'ssh'
    )
    if ($Repo -match '^(git@|https://|ssh://)') { return $Repo }

    $slug = $Repo -replace '\.git$', ''
    if ($Protocol -eq 'https') { return "https://github.com/$slug.git" }
    return "git@github.com:$slug.git"
}

function Get-NMRepoList {
    <#
    .SYNOPSIS
    Expands a repo set to a list of 'owner/name' slugs.

    .DESCRIPTION
    A set either lists `repos` explicitly, or names an `owner` with includeAll,
    in which case the list is resolved through `gh repo list` at clone time -
    so a new repo in the org shows up without editing config.json.
    Returns $null (not an empty array) when resolution failed, so the caller can
    tell "couldn't ask" apart from "owner genuinely has no repos".
    #>
    param(
        [Parameter(Mandatory)]$Set,
        [Parameter(Mandatory)][string]$SetName
    )

    $explicit = @()
    if ($Set.PSObject.Properties['repos'] -and $Set.repos) { $explicit = @($Set.repos) }

    $wantsAll = $Set.PSObject.Properties['includeAll'] -and $Set.includeAll
    if (-not $wantsAll) { return $explicit }

    if (-not $Set.PSObject.Properties['owner'] -or -not $Set.owner) {
        Write-NMFail "$SetName sets includeAll but has no owner"
        return $null
    }
    if (-not (Test-NMCommand 'gh')) {
        Write-NMWarn "$SetName needs gh to list $($Set.owner)'s repos - re-run this step in a new terminal"
        return $null
    }

    Write-NMInfo "querying GitHub for $($Set.owner) repositories..."
    $result = Invoke-NMNative -Command 'gh' -Arguments @(
        'repo', 'list', $Set.owner, '--limit', '200', '--json', 'nameWithOwner,isArchived'
    )
    if (-not $result.Success) {
        Write-NMFail "gh repo list $($Set.owner) failed: $($result.Output.Trim())"
        return $null
    }

    try { $all = $result.Output | ConvertFrom-Json }
    catch { Write-NMFail "could not parse gh output for $($Set.owner)"; return $null }

    $skipArchived = $Set.PSObject.Properties['excludeArchived'] -and $Set.excludeArchived
    $exclude = @()
    if ($Set.PSObject.Properties['exclude'] -and $Set.exclude) { $exclude = @($Set.exclude) }

    $slugs = @($all |
        Where-Object { -not ($skipArchived -and $_.isArchived) } |
        ForEach-Object { $_.nameWithOwner } |
        Where-Object {
            $name = ($_ -split '/')[-1]
            ($exclude -notcontains $name) -and ($exclude -notcontains $_)
        })

    # An explicit `repos` list alongside includeAll adds to the resolved set.
    return @($explicit + $slugs | Select-Object -Unique)
}

function Set-NMRegistryValue {
    <#
    .SYNOPSIS
    Idempotent registry write. Skips silently when the value already matches.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'String', 'ExpandString', 'QWord')][string]$Type = 'DWord',
        [string]$Description
    )
    $label = if ($Description) { $Description } else { "$Path\$Name = $Value" }

    $current = $null
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        # Under StrictMode, .$Name on a key that lacks the value is a hard error,
        # so go through PSObject.Properties instead of dotting in.
        if ($item -and $item.PSObject.Properties[$Name]) { $current = $item.$Name }
    }
    if ($null -ne $current -and $current -eq $Value) {
        Write-NMSkip "$label (already set)"
        return $false
    }

    Invoke-NMAction -Description $label -Action {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    } | Out-Null
    return $true
}
