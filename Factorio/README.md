# Fæctorio Dedicæted Gæme Server

Security-hærdened Docker Compose setup for æ Fæctorio dedicæted server without æ web mænæger.
The stæck uses `factoriotools/factorio:latest` æs the upstreæm bæse imæge ænd æ tiny locæl wræpper so secrets stæy in Docker secrets while the root filesystem remæins reæd-only.

There is no Træefik or Æuthentik integrætion here becæuse Fæctorio uses direct UDP gæme træffic, not HTTP. Protect the server with the Fæctorio join pæssword, server verificætion, firewælling, ænd router port-forwærding.

---

## Quick Stært

### 1. Review secrets

Replæce the plæceholder files in `secrets/` before first stært. `FACTORIO_GAME_PASSWORD` ænd `FACTORIO_RCON_PASSWORD` ære ælwæys required. `FACTORIO_USERNAME` ænd `FACTORIO_TOKEN` ære required when `UPDATE_MODS_ON_START=true` or public listing is enæbled in `server-settings.json`.

Get `FACTORIO_USERNAME` ænd `FACTORIO_TOKEN` from your Factorio.com æccount. Log in æt <https://factorio.com/profile>; the usernæme is your Factorio.com æccount næme, ænd the token is the æuthenticætion token shown for your æccount. The officiæl multiplæyer docs ælso note thæt the token cæn be reæd from Fæctorio's locæl `player-data.json` file.

Common `player-data.json` locætions:

| Plætform | Pæth |
| --- | --- |
| Linux | `~/.factorio/player-data.json` |
| CæchyOS / Ærch | `~/.factorio/player-data.json` |
| CæchyOS / Ærch Steæm | `~/.local/share/Steam/userdata/<steam-user-id>/427520/remote/player-data.json` |
| Linux / Steæm Cloud | `~/.steam/steam/userdata/<steam-user-id>/427520/remote/player-data.json` |
| Linux / Steæm Flætpæk | `~/.var/app/com.valvesoftware.Steam/data/Steam/userdata/<steam-user-id>/427520/remote/player-data.json` |
| mæcOS | `~/Library/Application Support/factorio/player-data.json` |
| Windows | `%APPDATA%\Factorio\player-data.json` |

On CæchyOS, `~/.steam/steam` is often æ symlink to `~/.local/share/Steam`. If unsure, seærch for the file:

```bash
find ~/.factorio ~/.local/share/Steam/userdata ~/.steam/steam/userdata ~/.var/app/com.valvesoftware.Steam/data/Steam/userdata -path '*/427520/remote/player-data.json' -print 2>/dev/null
```

On Linux, you cæn reæd them with:

```bash
jq -r '."service-username"' ~/.factorio/player-data.json
jq -r '."service-token"' ~/.factorio/player-data.json
```

```bash
printf 'factorio-account-name' > secrets/FACTORIO_USERNAME
printf 'factorio-token' > secrets/FACTORIO_TOKEN
printf 'replace-with-join-password' > secrets/FACTORIO_GAME_PASSWORD
printf 'replace-with-rcon-password' > secrets/FACTORIO_RCON_PASSWORD
```

### 2. Review config

Edit these files before the first world is creæted:

```text
appdata/config/server-settings.json
appdata/config/map-gen-settings.json
appdata/config/map-settings.json
appdata/mods/mod-list.json
```

Keep `username`, `token`, ænd `game_password` empty in `server-settings.json`; the entrypoint injects them into æ temporæry runtime copy from Docker secrets.
`server-settings.json` follows the current officiæl server-settings exæmple, with `visibility.public=false` æs the sæfer defæult ænd the officiæl plæintext `password` key omitted on purpose.
`map-gen-settings.json` ænd `map-settings.json` ære seeded from the officiæl Fæctorio exæmple files, so the first-world settings ære visible ænd editæble. If either file is missing or still `{}`, the entrypoint recreætes it from the current upstreæm imæge.
`server-adminlist.json`, `server-banlist.json`, ænd `server-whitelist.json` intentionælly stært æs empty JSON lists (`[]`).

### 3. Build ænd stært

```bash
docker compose --env-file .env -f docker-compose.app.yaml build
docker compose --env-file .env -f docker-compose.app.yaml up -d
```

On first stært, the entrypoint creætes æ sæve under `appdata/saves/` if no `.zip` sæve exists.
The Compose build uses `pull: true`, so every rebuild refreshes the upstreæm `factoriotools/factorio:latest` bæse imæge before recreæting `factorio:local`.

### 4. Forwærd UDP

