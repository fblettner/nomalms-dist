# nomalms for Windows: install and upgrade Nomana products on a customer's server.
#
# The server is enrolled once with a code from the NomaLMS portal. After that,
# each git clone / pull of a product gets a one-hour, read-only GitHub token
# from NomaLMS, as long as the customer's licence for that product is valid.
#
#   nomalms enroll <code> [--url https://...]   register this server (once)
#   nomalms status                              products, licences, installs
#   nomalms install <product> [folder]          clone a product
#   nomalms adopt <folder>                      switch an existing clone to nomalms
#   nomalms upgrade [product|folder]            git pull (all installs if none given)
#   nomalms license <product>                   print the licence key
#   nomalms self-update                         update this tool
#
# Needs: Git for Windows, Windows PowerShell 5.1 or later. The server token is
# kept in %APPDATA%\nomalms\config, encrypted for this Windows user (DPAPI).

# Not 'Stop': Windows PowerShell 5.1 would turn anything git writes to stderr into a failure.
$ErrorActionPreference = 'Continue'
$Version = '1.0.0'
$DefaultUrl = 'https://nomalms.nomana-it.fr'
$ConfDir = if ($env:NOMALMS_HOME) { $env:NOMALMS_HOME } else { Join-Path $env:APPDATA 'nomalms' }
$ConfFile = Join-Path $ConfDir 'config'
$InstallsFile = Join-Path $ConfDir 'installs'
$Self = $MyInvocation.MyCommand.Path
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Die([string]$Message) { [Console]::Error.WriteLine("nomalms: $Message"); exit 1 }
function Need([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { Die "'$Name' is required but not installed" } }

function Conf-Get([string]$Key) {
    if (-not (Test-Path $ConfFile)) { return '' }
    foreach ($line in Get-Content $ConfFile) { if ($line.StartsWith("$Key=")) { return $line.Substring($Key.Length + 1) } }
    return ''
}

function Service-Url {
    $url = if ($env:NOMALMS_URL) { $env:NOMALMS_URL } else { Conf-Get 'url' }
    if (-not $url) { $url = $DefaultUrl }
    return $url.TrimEnd('/')
}

# The token is stored encrypted for the current Windows user.
function Protect([string]$Plain) { ConvertFrom-SecureString (ConvertTo-SecureString $Plain -AsPlainText -Force) }
function Unprotect([string]$Stored) {
    $secure = ConvertTo-SecureString $Stored -ErrorAction Stop
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-Token {
    $stored = Conf-Get 'token_dpapi'
    if (-not $stored) { return '' }
    try { return Unprotect $stored } catch { Die "the saved server token cannot be read by this Windows user: enrol again (nomalms enroll <code>)" }
}

function Require-Token {
    $token = Get-Token
    if (-not $token) { Die "this server is not enrolled. In the portal: Repository access > Add a server, then: nomalms enroll <code>" }
    return $token
}

# Api METHOD PATH [TOKEN] [JSON BODY] -> the answer as text. On an error: the service's message.
# -Quiet: return $null instead of exiting (used by the git helper).
function Api([string]$Method, [string]$Path, [string]$Token = '', [string]$Body = '', [switch]$Quiet) {
    $headers = @{ 'X-Nomalms-Version' = $Version }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{ Uri = "$(Service-Url)$Path"; Method = $Method; Headers = $headers; UseBasicParsing = $true }
    if ($Body) { $params['Body'] = $Body; $params['ContentType'] = 'application/json' }
    try {
        return (Invoke-WebRequest @params -ErrorAction Stop).Content
    } catch {
        $detail = ''
        $text = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $text = $_.ErrorDetails.Message }
        elseif ($_.Exception.Response -and ($_.Exception.Response -is [Net.HttpWebResponse])) {
            try {
                $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $text = $reader.ReadToEnd()
            } catch {}
        }
        if ($text) { try { $detail = (ConvertFrom-Json $text).detail } catch {} }
        $message = if ($detail) { "$detail" } elseif ($_.Exception.Response) { "the service answered $([int]$_.Exception.Response.StatusCode)" } else { "cannot reach $(Service-Url): $($_.Exception.Message)" }
        [Console]::Error.WriteLine("nomalms: $message")
        if ($Quiet) { return $null }
        exit 1
    }
}

function Clean([string]$Value, [string]$Allowed) { return ($Value -replace "[^$Allowed]", '') }

# ── Commands ──────────────────────────────────────────────────────────────

function Cmd-Enroll($Arguments) {
    $code = ''; $url = ''
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = [string]$Arguments[$i]
        if ($a -eq '--url') { $i++; $url = [string]$Arguments[$i] }
        elseif ($a.StartsWith('--url=')) { $url = $a.Substring(6) }
        else { $code = $a }
    }
    if (-not $code) { Die 'usage: nomalms enroll <code> [--url https://...]' }
    if ($url) { $env:NOMALMS_URL = $url }
    $code = Clean $code 'A-Za-z0-9-'
    $hostName = Clean $env:COMPUTERNAME 'A-Za-z0-9._-'
    $answer = Api 'POST' '/api/server/enroll?format=text' '' "{`"code`":`"$code`",`"hostname`":`"$hostName`",`"version`":`"$Version`"}"
    $values = @{}
    foreach ($line in ($answer -split "`n")) { $k, $v = $line -split '=', 2; if ($k) { $values[$k] = $v } }
    if (-not $values['token']) { Die 'unexpected answer from the service' }
    New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null
    Set-Content -Path $ConfFile -Encoding ASCII -Value @("url=$(Service-Url)", "token_dpapi=$(Protect $values['token'])")
    Write-Output "Enrolled as '$($values['server'])' for $($values['customer'])."
    Write-Output 'Next: nomalms status'
}

