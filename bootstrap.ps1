<#
.SYNOPSIS
    Sets up a Windows machine from scratch. Safe to re-run.

.DESCRIPTION
    Reads config.json, then runs the numbered step scripts in
    platforms/windows/steps in order. Every step is idempotent: re-running
    bootstrap on a configured machine should report all skips and change nothing.

.PARAMETER DryRun
    Print what would happen without touching the machine.

.PARAMETER Only
    Run only the steps whose filename matches one of these prefixes/names.
    e.g.  -Only 01,04   or   -Only packages

.PARAMETER Skip
    Inverse of -Only.

.PARAMETER Tags
    Override config.json's packages.tags for this run.
    e.g.  -Tags core,cli

.PARAMETER ProjectsRoot
    Where repos get cloned. Defaults to config.json's dev.root (D:\projects),
    which itself falls back to dev.fallbackRoot when that drive doesn't exist.
    e.g.  -ProjectsRoot 'E:\code'

.PARAMETER Repos
    Which repo sets from config.json's dev.repoSets to clone, or 'all' / 'none'.
    Defaults to dev.defaultRepoSets.
    e.g.  -Repos Personal,SayWhatTech

.EXAMPLE
    .\bootstrap.ps1 -DryRun
.EXAMPLE
    .\bootstrap.ps1 -Only packages -Tags core,cli
.EXAMPLE
    .\bootstrap.ps1 -ProjectsRoot 'C:\dev' -Repos all
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string[]]$Only,
    [string[]]$Skip,
    [string[]]$Tags,
    [string]$ProjectsRoot,
    [string[]]$Repos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot

# --- platform dispatch --------------------------------------------------------
# Windows is the only implemented platform today. macOS/Linux get their own
# bootstrap.sh reading the same config.json + manifest/packages.json.
# $IsWindows only exists in PowerShell 6+; in Windows PowerShell 5.1 it's absent
# and StrictMode makes reading it fatal - so probe rather than reference it.
$onWindows = if (Test-Path Variable:IsWindows) { $IsWindows } else { $true }
if (-not $onWindows) {
    Write-Host 'This is the Windows entry point. On macOS/Linux run ./bootstrap.sh' -ForegroundColor Yellow
    exit 1
}

$Global:NM = [ordered]@{
    DryRun   = [bool]$DryRun
    RepoRoot = $RepoRoot
    Config   = $null
    Changed  = [System.Collections.Generic.List[string]]::new()
    Skipped  = [System.Collections.Generic.List[string]]::new()
    Failed   = [System.Collections.Generic.List[string]]::new()
}

. (Join-Path $RepoRoot 'platforms\windows\lib\common.ps1')

$config = Get-NMConfig
if ($Tags) {
    $config.packages.tags = $Tags
    Write-NMInfo "Package tags overridden: $($Tags -join ', ')"
}

# Stashed on $Global:NM so step 05 picks them up; it reads its own parameters
# first, so the step is still runnable standalone.
if ($ProjectsRoot) { $Global:NM.ProjectsRoot = $ProjectsRoot }
if ($Repos)        { $Global:NM.RepoSets     = $Repos }

# --- banner -------------------------------------------------------------------
Write-Host ''
Write-Host '  new-machine' -ForegroundColor White
Write-Host "  $([Environment]::OSVersion.VersionString) | PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host "  admin: $(if (Test-NMAdmin) { 'yes' } else { 'no  (steps needing elevation will be skipped with a note)' })" -ForegroundColor DarkGray
if ($DryRun) { Write-Host '  DRY RUN - nothing will be modified' -ForegroundColor DarkYellow }

# --- step selection -----------------------------------------------------------
$stepDir = Join-Path $RepoRoot 'platforms\windows\steps'
$steps = Get-ChildItem -Path $stepDir -Filter '*.ps1' | Sort-Object Name

function Test-StepMatch {
    param([string]$FileName, [string[]]$Patterns)
    foreach ($p in $Patterns) { if ($FileName -like "*$p*") { return $true } }
    return $false
}

if ($Only) { $steps = $steps | Where-Object { Test-StepMatch $_.BaseName $Only } }
if ($Skip) { $steps = $steps | Where-Object { -not (Test-StepMatch $_.BaseName $Skip) } }

if (-not $steps) { Write-NMWarn 'No steps matched.'; exit 1 }

# --- run ----------------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($step in $steps) {
    try {
        & $step.FullName
    } catch {
        Write-NMFail "step $($step.BaseName) aborted: $($_.Exception.Message)"
        Write-NMInfo  "continuing with the remaining steps"
    }
}

$stopwatch.Stop()

# --- summary ------------------------------------------------------------------
Write-Host ''
Write-Host '==> Summary' -ForegroundColor Cyan
Write-Host "    changed: $($Global:NM.Changed.Count)   unchanged: $($Global:NM.Skipped.Count)   failed: $($Global:NM.Failed.Count)   ($([int]$stopwatch.Elapsed.TotalSeconds)s)"

if ($Global:NM.Failed.Count) {
    Write-Host ''
    Write-Host '    Failures:' -ForegroundColor Red
    $Global:NM.Failed | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
}

Write-Host ''
Write-NMInfo 'Open a new terminal so PATH and profile changes take effect.'
Write-Host ''

exit ([int]($Global:NM.Failed.Count -gt 0))
