# Shared PowerShell profile - linked to both PowerShell 7 and Windows PowerShell 5.
# Everything here degrades gracefully if a tool isn't installed yet, so this file
# is safe to link before step 01 has finished.

# --- editing ------------------------------------------------------------------
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    $psrlVersion = (Get-Module PSReadLine).Version

    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -EditMode Windows
    # Up/Down search history by what's already typed
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete

    # Windows PowerShell 5.1 ships PSReadLine 2.0, which has neither option.
    if ($psrlVersion -ge [version]'2.1.0') { Set-PSReadLineOption -PredictionSource History }
    if ($psrlVersion -ge [version]'2.2.0') { Set-PSReadLineOption -PredictionViewStyle ListView }
}

$env:EDITOR = 'code --wait'

# --- prompt -------------------------------------------------------------------
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $env:STARSHIP_CONFIG = Join-Path $env:USERPROFILE '.config\starship.toml'
    Invoke-Expression (&starship init powershell)
}

# --- tool init ----------------------------------------------------------------
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
if (Get-Command gh -ErrorAction SilentlyContinue) {
    # gh completion is slow to generate; cache it.
    $ghCompletion = Join-Path $env:LOCALAPPDATA 'gh-completion.ps1'
    if (-not (Test-Path $ghCompletion)) { gh completion -s powershell | Out-File $ghCompletion -Encoding utf8 }
    . $ghCompletion
}

# --- aliases ------------------------------------------------------------------
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ll { eza -l --group-directories-first --git @args }
    function la { eza -la --group-directories-first --git @args }
    function lt { eza --tree --level=2 --group-directories-first @args }
} else {
    function ll { Get-ChildItem @args }
    function la { Get-ChildItem -Force @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -ErrorAction SilentlyContinue
    function cat { bat --style=plain --paging=never @args }
}

function .. { Set-Location .. }
function ... { Set-Location ../.. }

# git
function g   { git @args }
function gs  { git status --short --branch }
function ga  { git add @args }
function gc  { git commit @args }
function gp  { git push @args }
function gl  { git pull @args }
function gd  { git diff @args }
function glg { git lg @args }
function lg  { lazygit }

# jump to the dev root from anywhere
function dev { Set-Location (Join-Path $env:USERPROFILE 'projects') }

function which { param([string]$Name) (Get-Command $Name -ErrorAction SilentlyContinue).Source }
function touch { param([string]$Path) if (-not (Test-Path $Path)) { New-Item -ItemType File -Path $Path | Out-Null } }

# Reload this profile after editing it
function reload { . $PROFILE }
# Edit it in place - resolves through the symlink to the repo copy.
# No ?? operator here: this file is also parsed by Windows PowerShell 5.1.
function editprofile {
    $item = Get-Item $PROFILE -ErrorAction SilentlyContinue
    $path = if ($item -and $item.Target) { $item.Target } else { $PROFILE }
    code $path
}
