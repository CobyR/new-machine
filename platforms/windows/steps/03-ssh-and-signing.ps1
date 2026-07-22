<#
SSH key + agent + GitHub auth + commit signing.

Interactive by design: `gh auth login` opens a browser. Everything before that
is automatic, and every part is skipped cleanly if already done.

Every external command goes through Invoke-NMNative - `gh` and `ssh-keygen`
write informational text to stderr, which Windows PowerShell 5.1 would otherwise
promote into a terminating error.
#>

. (Join-Path $PSScriptRoot '..\lib\common.ps1')

$config = Get-NMConfig
Write-NMHeader 'SSH, GitHub auth, and commit signing'

$sshDir  = Join-Path $env:USERPROFILE '.ssh'
$keyPath = Join-Path $sshDir $config.ssh.keyName
$pubPath = "$keyPath.pub"

New-NMDirectory $sshDir

# --- key ----------------------------------------------------------------------
if (Test-Path $keyPath) {
    Write-NMSkip "SSH key exists ($($config.ssh.keyName))"
} elseif (-not (Test-NMCommand 'ssh-keygen')) {
    Write-NMFail 'ssh-keygen not found - install OpenSSH Client (Settings > Optional Features)'
} else {
    $keyType = $config.ssh.keyType
    $comment = $config.ssh.comment
    $kp      = $keyPath
    Invoke-NMAction -Description "generate $keyType key at $kp" -Action {
        # -N '' = no passphrase. Swap for a prompt if you want one; the agent
        # step below would then ask for it once per boot.
        $result = Invoke-NMNative -Command 'ssh-keygen' -Arguments @('-t', $keyType, '-C', $comment, '-f', $kp, '-N', '')
        if (-not $result.Success) { throw "ssh-keygen exited $($result.ExitCode): $($result.Output.Trim())" }
    } | Out-Null
}

# --- agent --------------------------------------------------------------------
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if (-not $agent) {
    Write-NMWarn 'ssh-agent service not present - skipping agent setup'
} elseif ($agent.StartType -eq 'Automatic' -and $agent.Status -eq 'Running') {
    Write-NMSkip 'ssh-agent running'
} elseif (-not (Test-NMAdmin)) {
    Write-NMWarn 'ssh-agent needs elevation to set to auto-start - re-run this step as admin'
} else {
    Invoke-NMAction -Description 'enable and start ssh-agent' -Action {
        Set-Service ssh-agent -StartupType Automatic
        Start-Service ssh-agent
    } | Out-Null
}

$agentRunning = (Get-Service ssh-agent -ErrorAction SilentlyContinue).Status -eq 'Running'

if ((Test-Path $keyPath) -and $agentRunning -and (Test-NMCommand 'ssh-add')) {
    $loaded      = (Invoke-NMNative -Command 'ssh-add' -Arguments @('-l')).Output
    $fpResult    = Invoke-NMNative -Command 'ssh-keygen' -Arguments @('-lf', $pubPath)
    $fingerprint = if ($fpResult.Success) { ($fpResult.Output.Trim() -split '\s+')[1] } else { '' }

    if ($fingerprint -and $loaded -match [regex]::Escape($fingerprint)) {
        Write-NMSkip 'key already in agent'
    } else {
        $kp = $keyPath
        Invoke-NMAction -Description 'add key to ssh-agent' -Action {
            $r = Invoke-NMNative -Command 'ssh-add' -Arguments @($kp)
            if (-not $r.Success) { throw "ssh-add exited $($r.ExitCode): $($r.Output.Trim())" }
        } | Out-Null
    }
}

# --- known_hosts --------------------------------------------------------------
$knownHosts = Join-Path $sshDir 'known_hosts'
$hasGitHub = (Test-Path $knownHosts) -and ((Get-Content $knownHosts -Raw) -match 'github\.com')
if ($hasGitHub) {
    Write-NMSkip 'github.com in known_hosts'
} elseif (-not (Test-NMCommand 'ssh-keyscan')) {
    Write-NMWarn 'ssh-keyscan not found - skipping known_hosts'
} else {
    $kh = $knownHosts
    Invoke-NMAction -Description 'add github.com to known_hosts' -Action {
        $r = Invoke-NMNative -Command 'ssh-keyscan' -Arguments @('-t', 'rsa,ecdsa,ed25519', 'github.com')
        # ssh-keyscan reports progress on stderr; keep only the host key lines.
        $keys = @($r.Output -split "`r?`n" | Where-Object { $_ -match '^github\.com\s' })
        if (-not $keys) { throw 'ssh-keyscan returned no host keys (no network?)' }
        Add-Content -Path $kh -Value $keys
    } | Out-Null
}

# --- GitHub auth --------------------------------------------------------------
$ghReady = $false
if (-not (Test-NMCommand 'gh')) {
    Write-NMWarn 'gh not on PATH yet - re-run this step in a new terminal'
} else {
    $status = Invoke-NMNative -Command 'gh' -Arguments @('auth', 'status')
    if ($status.Success) {
        Write-NMSkip 'gh authenticated'
        $ghReady = $true
    } elseif ($Global:NM.DryRun) {
        Write-Host '  ~ would: run gh auth login (interactive)' -ForegroundColor DarkYellow
    } else {
        Write-NMInfo 'launching `gh auth login` - follow the browser prompts'
        # Deliberately NOT through Invoke-NMNative: this one needs the real console.
        & gh auth login --git-protocol ssh --web
        if ($LASTEXITCODE -eq 0) { Write-NMOk 'gh authenticated'; $ghReady = $true }
        else { Write-NMFail 'gh auth login failed' }
    }
}