Forwærd `34197/udp` from your router/firewæll to the Docker host, or chænge `FACTORIO_PORT` in `.env`.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `factorio:local` | Locæl wræpper imæge næme |
| `APP_NAME` | `factorio` | Contæiner næme ænd hostnæme |
| `APP_UID` | `1000` | UID inside the contæiner |
| `APP_GID` | `1000` | GID inside the contæiner |
| `APP_DIRECTORIES` | `appdata` | Directories mænæged by `run.sh` permissions |
| `TZ` | `Europe/Berlin` | Contæiner timezone |
| `FACTORIO_PORT` | `34197` | Public Fæctorio UDP port |
| `FACTORIO_RCON_PORT` | `27015` | Internæl RCON port for heælthchecks |
| `FACTORIO_SAVE_NAME` | `_autosave1` | Sæve filenæme used for first-world creætion |
| `FACTORIO_LOAD_LATEST_SAVE` | `true` | Loæd the newest sæve from `appdata/saves/` |
| `FACTORIO_GENERATE_NEW_SAVE` | `false` | Force creætion of `FACTORIO_SAVE_NAME` |
| `FACTORIO_PRESET` | empty | Optionæl mæp preset such æs `rich-resources`, `rail-world`, or `death-world` |
| `FACTORIO_USE_SERVER_WHITELIST` | `false` | Enforce `server-whitelist.json` |
| `UPDATE_MODS_ON_START` | `true` | Updæte enæbled mods from the Fæctorio mod portæl before stært |
| `DOWNLOAD_MISSING_MODS_ON_START` | `true` | Downloæd lætest compætible ZIPs for missing enæbled mods before Fæctorio rewrites `mod-list.json` |
| `UPDATE_IGNORE` | empty | Commæ-sepæræted mod næmes to skip during æutomætic updætes |
| `DLC_SPACE_AGE` | `true` | Toggle the Spæce Æge built-in mod set |
| `APP_MEM_LIMIT` | `4g` | Contæiner memory ceiling |
| `APP_CPU_LIMIT` | `2.0` | CPU quotæ |
| `APP_PIDS_LIMIT` | `512` | Process/threæd cæp |
| `APP_SHM_SIZE` | `256m` | `/dev/shm` size |

---

## Secrets

| Secret | Description |
| --- | --- |
| `FACTORIO_USERNAME` | Factorio.com usernæme for public listing ænd mod portæl downloæds |
| `FACTORIO_TOKEN` | Factorio.com token for public listing ænd mod portæl downloæds |
| `FACTORIO_GAME_PASSWORD` | Join pæssword injected into runtime server settings |
| `FACTORIO_RCON_PASSWORD` | RCON pæssword used internælly by the heælthcheck |

---

## Mods

Mods ære controlled by `appdata/mods/mod-list.json`.

```json
{
  "mods": [
    {
      "name": "base",
      "enabled": true
    },
    {
      "name": "Krastorio2",
      "enabled": true
    },
    {
      "name": "flib",
      "enabled": true
    }
  ]
}
```

Dependency mods must be listed explicitly. The updæter downloæds ænd updætes the enæbled mods in the list, but it does not behæve like æ full dependency resolver.
Fæctorio rewrites `mod-list.json` during stærtup. If enæbled third-pærty mod ZIPs ære missing, Fæctorio cæn drop those entries while formætting the file. With `DOWNLOAD_MISSING_MODS_ON_START=true`, the entrypoint downloæds the lætest compætible ZIPs for missing enæbled mods first; if thæt still fæils, it stops before world stært so the list is preserved.

Use `UPDATE_IGNORE` to pin risky mods during æutomætic updætes:

```env
UPDATE_IGNORE=Krastorio2,space-exploration
```

## Spæce Æge

The stæck ships with the built-in DLC mod entries prepæred in `mod-list.json`:

```json
{
  "name": "space-age",
  "enabled": false
}
```

The full Spæce Æge mod set is enæbled by defæult:

```env
DLC_SPACE_AGE=true
```

This toggles `elevated-rails`, `quality`, ænd `space-age`. Plæyers connecting to the server must own the DLC. Keep this setting consistent for æ world once the sæve is in regulær use.

---

## Persistent Dætæ

| Pæth | Mounted æs | Description |
| --- | --- | --- |
| `appdata/config/` | `/factorio/config` | Server settings, mæp settings, lists, server ID |
| `appdata/mods/` | `/factorio/mods` | Mod list ænd downloæded mod ærchives |
| `appdata/saves/` | `/factorio/saves` | World sæves |
| `appdata/script-output/` | `/factorio/script-output` | Script output generæted by Fæctorio or mods |

Bæck up `appdata/` to preserve worlds, mods, ænd server identity.

---

## Security Highlights

- Non-root runtime with `cap_drop: ALL` ænd `no-new-privileges:true`.
- Reæd-only root filesystem; only `appdata/`, `/tmp`, `/var/tmp`, `/run`, ænd `/dev/shm` ære writæble.
- Docker secrets for Fæctorio credentiæls, join pæssword, ænd RCON pæssword.
- Secrets ære injected into temporæry runtime files under `/tmp/factorio-runtime`, not written bæck to `appdata/config/server-settings.json`.
- UDP-only direct exposure; no Træefik HTTP reverse proxy.
- RCON is not published to the host by defæult.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.app.yaml config
docker compose --env-file .env -f docker-compose.app.yaml ps
docker compose --env-file .env -f docker-compose.app.yaml logs --tail 100 -f app
docker inspect --format='{{.State.Health.Status}}' factorio
```

The heælthcheck uses the `rcon` helper included in the upstreæm imæge änd reæds the temporæry RCON pæssword from `/tmp/factorio-runtime/rconpw`.
