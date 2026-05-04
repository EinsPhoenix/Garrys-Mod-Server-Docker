<#
.SYNOPSIS
    Management console for the TTT Garry's Mod Docker server.

.DESCRIPTION
    Interactive PowerShell menu. Self-elevates to Administrator.

    Menu:
        1) Start server   - launch Docker Desktop if needed, docker compose up,
                            open Windows Firewall ports
        2) Shutdown       - docker compose down + close firewall ports
        3) Close ports    - remove firewall rules only (server keeps running)
        4) Promote admin  - add a SteamID as superadmin via users.txt
        5) Change config  - edit common TTT cvars in cfg/server.cfg
        Q) Quit

    Run from any PowerShell prompt:
        powershell -ExecutionPolicy Bypass -File .\scripts\manage.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Self-elevate
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath)
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

# Constants
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ContainerName = 'garrysmod-server'

$FirewallRules = @(
    @{ Name = 'GMod TTT Docker - Game UDP';   Protocol = 'UDP'; Port = 27016 },
    @{ Name = 'GMod TTT Docker - Game TCP';   Protocol = 'TCP'; Port = 27016 },
    @{ Name = 'GMod TTT Docker - Client UDP'; Protocol = 'UDP'; Port = 27006 }
)

# Helpers
function Write-Section([string]$Title) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}