# Products as objects: name, repo ("-" if none), valid, expires, label.
function Get-Status {
    $token = Require-Token
    $text = Api 'GET' '/api/server/status?format=text' $token
    $status = @{ server = ''; customer = ''; products = @() }
    foreach ($line in ($text -split "`n")) {
        if ($line.StartsWith('server=')) { $status.server = $line.Substring(7) }
        elseif ($line.StartsWith('customer=')) { $status.customer = $line.Substring(9) }
        elseif ($line.StartsWith("product`t")) {
            $f = $line -split "`t"
            $status.products += [pscustomobject]@{ name = $f[1]; repo = $f[2]; valid = ($f[3] -eq 'valid'); expires = $f[4]; label = $f[5] }
        }
    }
    return $status
}

function Get-Installs {
    if (-not (Test-Path $InstallsFile)) { return @() }
    return @(Get-Content $InstallsFile | Where-Object { $_ } | ForEach-Object { $f = $_ -split "`t", 2; [pscustomobject]@{ name = $f[0]; dir = $f[1] } })
}

function Describe([string]$Dir) { $d = (& git -C $Dir describe --tags --always 2>$null); return "$d" }

function Cmd-Status {
    $status = Get-Status
    Write-Output "Service : $(Service-Url)"
    Write-Output "Server  : $($status.server)"
    Write-Output "Customer: $($status.customer)"
    Write-Output ''
    Write-Output 'Products:'
    if ($status.products.Count -eq 0) { Write-Output '  (no licence)' }
    foreach ($p in $status.products) {
        $state = if ($p.valid) { 'licence valid' } else { 'NO VALID LICENCE' }
        if ($p.expires -ne '-') { $state = "$state until $($p.expires)" }
        $repo = if ($p.repo -eq '-') { '(not distributed through nomalms)' } else { $p.repo }
        Write-Output ("  {0,-16} {1}" -f $p.name, $p.label)
        Write-Output "    $repo, $state"
    }
    Write-Output ''
    Write-Output 'Installed here:'
    $installs = Get-Installs
    if ($installs.Count -eq 0) { Write-Output '  (nothing yet: nomalms install <product> [folder])' }
    foreach ($i in $installs) {
        if (Test-Path (Join-Path $i.dir '.git')) { Write-Output ("  {0,-16} {1}  ({2})" -f $i.name, $i.dir, (Describe $i.dir)) }
        else { Write-Output ("  {0,-16} {1}  (folder missing)" -f $i.name, $i.dir) }
    }
}

function Repo-Of($Status, [string]$Product) {
    $p = $Status.products | Where-Object { $_.name -eq $Product } | Select-Object -First 1
    if (-not $p) { Die "no licence for the product '$Product' (see: nomalms status)" }
    if ($p.repo -eq '-') { Die "'$Product' is not distributed through nomalms" }
    if (-not $p.valid) { Die "the licence for '$Product' has expired or been revoked" }
    return $p.repo
}