function Add-NMGitHubKey {
    <#
    Uploads $pubPath to GitHub as an auth or signing key, if not already there.

    `gh ssh-key list` takes no --type flag (only `add` does) and has no --json,
    so it returns every key as TSV with the type in the last column:

        <title>  <algo> <key material>  <created>  <id>  authentication

    Both filters matter. Dropping --type is what makes the call work at all;
    filtering by the type column is what makes the answer correct, because SSH
    signing reuses the authentication key - the same bytes appear under both
    types, so an unfiltered match would report the signing key as present the
    moment the auth key is registered, and never upload it.
    #>
    param(
        [ValidateSet('authentication', 'signing')][string]$KeyType,
        [string]$PublicKeyPath
    )
    $localKey = (Get-Content $PublicKeyPath -Raw).Split(' ')[1]
    $listing  = Invoke-NMNative -Command 'gh' -Arguments @('ssh-key', 'list')

    if (-not $listing.Success) {
        Write-NMWarn "can't read your GitHub SSH keys: $($listing.Output.Trim())"
        Write-NMInfo  'if that is a permissions error: gh auth refresh -s admin:public_key,admin:ssh_signing_key'
        return
    }

    $registered = @()
    foreach ($line in ($listing.Output -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        $cols = $line -split "`t"
        if ($cols.Count -lt 5) { continue }
        if ($cols[-1].Trim() -ne $KeyType) { continue }
        $registered += (($cols[1] -split ' ')[1])
    }

    if ($registered -contains $localKey) {
        Write-NMSkip "$KeyType key already on GitHub"
        return
    }

    $title = if ($KeyType -eq 'signing') { "$env:COMPUTERNAME (signing)" } else { $env:COMPUTERNAME }
    Invoke-NMAction -Description "upload $KeyType key to GitHub" -Action {
        $r = Invoke-NMNative -Command 'gh' -Arguments @('ssh-key', 'add', $PublicKeyPath, '--type', $KeyType, '--title', $title)
        if (-not $r.Success) { throw "gh ssh-key add exited $($r.ExitCode): $($r.Output.Trim())" }
    } | Out-Null
}

if ($ghReady -and $config.ssh.uploadToGitHub -and (Test-Path $pubPath) -and -not $Global:NM.DryRun) {
    Add-NMGitHubKey -KeyType 'authentication' -PublicKeyPath $pubPath
}

# --- commit signing -----------------------------------------------------------
switch ($config.signing.method) {

    'ssh' {
        # SSH signing: reuse the key we just made, no separate GPG keyring.
        if (-not (Test-Path $pubPath)) { Write-NMWarn 'no public key - skipping signing setup'; break }

        $allowed = Join-Path $sshDir 'allowed_signers'
        $entry   = "$($config.identity.email) namespaces=`"git`" $((Get-Content $pubPath -Raw).Trim())"
        if ((Test-Path $allowed) -and ((Get-Content $allowed -Raw) -match [regex]::Escape($entry))) {
            Write-NMSkip 'allowed_signers entry'
        } else {
            $al = $allowed; $en = $entry
            Invoke-NMAction -Description 'write ~/.ssh/allowed_signers' -Action {
                Add-Content -Path $al -Value $en
            } | Out-Null
        }

        $sign = if ($config.signing.signCommitsByDefault) { 'true' } else { 'false' }
        $gitSettings = [ordered]@{
            'gpg.format'                 = 'ssh'
            'user.signingkey'            = $pubPath
            'gpg.ssh.allowedSignersFile' = $allowed
            'commit.gpgsign'             = $sign
            'tag.gpgsign'                = $sign
        }
        # ~/.gitconfig.local, never --global: ~/.gitconfig is a symlink to the
        # tracked dotfile, so --global would commit this machine's absolute
        # paths into every other machine's config.
        foreach ($key in $gitSettings.Keys) {
            Set-NMGitLocal -Key $key -Value $gitSettings[$key]
        }

        # Register the signing key with GitHub so commits show "Verified".
        if ($ghReady -and -not $Global:NM.DryRun) {
            Add-NMGitHubKey -KeyType 'signing' -PublicKeyPath $pubPath
        }
    }

    'gpg' {
        if (-not (Test-NMCommand 'gpg')) {
            Write-NMWarn 'gpg not installed - add GnuPG.GnuPG to manifest/packages.json and re-run 01-packages'
            break
        }
        $keys = Invoke-NMNative -Command 'gpg' -Arguments @('--list-secret-keys', '--keyid-format=long', $config.identity.email)
        if (-not $keys.Success) {
            Write-NMInfo 'generating a GPG key is interactive; run:'
            Write-NMInfo "  gpg --full-generate-key    (RSA 4096, no expiry, $($config.identity.email))"
            Write-NMInfo '  then re-run this step to wire it into git and GitHub'
            break
        }
        $match = [regex]::Match($keys.Output, 'sec\s+\S+/(\S+)')
        if (-not $match.Success) { Write-NMWarn 'could not parse GPG key id'; break }
        $keyId = $match.Groups[1].Value

        $gpgSettings = [ordered]@{
            'gpg.format'      = 'openpgp'
            'user.signingkey' = $keyId
            'commit.gpgsign'  = $(if ($config.signing.signCommitsByDefault) { 'true' } else { 'false' })
        }
        foreach ($key in $gpgSettings.Keys) {
            Set-NMGitLocal -Key $key -Value $gpgSettings[$key]
        }
        Write-NMInfo "add this key to GitHub:  gpg --armor --export $keyId | gh gpg-key add -"
    }

    default { Write-NMSkip 'commit signing (method: none)' }
}