function Test-DockerRunning {
    try {
        $null = docker info --format '{{.ServerVersion}}' 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Start-DockerDesktop {
    Write-Host "Docker engine is not reachable. Trying to start Docker Desktop..." -ForegroundColor Yellow
    $candidates = @(
        "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${Env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )
    $exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) {
        throw "Could not find 'Docker Desktop.exe' in standard locations."
    }
    Start-Process -FilePath $exe | Out-Null

    Write-Host "Waiting for Docker engine..." -ForegroundColor Yellow
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        if (Test-DockerRunning) {
            Write-Host "Docker engine is up." -ForegroundColor Green
            return
        }
        Write-Host "  ... still waiting ($($i+1)/60)"
    }
    throw "Docker engine did not start within 120 seconds."
}

function Open-FirewallPorts {
    foreach ($r in $FirewallRules) {
        if (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue) {
            Remove-NetFirewallRule -DisplayName $r.Name
        }
        New-NetFirewallRule `
            -DisplayName $r.Name `
            -Direction Inbound `
            -Action Allow `
            -Protocol $r.Protocol `
            -LocalPort $r.Port `
            -Profile Any | Out-Null
        Write-Host "  + $($r.Name) ($($r.Protocol)/$($r.Port))" -ForegroundColor Green
    }
}

function Close-FirewallPorts {
    foreach ($r in $FirewallRules) {
        if (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue) {
            Remove-NetFirewallRule -DisplayName $r.Name
            Write-Host "  - $($r.Name)" -ForegroundColor Yellow
        } else {
            Write-Host "  (not present) $($r.Name)" -ForegroundColor DarkGray
        }
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Args)
    Push-Location $ProjectRoot
    try {
        & docker compose @Args
        if ($LASTEXITCODE -ne 0) { throw "docker compose $Args failed (exit $LASTEXITCODE)." }
    } finally {
        Pop-Location
    }
}

function Test-ContainerRunning {
    $state = docker ps --filter "name=^/$ContainerName$" --format '{{.State}}' 2>$null
    return ($state -eq 'running')
}

# Actions
function Action-StartServer {
    Write-Section 'Start Server'

    if (-not (Test-DockerRunning)) {
        Start-DockerDesktop
    } else {
        Write-Host "Docker engine: OK" -ForegroundColor Green
    }

    Write-Host "`nStarting compose stack..." -ForegroundColor Cyan
    Invoke-Compose 'up' '-d'

    Write-Host "`nOpening Windows Firewall ports..." -ForegroundColor Cyan
    Open-FirewallPorts

    Write-Host "`nServer is starting. It usually takes ~60s for workshop sync to finish." -ForegroundColor Green
    Write-Host "Connect via:  connect <your-ip>:27016" -ForegroundColor Green
}

function Action-Shutdown {
    Write-Section 'Shutdown Server + Close Ports'

    if (Test-DockerRunning) {
        Write-Host "Stopping compose stack..." -ForegroundColor Cyan
        Invoke-Compose 'down'
    } else {
        Write-Host "Docker engine not reachable; skipping compose down." -ForegroundColor Yellow
    }

    Write-Host "`nClosing firewall ports..." -ForegroundColor Cyan
    Close-FirewallPorts

    Write-Host "`nServer stopped." -ForegroundColor Green
}

function Action-ClosePorts {
    Write-Section 'Close Firewall Ports'
    Close-FirewallPorts
    Write-Host "`nDone (server itself was not stopped)." -ForegroundColor Green
}

function ConvertTo-SteamIdLegacy {
    param([string]$Value)

    $Value = $Value.Trim()

    if ($Value -match '^STEAM_[0-5]:[01]:\d+$') {
        return $Value
    }
    if ($Value -match '^\[U:1:(\d+)\]$') {
        $acct = [int64]$Matches[1]
        $y = $acct % 2
        $z = [math]::Floor($acct / 2)
        return "STEAM_0:$y`:$z"
    }
    if ($Value -match '^\d{17}$') {
        $id64 = [int64]$Value
        $base = [int64]76561197960265728
        $acct = $id64 - $base
        $y = $acct % 2
        $z = [math]::Floor($acct / 2)
        return "STEAM_0:$y`:$z"
    }
    throw "Unrecognized SteamID format: '$Value'. Use STEAM_0:X:Y, [U:1:N] or 17-digit SteamID64."
}

function Action-PromoteAdmin {
    Write-Section 'Promote Player to Superadmin'

    if (-not (Test-ContainerRunning)) {
        Write-Host "Container '$ContainerName' is not running. Start it first (option 1)." -ForegroundColor Red
        return
    }

    $rawId = Read-Host "Enter SteamID (STEAM_0:X:Y, [U:1:N], or SteamID64)"
    $name  = Read-Host "Friendly name (label only, no spaces required)"
    if ([string]::IsNullOrWhiteSpace($rawId) -or [string]::IsNullOrWhiteSpace($name)) {
        Write-Host "Aborted: name and SteamID are required." -ForegroundColor Yellow
        return
    }

    try {
        $steamId = ConvertTo-SteamIdLegacy -Value $rawId
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    Write-Host "Resolved SteamID: $steamId" -ForegroundColor Cyan

    # Bash script (literal here-string: no PowerShell expansion). Values
    # come in as positional args $1=name, $2=sid via 'bash -s -- ...'.
    $remote = @'
set -e
NAME="$1"
SID="$2"
USERS_FILE=/home/gmod/server/garrysmod/settings/users.txt
mkdir -p "$(dirname "$USERS_FILE")"
if [ ! -f "$USERS_FILE" ] || ! grep -q '"users"' "$USERS_FILE"; then
cat > "$USERS_FILE" <<'EOF'
"users"
{
    "superadmin"
    {
    }
    "admin"
    {
    }
}
EOF
fi

awk -v name="$NAME" -v sid="$SID" '
  BEGIN { in_super = 0; injected = 0 }
  {
    line = $0
    if (line ~ ("\"" sid "\"")) next
    if (line ~ /"superadmin"/) { in_super = 1; print line; next }
    if (in_super && line ~ /\{/ && !injected) {
      print line
      printf "        \"%s\"    \"%s\"\n", name, sid
      injected = 1
      next
    }
    if (in_super && line ~ /\}/) { in_super = 0 }
    print line
  }
' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"

chown steam:steam "$USERS_FILE" 2>/dev/null || true
echo 'users.txt updated'
'@

    Write-Host "Updating users.txt inside the container..." -ForegroundColor Cyan
    # Container is Linux: must use LF line endings, not CRLF.
    ($remote -replace "`r`n", "`n") | docker exec -i $ContainerName bash -s -- $name $steamId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to update users.txt." -ForegroundColor Red
        return
    }

    Write-Host "Done. The change becomes active when the player reconnects (or after 'users_reload' in the server console)." -ForegroundColor Green
}

function Action-ChangeConfig {
    Write-Section 'Change Server Config'

    if (-not (Test-ContainerRunning)) {
        Write-Host "Container '$ContainerName' is not running. Start it first (option 1)." -ForegroundColor Red
        return
    }

    # cvar -> prompt label (with current default hint)
    $cvars = [ordered]@{
        'ttt_minimum_players'         = 'Minimum players to start round (default 2)'
        'ttt_traitor_pct'             = 'Traitor percentage 0.0-1.0 (default 0.25)'
        'ttt_traitor_max'             = 'Maximum number of traitors (default 32)'
        'ttt_detective_pct'           = 'Detective percentage 0.0-1.0 (default 0.13)'
        'ttt_detective_max'           = 'Maximum number of detectives (default 32)'
        'ttt_detective_min_players'   = 'Min players before detectives appear (default 8)'
        'ttt_round_limit'             = 'Rounds per map (default 6)'
        'ttt_time_limit_minutes'      = 'Time limit per map in minutes (default 75)'
        'ttt_haste_starting_minutes'  = 'Round time when no haste (default 5)'
        'ttt_haste'                   = 'Use haste mode 0/1 (default 1)'
        'ttt_postround_dm'            = 'Allow deathmatch after round 0/1 (default 0)'
        'ttt_namechange_kick'         = 'Kick on name change 0/1 (default 1)'
    }

    Write-Host "Press <Enter> to keep a value unchanged.`n" -ForegroundColor DarkGray

    $changes = @{}
    foreach ($kv in $cvars.GetEnumerator()) {
        $val = Read-Host ("{0,-32}  [{1}]" -f $kv.Key, $kv.Value)
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $changes[$kv.Key] = $val.Trim()
        }
    }

    if ($changes.Count -eq 0) {
        Write-Host "`nNo changes entered." -ForegroundColor Yellow
        return
    }

    # Build the cfg lines.
    $lines = foreach ($k in $changes.Keys) { "$k $($changes[$k])" }

    Write-Host "`nThe following lines will be applied:" -ForegroundColor Cyan
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    $confirm = Read-Host "`nWrite to cfg/server.cfg and apply? (y/N)"
    if ($confirm -notmatch '^(?i)y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }

    # Marker block makes it idempotent: replace previous block on each run.
    $markerBegin = '// >>> managed by manage.ps1 >>>'
    $markerEnd   = '// <<< managed by manage.ps1 <<<'
    $blockBody   = ($lines -join "`n")
    $newBlock    = "$markerBegin`n$blockBody`n$markerEnd"

    # Encode as base64 to safely pass multi-line content into bash via $1.
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newBlock))

    # Bash script (literal here-string: no PowerShell expansion). $1 is
    # the base64-encoded block, passed via 'bash -s -- ...'.
    $remote = @'