# What git is told, per clone. Git for Windows runs helpers through its own sh:
# forward slashes and single quotes keep a path with spaces in one piece.
function Helper-Value { return "!powershell -NoProfile -ExecutionPolicy Bypass -File '$($Self -replace '\\', '/')' git-credential" }

function Configure-Clone([string]$Dir) {
    & git -C $Dir config --unset-all credential.helper 2>$null
    & git -C $Dir config --add credential.helper ''
    & git -C $Dir config --add credential.helper (Helper-Value)
    & git -C $Dir config credential.useHttpPath true
}

function Record-Install([string]$Name, [string]$Dir) {
    New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null
    $lines = @(Get-Installs | Where-Object { $_.dir -ne $Dir } | ForEach-Object { "$($_.name)`t$($_.dir)" })
    $lines += "$Name`t$Dir"
    Set-Content -Path $InstallsFile -Encoding UTF8 -Value $lines
}

function Next-Step([string]$Name, [string]$Dir) {
    if ($Name -like 'nomaubl*') { Write-Output "Next, for each environment: nomaubl.cmd upgrade <env>   (in $Dir)" }
    else { Write-Output "Next: follow the product's README in $Dir to install the new version." }
}

function Cmd-Install($Arguments) {
    if ($Arguments.Count -lt 1) { Die 'usage: nomalms install <product> [folder]' }
    Need 'git'
    $product = [string]$Arguments[0]
    $repo = Repo-Of (Get-Status) $product
    $dir = if ($Arguments.Count -ge 2) { [string]$Arguments[1] } else { ($repo -split '/')[-1] }
    if (Test-Path $dir) { Die "'$dir' already exists. For an existing install: nomalms adopt $dir" }
    & git clone -c credential.helper= -c "credential.helper=$(Helper-Value)" -c credential.useHttpPath=true "https://github.com/$repo.git" $dir
    if ($LASTEXITCODE -ne 0) { Die 'the clone failed' }
    $dir = (Resolve-Path $dir).Path
    Configure-Clone $dir
    Record-Install $product $dir
    Write-Output "Installed $product in $dir."
    Write-Output "Licence key to enter in the product: nomalms license $product"
}

function Cmd-Adopt($Arguments) {
    if ($Arguments.Count -lt 1) { Die 'usage: nomalms adopt <folder>' }
    Need 'git'
    if (-not (Test-Path (Join-Path $Arguments[0] '.git'))) { Die "'$($Arguments[0])' is not a git clone" }
    $dir = (Resolve-Path $Arguments[0]).Path
    $oldUrl = "$(& git -C $dir remote get-url origin 2>$null)"
    if (-not $oldUrl) { Die "'$dir' has no remote named origin" }
    # https://github.com/owner/name(.git) or git@host-or-alias:owner/name(.git)
    $repo = $oldUrl -replace '\.git$', '' -replace '^https?://[^/]*/', '' -replace '^ssh://[^/]*/', '' -replace '^[^:/]*@[^:]*:', ''
    $status = Get-Status
    $p = $status.products | Where-Object { $_.repo -ieq $repo } | Select-Object -First 1
    if (-not $p) { Die "'$repo' is not one of your products distributed through nomalms (see: nomalms status)" }
    $oldHelpers = @(& git -C $dir config --local --get-all credential.helper 2>$null)
    $oldPath = "$(& git -C $dir config --local --get credential.useHttpPath 2>$null)"
    & git -C $dir remote set-url origin "https://github.com/$repo.git"
    Configure-Clone $dir
    & git -C $dir fetch --quiet origin
    if ($LASTEXITCODE -eq 0) {
        Record-Install $p.name $dir
        Write-Output "$dir now pulls $repo through nomalms."
        Write-Output 'The token or deploy key used before is no longer needed on this server.'
    } else {
        # Put everything back: the previous way keeps working.
        & git -C $dir remote set-url origin $oldUrl
        & git -C $dir config --unset-all credential.helper 2>$null
        foreach ($h in $oldHelpers) { if ($h) { & git -C $dir config --add credential.helper $h } }
        if ($oldPath) { & git -C $dir config credential.useHttpPath $oldPath } else { & git -C $dir config --unset credential.useHttpPath 2>$null }
        Die "could not fetch through nomalms; '$dir' was left as it was"
    }
}

