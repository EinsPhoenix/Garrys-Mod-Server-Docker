# TTT Phoenix - Garry's Mod Dedicated Server (Docker)

A self-contained Docker setup for a Trouble in Terrorist Town (TTT) dedicated
Garry's Mod server. Steam Workshop addons (weapons, maps, MapVote) are
downloaded and mounted automatically on every container start. A PowerShell
management console handles Docker, Windows Firewall, admin promotion and TTT
config edits from a single menu.

---

## Quickstart

Prerequisites: Windows 10/11 with Docker Desktop (WSL2 backend) installed.

1. Clone the repository and open a terminal in the project root.
2. Build the image (only needed the first time, or after editing the Dockerfile):

   ```powershell
   docker compose build
   ```

3. Launch the management console (it will self-elevate to Administrator):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\manage.ps1
   ```

4. In the menu pick `1) Start server`. The script will:
   - start Docker Desktop if it is not running,
   - run `docker compose up -d`,
   - open Windows Firewall for UDP/TCP 27016 and UDP 27006.

5. The first start takes roughly 60 seconds while SteamCMD downloads the
   workshop content. When the container is healthy, connect from the in-game
   console:

   ```
   connect <your-lan-ip>:27016
   ```

   Friends on the internet connect to `<your-public-ip>:27016` once your
   router forwards UDP 27016 to your machine.

To stop everything (server + firewall) pick `2) Shutdown` in the menu.

---

## Default content

Built-in addons shipped in `addons/` (no workshop required):

| Folder            | What it does                                                  |
| ----------------- | ------------------------------------------------------------- |
| `ttt-workshop`    | Auto-generated `resource.AddWorkshop` so clients fast-download every Workshop ID below. |
| `ttt-jihad`       | Traitor equipment "Jihad Bomb". Plays a 3-second warning sound, then explodes. |
| `ttt-proximity`   | Distance-based voice chat (`ttt_proximity_voice`, `ttt_proximity_full`, `ttt_proximity_max`). Spectators always hear everyone. |

### Custom Jihad warning sound (not in repo)

The Jihad Bomb plays `sound/ttt_jihad/wth.mp3` when triggered. The repository
does **not** ship that file (no copyrighted media in git). To enable the
sound, drop your own MP3 here on the host:

```
addons/ttt-jihad/sound/ttt_jihad/wth.mp3
```

Then `docker compose restart` the container. `assets/start.sh` rsyncs
`addons/` into the game tree on every start, so the file is picked up
automatically and broadcast to clients via `resource.AddSingleFile`. Audible
radius is roughly 50 m (controlled by `SoundLevel = 90` in
`addons/ttt-jihad/lua/weapons/weapon_ttt_jihad/shared.lua`).

Workshop IDs configured in `docker-compose.yaml`:

| Category   | Workshop ID  | Item                              |
| ---------- | ------------ | --------------------------------- |
| Weapon     | `807428039`  | Holy Hand Grenade TTT             |
| Weapon     | `356664308`  | TTT Melon Launcher                |
| Map vote   | `151583504`  | MapVote (Lucien, Fretta-style)    |
| Map        | `159321088`  | ttt_minecraft_b5                  |
| Map        | `221814617`  | ttt_67thway_v3                    |
| Map        | `281454209`  | ttt_clue_se                       |
| Map        | `195227686`  | ttt_dolls                         |
| Map        | `419903291`  | ttt_rooftops_a2_f1                |
| Map        | `157420728`  | ttt_waterworld                    |
| Map        | `253297309`  | ttt_airbus_b3                     |

Clients auto-download the same IDs through `addons/ttt-workshop` (which calls
`resource.AddWorkshop`).

The map rotation is built from the `MAPS` environment variable in
`docker-compose.yaml`; the list is shuffled into `cfg/mapcycle.txt` on every
container start.

---

## Repository layout

```
garrysmod-docker/
  Dockerfile                Container image (debian bullseye-slim, glibc 2.31)
  docker-compose.yaml       Stack definition (ports, env, volumes)
  assets/
    start.sh                Container entrypoint: workshop sync + srcds_run
    health.sh               HEALTHCHECK script
    update.txt              SteamCMD script (downloads GMod app 4020)
  addons/                   Read-only mount -> /srv/addons (rsync'd on start)
    ttt-workshop/           Client-side resource.AddWorkshop addon
    ttt-jihad/              Built-in Jihad Bomb traitor weapon
    ttt-proximity/          Distance-based voice chat
  gamemodes/                Read-only mount -> /srv/gamemodes (only synced
                            when you drop your own gamemode override here;
                            stock gamemodes ship with the GMod install)
  scripts/
    manage.ps1              Windows management console (admin menu)
```

---

## Networking

The local Garry's Mod client (`gmod.exe`) binds UDP 27015 on the host whenever
it runs. To avoid conflicts the dedicated server in this project uses
**port 27016** (UDP and TCP) and **27006/UDP** for the client port. Both the
host and container side use the same numbers so the LAN server browser
advertises the correct address (`<host-ip>:27016`).

| Purpose            | Host port  | Container port | Protocol |
| ------------------ | ---------- | -------------- | -------- |
| Game traffic, RCON | 27016      | 27016          | UDP+TCP  |
| Client port        | 27006      | 27005          | UDP      |

For internet play, forward **UDP 27016** (and TCP 27016 if you want RCON) on
your router to the host machine.

### Connecting via a domain name

Source servers cannot bind to a hostname directly, but players can still
connect through a DNS name:

1. Create a DNS `A` record pointing your domain to your public IP, for example
   `ttt.example.com -> 93.208.28.169`.
2. Forward UDP 27016 on your router as described above.
3. Players connect from the in-game console:

   ```
   connect ttt.example.com:27016
   ```

For dynamic public IPs, use a DDNS provider (DuckDNS, No-IP, your router's
built-in DDNS, etc.) and point the `A` record at the DDNS hostname (`CNAME`).

---

## Management console

`scripts/manage.ps1` is a single, self-elevating PowerShell script. The menu:

1. **Start server** - launch Docker Desktop if needed, `docker compose up -d`,
   open Windows Firewall ports.
2. **Shutdown** - `docker compose down` and remove the firewall rules.
3. **Close ports** - remove the firewall rules only (server keeps running).
4. **Promote player to superadmin** - prompts for SteamID (any of
   `STEAM_0:X:Y`, `[U:1:N]`, or 17-digit SteamID64) and a friendly name.
   Updates `garrysmod/settings/users.txt` inside the container. Takes effect
   when the player reconnects, or after `users_reload` in the server console.
5. **Change server config** - prompts for common TTT cvars
   (`ttt_traitor_pct`, `ttt_round_limit`, `ttt_time_limit_minutes`,
   `ttt_minimum_players`, etc.) and writes them into a managed block in
   `garrysmod/cfg/server.cfg`. Re-running the action replaces the previous
   block. Changes apply on the next map change, or immediately after
   `docker compose restart`.

The menu header shows live status for the Docker engine, the container, and
the firewall rules.

---

## Manual Docker usage

If you do not want to use the management console:

```powershell
docker compose build           # build the image
docker compose up -d           # start in the background
docker compose logs -f         # follow logs (Ctrl+C to detach)
docker compose restart         # apply server.cfg changes immediately
docker compose down            # stop and remove the container
```

The compose stack uses two named volumes for caching:

- `gmod_steam_cache` -> `/home/gmod/server/steam_cache`
- `gmod_server_cache` -> `/home/gmod/server/garrysmod/cache`

These survive `docker compose down` and avoid re-downloading workshop content
on every start. To wipe them: `docker volume rm garrysmod-docker_gmod_steam_cache garrysmod-docker_gmod_server_cache`.

---

## Configuration reference

Environment variables in `docker-compose.yaml`:

| Variable       | Default                         | Description                                                              |
| -------------- | ------------------------------- | ------------------------------------------------------------------------ |
| `HOSTNAME`     | `TTTPhoenix`                    | Server name displayed in the Steam server browser.                       |
| `NAME`         | `EinsPhoenix`                   | Fallback name if `HOSTNAME` is unset.                                    |
| `PRODUCTION`   | `1`                             | Adds `-disableluarefresh` for production; set to `0` for dev mode.       |
| `GAMEMODE`     | `terrortown`                    | Garry's Mod gamemode folder name.                                        |
| `MAP`          | `ttt_minecraft_b5`              | Fallback map if `MAPS` is empty.                                         |
| `MAPS`         | (7 TTT maps)                    | Comma/space/newline list, shuffled into `cfg/mapcycle.txt`.              |
| `PORT`         | `27016`                         | UDP/TCP game port (must match the compose `ports:` mapping).             |
| `MAXPLAYERS`   | `16`                            | Maximum player slots.                                                    |
| `WORKSHOP_IDS` | (11 IDs)                        | Space-separated workshop addon IDs (gmod app 4000).                      |
| `GSLT`         | unset                           | Optional Steam Game Server Login Token.                                  |
| `AUTHKEY`      | unset                           | Optional `-authkey` for workshop collections.                            |
| `ARGS`         | unset                           | Extra raw arguments appended to the `srcds_run` command.                 |

Edit `docker-compose.yaml` and run `docker compose up -d` to apply.

---

## How addon mounting works

Garry's Mod is sensitive to how its content folders are exposed. Mounting the
host's `addons/` and `gamemodes/` directly into `/home/gmod/server/garrysmod/*`
through Docker Desktop's 9p filesystem causes the Source engine to silently
miss most files (directory enumeration returns empty, even though the files
are readable).

To work around this:

1. The host directories are mounted **read-only** at `/srv/addons` and
   `/srv/gamemodes`.
2. On every container start, `assets/start.sh` uses `rsync` to copy them into
   the real game tree at `/home/gmod/server/garrysmod/{addons,gamemodes}`.
3. Workshop downloads land in `addons/ws_<id>/` after extraction with
   `gmad_linux`, which is the format `gameinfo.txt`'s `game+mod
   garrysmod/addons/*` line actually mounts.

The result is shown in the server log as
`Adding Filesystem Addon 'addons/ws_<id>'` for each workshop item.

---

## Troubleshooting

**The in-game server browser shows the wrong port.**
Make sure the container is running with the host port equal to the container
port (this repo uses 27016 on both sides for that reason). After editing
`docker-compose.yaml`, run `docker compose up -d --force-recreate`.

**A2S query times out from the host.**
Check whether your local `gmod.exe` is running: it binds UDP 27015 to
`0.0.0.0` and intercepts queries to that port. This project uses 27016 for
the dedicated server to avoid the conflict.

**Friends cannot connect over the internet.**
Confirm the router forwards UDP 27016 to the host machine, and that the
firewall rules from the management console exist (menu shows
`Firewall ports: 3/3 open`). Verify your public IP with
`Invoke-RestMethod ifconfig.me`.

**Workshop addons are downloaded but not loaded.**
Look for `Adding Filesystem Addon 'addons/ws_<id>'` lines in
`docker compose logs`. If they are missing, delete the cache volumes and
recreate the container.

---

## License

See [LICENSE](LICENSE).


## Have Fun now its not painfull anymore
# Author 
@EinsPhoenix

# Credits
@ceifa