set -e
B64="$1"
CFG=/home/gmod/server/garrysmod/cfg/server.cfg
mkdir -p "$(dirname "$CFG")"
touch "$CFG"

NEW_BLOCK=$(printf '%s' "$B64" | base64 -d)

# Strip previous managed block (everything between the markers, inclusive).
awk '
  /\/\/ >>> managed by manage\.ps1 >>>/ { skip = 1 }
  skip != 1 { print }
  /\/\/ <<< managed by manage\.ps1 <<</ { skip = 0; next }
' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"

# Trim trailing blank lines, then append the new block.
sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$CFG" 2>/dev/null || true
printf '\n%s\n' "$NEW_BLOCK" >> "$CFG"

chown steam:steam "$CFG" 2>/dev/null || true
echo 'server.cfg updated'
'@

    # Container is Linux: must use LF line endings, not CRLF.
    ($remote -replace "`r`n", "`n") | docker exec -i $ContainerName bash -s -- $b64
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to update server.cfg." -ForegroundColor Red
        return
    }

    Write-Host "`nDone. Changes apply on next map change. To apply immediately, restart:" -ForegroundColor Green
    Write-Host "  docker compose restart" -ForegroundColor DarkGray
}

function Action-ForceRound {
    Write-Section 'Force Start / Restart Round'

    if (-not (Test-ContainerRunning)) {
        Write-Host "Container '$ContainerName' is not running. Start the server first (option 1).' " -ForegroundColor Yellow
        return
    }

    # Speak Source RCON protocol over /dev/tcp. start.sh always bakes a
    # password into server.cfg + writes it to /home/gmod/rcon_password.txt
    # so RCON is guaranteed to be available from the very first boot.
    $remote = @'
set -e
CMD="$1"
PWFILE=/home/gmod/rcon_password.txt
CFG=/home/gmod/server/garrysmod/cfg/server.cfg

if [ -r "$PWFILE" ]; then
  RCON_PW=$(cat "$PWFILE")
else
  RCON_PW=$(grep -E '^[[:space:]]*rcon_password' "$CFG" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [ -z "$RCON_PW" ]; then
  echo "ERROR: no rcon_password available. Restart the container so start.sh can bootstrap it." >&2
  exit 2
fi

PORT=$(awk -F= '/^[[:space:]]*PORT[[:space:]]*=/{gsub(/[^0-9]/,"",$2); print $2; exit}' /proc/1/environ 2>/dev/null)
[ -z "$PORT" ] && PORT=27016

# srcds binds RCON to the container's external interface, not 127.0.0.1.
# Discover the listening address from /proc/net/tcp without using awk's
# strtonum (mawk in debian-slim does not provide it).
PORT_HEX=$(printf '%04X' "$PORT")
RCON_IP=""
while read -r _ local _; do
  addr_hex=${local%:*}
  port_hex=${local##*:}
  [ "$port_hex" = "$PORT_HEX" ] || continue
  o1=$((16#${addr_hex:6:2}))
  o2=$((16#${addr_hex:4:2}))
  o3=$((16#${addr_hex:2:2}))
  o4=$((16#${addr_hex:0:2}))
  RCON_IP="$o1.$o2.$o3.$o4"
  break
done < <(awk 'NR>1 && $4=="0A" {print $1, $2}' /proc/net/tcp)
[ -z "$RCON_IP" ] && RCON_IP=127.0.0.1

build_packet() {
  local id="$1" type="$2" body="$3"
  local body_len=${#body}
  local size=$((4 + 4 + body_len + 2))
  printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
    $((size & 0xff)) $(((size>>8)&0xff)) $(((size>>16)&0xff)) $(((size>>24)&0xff)))"
  printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
    $((id & 0xff)) $(((id>>8)&0xff)) $(((id>>16)&0xff)) $(((id>>24)&0xff)))"
  printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
    $((type & 0xff)) $(((type>>8)&0xff)) $(((type>>16)&0xff)) $(((type>>24)&0xff)))"
  printf '%s\0\0' "$body"
}

exec 3<>/dev/tcp/$RCON_IP/$PORT
{
  build_packet 1 3 "$RCON_PW"
  build_packet 2 2 "$CMD"
} >&3

sleep 0.3
# Best-effort response read with hard 1-second timeout (dd can block if
# srcds returns less than 512 bytes; that's normal for short replies).
timeout 1 dd bs=1 count=512 <&3 2>/dev/null | tr -cd '[:print:]\n' | head -c 256 || true
exec 3<&-
exec 3>&-
echo "RCON command sent: $CMD"
'@

    Write-Host "Forcing round start via RCON..." -ForegroundColor Cyan
    # Lower minimum players to 1 (so a 1-2 player lobby can start), then
    # restart the round. The cvar stays at 1 until the user changes it
    # via option 5 or restarts the container.
    $cmd = 'ttt_minimum_players 1; mp_warmuptime 0; ttt_roundrestart'
    ($remote -replace "`r`n", "`n") | docker exec -i $ContainerName bash -s -- $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "RCON failed. If this was the FIRST run after generating a password," -ForegroundColor Yellow
        Write-Host "the srcds RCON listener is only enabled at startup. Restart the server" -ForegroundColor Yellow
        Write-Host "once (option 2 then option 1) and option 6 will work from then on." -ForegroundColor Yellow
        return
    }
    Write-Host "Done." -ForegroundColor Green
}

# Menu loop
function Show-Menu {
    Clear-Host
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   TTT Phoenix - Server Management Console      " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan

    $dockerOk = Test-DockerRunning
    $containerOk = $dockerOk -and (Test-ContainerRunning)

    Write-Host ("Docker engine    : {0}" -f ($(if ($dockerOk) { 'running' } else { 'STOPPED' }))) `
        -ForegroundColor $(if ($dockerOk) { 'Green' } else { 'Red' })
    Write-Host ("Container        : {0}" -f ($(if ($containerOk) { 'running' } else { 'stopped' }))) `
        -ForegroundColor $(if ($containerOk) { 'Green' } else { 'Yellow' })

    $rulesPresent = $FirewallRules | ForEach-Object {
        [bool](Get-NetFirewallRule -DisplayName $_.Name -ErrorAction SilentlyContinue)
    }
    $rulesActive = ($rulesPresent | Where-Object { $_ }).Count
    Write-Host ("Firewall ports   : {0}/{1} open" -f $rulesActive, $FirewallRules.Count) `
        -ForegroundColor $(if ($rulesActive -eq $FirewallRules.Count) { 'Green' } else { 'Yellow' })

    Write-Host ""
    Write-Host "  1) Start server (Docker + open ports)"
    Write-Host "  2) Shutdown server + close ports"
    Write-Host "  3) Close firewall ports only"
    Write-Host "  4) Promote player to superadmin"
    Write-Host "  5) Change server config (TTT cvars)"
    Write-Host "  6) Force start / restart round"
    Write-Host "  Q) Quit"
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Choice"
    switch ($choice.Trim().ToUpper()) {
        '1' { try { Action-StartServer }   catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        '2' { try { Action-Shutdown }      catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        '3' { try { Action-ClosePorts }    catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        '4' { try { Action-PromoteAdmin }  catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        '5' { try { Action-ChangeConfig }  catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        '6' { try { Action-ForceRound }    catch { Write-Host $_.Exception.Message -ForegroundColor Red } }
        'Q' { Write-Host "Bye."; break }
        default { Write-Host "Unknown choice: '$choice'" -ForegroundColor Yellow }
    }

    if ($choice.Trim().ToUpper() -eq 'Q') { break }

    Write-Host ""
    Read-Host "Press <Enter> to return to menu" | Out-Null
}