function Upgrade-One($Install) {
    if (-not (Test-Path (Join-Path $Install.dir '.git'))) { [Console]::Error.WriteLine("nomalms: $($Install.dir) is missing, skipped"); return $false }
    $before = "$(& git -C $Install.dir rev-parse HEAD 2>$null)"
    Write-Output "== $($Install.name) ($($Install.dir))"
    & git -C $Install.dir pull --ff-only
    if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("nomalms: the pull failed in $($Install.dir)"); return $false }
    if ($before -eq "$(& git -C $Install.dir rev-parse HEAD)") { Write-Output "Already up to date ($(Describe $Install.dir))." }
    else { Write-Output "Now at $(Describe $Install.dir)."; Next-Step $Install.name $Install.dir }
    return $true
}

function Cmd-Upgrade($Arguments) {
    Need 'git'
    $installs = Get-Installs
    if ($installs.Count -eq 0) { Die 'nothing installed through nomalms yet (nomalms install, or nomalms adopt <folder>)' }
    if ($Arguments.Count -ge 1) {
        $target = [string]$Arguments[0]
        if (Test-Path $target) { $target = (Resolve-Path $target).Path }
        $installs = @($installs | Where-Object { $_.name -eq $target -or $_.dir -eq $target })
        if ($installs.Count -eq 0) { Die "'$($Arguments[0])' is not installed through nomalms (see: nomalms status)" }
    }
    $failed = 0
    foreach ($i in $installs) { $ok = $true; Upgrade-One $i | ForEach-Object { if ($_ -is [bool]) { $ok = $_ } else { Write-Output $_ } }; if (-not $ok) { $failed = 1 } }
    exit $failed
}

function Cmd-License($Arguments) {
    if ($Arguments.Count -lt 1) { Die 'usage: nomalms license <product>' }
    $token = Require-Token
    $key = Api 'GET' "/api/server/license?product=$(Clean ([string]$Arguments[0]) 'A-Za-z0-9._-')&format=text" $token
    Write-Output $key.Trim()
}

# Called by git: "git-credential get" with the request on standard input.
function Cmd-GitCredential($Arguments) {
    if ($Arguments.Count -lt 1 -or $Arguments[0] -ne 'get') { exit 0 }
    $hostName = ''; $path = ''
    while ($null -ne ($line = [Console]::In.ReadLine())) {
        if ($line.StartsWith('host=')) { $hostName = $line.Substring(5) }
        elseif ($line.StartsWith('path=')) { $path = $line.Substring(5) }
    }
    if ($hostName -ne 'github.com') { exit 0 }
    $token = Get-Token
    if (-not $token) { [Console]::Error.WriteLine('nomalms: this server is not enrolled (nomalms enroll <code>)'); exit 0 }
    $repo = Clean ($path -replace '\.git$', '') 'A-Za-z0-9._/-'
    $answer = Api 'POST' "/api/git-credential?format=git&repo=$repo" $token '' -Quiet
    if ($answer) { [Console]::Out.Write($answer) }
    exit 0
}

function Cmd-SelfUpdate {
    Need 'git'
    $here = Split-Path $Self
    if (-not (Test-Path (Join-Path $here '.git'))) { Die "$here is not a git clone: download the new version by hand" }
    & git -C $here pull --ff-only
}

function Usage {
    Get-Content $Self | Select-Object -Skip 1 -First 13 | ForEach-Object { $_ -replace '^# ?', '' }
}

$command = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })
switch ($command) {
    'enroll' { Cmd-Enroll $rest }
    'status' { Cmd-Status }
    'install' { Cmd-Install $rest }
    'adopt' { Cmd-Adopt $rest }
    { $_ -in 'upgrade', 'update' } { Cmd-Upgrade $rest }
    { $_ -in 'license', 'licence' } { Cmd-License $rest }
    'git-credential' { Cmd-GitCredential $rest }
    'self-update' { Cmd-SelfUpdate }
    { $_ -in 'version', '--version', '-v' } { Write-Output $Version }
    { $_ -in 'help', '--help', '-h' } { Usage }
    default { Die "unknown command '$command' (nomalms help)" }
}
