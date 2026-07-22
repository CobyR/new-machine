<#
.SYNOPSIS
    Reads logs/runs.jsonl and prints it in a form you can actually scan.

.EXAMPLE
    .\tools\Show-RunLog.ps1                 # every run, newest first
.EXAMPLE
    .\tools\Show-RunLog.ps1 -ByMachine      # one row per machine, last run
.EXAMPLE
    .\tools\Show-RunLog.ps1 -Host DESKTOP-1 # just this machine
.EXAMPLE
    .\tools\Show-RunLog.ps1 -Detail         # full record incl. what changed
#>
[CmdletBinding()]
param(
    [string]$HostName,
    [switch]$ByMachine,
    [switch]$Detail,
    [int]$Last = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logPath = Join-Path $repo 'logs\runs.jsonl'

if (-not (Test-Path $logPath)) {
    Write-Host "No run log yet at logs/runs.jsonl - it is written the first time bootstrap.ps1 runs for real." -ForegroundColor Yellow
    return
}

$entries = @(
    Get-Content $logPath | Where-Object { $_.Trim() } | ForEach-Object {
        try { $_ | ConvertFrom-Json }
        catch { Write-Warning "skipping unparseable line: $($_.Exception.Message)" }
    }
)

if (-not $entries) { Write-Host 'Run log is empty.' -ForegroundColor Yellow; return }

if ($HostName) { $entries = @($entries | Where-Object { $_.host -eq $HostName }) }
if (-not $entries) { Write-Host "No runs recorded for host '$HostName'." -ForegroundColor Yellow; return }

# Newest first.
$entries = @($entries | Sort-Object { [datetime]$_.timestamp } -Descending)
if ($Last -gt 0) { $entries = @($entries | Select-Object -First $Last) }

function Format-Outcome {
    param($Entry)
    if ($Entry.result.failed -gt 0) { return "$($Entry.result.failed) failed" }
    if ($Entry.result.changed -gt 0) { return "$($Entry.result.changed) changed" }
    return 'no changes'
}

# --- one row per machine ------------------------------------------------------
if ($ByMachine) {
    Write-Host ''
    Write-Host 'Machines provisioned from this repo' -ForegroundColor Cyan
    # Group by machineId, not hostname: renaming a machine must not make it look
    # like a second one. Falls back to the hostname when machineId is absent
    # (CIM/registry unavailable on that run).
    $entries |
        Group-Object { if ($_.machineId) { $_.machineId } else { "host:$($_.host)" } } |
        ForEach-Object {
            $runs = @($_.Group | Sort-Object { [datetime]$_.timestamp } -Descending)
            $latest = $runs[0]

            # Surface renames rather than hiding them - the old name is how you
            # remember the machine.
            $names = @($runs | Select-Object -ExpandProperty host -Unique)
            $shown = $latest.host
            if ($names.Count -gt 1) {
                $former = @($names | Where-Object { $_ -ne $latest.host })
                $shown = "$($latest.host) (was $($former -join ', '))"
            }

            [pscustomobject]@{
                Host     = $shown
                Runs     = $runs.Count
                FirstRun = ([datetime]$runs[-1].timestamp).ToString('yyyy-MM-dd')
                LastRun  = ([datetime]$latest.timestamp).ToString('yyyy-MM-dd')
                OS       = if ($latest.os) { $latest.os.caption } else { '' }
                Model    = if ($latest.hardware) { "$($latest.hardware.manufacturer) $($latest.hardware.model)".Trim() } else { '' }
                Commit   = if ($latest.repo) { $latest.repo.commit } else { '' }
            }
        } |
        Sort-Object LastRun -Descending |
        Format-Table -AutoSize
    return
}

# --- full detail --------------------------------------------------------------
if ($Detail) {
    foreach ($e in $entries) {
        Write-Host ''
        Write-Host "$($e.localTime)  $($e.host)" -ForegroundColor Cyan
        Write-Host "  user       $($e.user)$(if ($e.elevated) { ' (elevated)' })"
        if ($e.os)       { Write-Host "  os         $($e.os.caption) build $($e.os.build)" }
        if ($e.hardware) { Write-Host "  hardware   $($e.hardware.manufacturer) $($e.hardware.model), $($e.hardware.cpu), $($e.hardware.ramGB) GB" }
        Write-Host "  powershell $($e.powershell)"
        if ($e.repo)     { Write-Host "  repo       $($e.repo.commit) on $($e.repo.branch)$(if ($e.repo.dirty) { ' (dirty)' })" }
        Write-Host "  steps      $($e.invocation.steps -join ', ')"
        if ($e.invocation.tags)         { Write-Host "  tags       $($e.invocation.tags -join ', ')" }
        if ($e.invocation.repos)        { Write-Host "  repo sets  $($e.invocation.repos -join ', ')" }
        if ($e.invocation.projectsRoot) { Write-Host "  root       $($e.invocation.projectsRoot)" }
        Write-Host "  result     $(Format-Outcome $e) in $($e.result.durationSeconds)s ($($e.result.skipped) unchanged)"

        if ($e.PSObject.Properties['changed'] -and $e.changed) {
            Write-Host '  changed:' -ForegroundColor DarkGray
            $e.changed | ForEach-Object { Write-Host "    + $_" -ForegroundColor DarkGray }
        }
        if ($e.PSObject.Properties['failures'] -and $e.failures) {
            Write-Host '  failures:' -ForegroundColor Red
            $e.failures | ForEach-Object { Write-Host "    x $_" -ForegroundColor Red }
        }
    }
    Write-Host ''
    return
}

# --- default: one line per run ------------------------------------------------
Write-Host ''
$entries | ForEach-Object {
    [pscustomobject]@{
        When    = ([datetime]$_.timestamp).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        Host    = $_.host
        User    = $_.user
        Commit  = if ($_.repo) { $_.repo.commit } else { '' }
        Steps   = $_.invocation.steps.Count
        Took    = "$($_.result.durationSeconds)s"
        Outcome = Format-Outcome $_
    }
} | Format-Table -AutoSize

# @() around the pipeline: with one entry Select-Object returns a scalar, and
# StrictMode makes .Count on it a hard error.
$hostCount = @($entries | Select-Object -ExpandProperty host -Unique).Count
Write-Host "  $($entries.Count) run(s) across $hostCount machine(s)" -ForegroundColor DarkGray
Write-Host ''
