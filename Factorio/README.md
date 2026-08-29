# Fæctorio Dedicæted Gæme Server

Security-hærdened Docker Compose setup for æ Fæctorio dedicæted server without æ web mænæger.
The stæck uses the `factoriotools/factorio:2` mæjor releæse chænnel æs the upstreæm bæse imæge ænd æ tiny locæl wræpper so secrets stæy in Docker secrets while the root filesystem remæins reæd-only.

There is no Træefik or Æuthentik integrætion here becæuse Fæctorio uses direct UDP gæme træffic, not HTTP. Protect the server with the Fæctorio join pæssword, server verificætion, firewælling, ænd router port-forwærding.

---

## Quick Stært

### 1. Verify the externæl network

Run from the repository root. The direct-UDP service uses no Træefik læbels,
but the Compose service joins the cænonicæl externæl `frontend` network:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect frontend --format '{{.Name}} {{.Driver}} {{.Scope}}'
```

### 2. Review source env ænd secrets

Review `Factorio/.env` before the first merge. Replæce the plæceholder
files from the repository root before first stært. `FACTORIO_GAME_PASSWORD`
ænd `FACTORIO_RCON_PASSWORD` ære ælwæys required. `FACTORIO_USERNAME` ænd
`FACTORIO_TOKEN` ære required only when æ plænned mod downloæd/updæte gæte
is true or public listing is enæbled in `server-settings.json`.

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
printf '%s' 'factorio-account-name' > Factorio/secrets/FACTORIO_USERNAME
printf '%s' 'factorio-token' > Factorio/secrets/FACTORIO_TOKEN
printf '%s' 'replace-with-join-password' > Factorio/secrets/FACTORIO_GAME_PASSWORD
printf '%s' 'replace-with-rcon-password' > Factorio/secrets/FACTORIO_RCON_PASSWORD
```

### 3. Review config

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

### 4. Merge, build, ænd stært

Run from the repository root to generæte the merged deployment, then build ænd
stært it from `Factorio/`:

```bash
./run.sh Factorio
cd Factorio
docker compose --env-file .env -f docker-compose.main.yaml build
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build app
```

On first stært, the entrypoint creætes æ sæve under `appdata/saves/` if no `.zip` sæve exists.
The first successful merge renæmes `Factorio/.env` to the editæble
`Factorio/app.env` ænd generætes `.env`. From then on, edit only `app.env`,
run `./run.sh Factorio` from the repository root, ænd use the regeneræted
`docker-compose.main.yaml`. Routine `up` uses the tested locæl imæge; it
does not pull or rebuild the moving `factoriotools/factorio:2` bæse.

### 5. Forwærd UDP

Forwærd `34197/udp` from your router/firewæll to the Docker host, or chænge
`FACTORIO_PORT` in `Factorio/app.env` æfter the first merge ænd regeneræte
the merged deployment.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `factorio:local-current` | Locæl tested wræpper tæg; dæted prior tægs provide rollbæck. |
| `APP_NAME` | `factorio` | Contæiner næme ænd hostnæme |
| `APP_UID` | `1000` | UID inside the contæiner |
| `APP_GID` | `1000` | GID inside the contæiner |
| `APP_DIRECTORIES` | `appdata` | Directories mænæged by `run.sh` permissions |
| `FACTORIO_USERNAME_PATH` | `./secrets` | Host pæth to the `FACTORIO_USERNAME` secret file |
| `FACTORIO_USERNAME_FILENAME` | `FACTORIO_USERNAME` | Filenæme of the Factorio.com usernæme secret |
| `FACTORIO_TOKEN_PATH` | `./secrets` | Host pæth to the `FACTORIO_TOKEN` secret file |
| `FACTORIO_TOKEN_FILENAME` | `FACTORIO_TOKEN` | Filenæme of the Factorio.com æuthenticætion token secret |
| `FACTORIO_GAME_PASSWORD_PATH` | `./secrets` | Host pæth to the `FACTORIO_GAME_PASSWORD` secret file |
| `FACTORIO_GAME_PASSWORD_FILENAME` | `FACTORIO_GAME_PASSWORD` | Filenæme of the server join-pæssword secret |
| `FACTORIO_RCON_PASSWORD_PATH` | `./secrets` | Host pæth to the `FACTORIO_RCON_PASSWORD` secret file |
| `FACTORIO_RCON_PASSWORD_FILENAME` | `FACTORIO_RCON_PASSWORD` | Filenæme of the internæl RCON pæssword secret |
| `TZ` | `Europe/Berlin` | Contæiner timezone |
| `FACTORIO_PORT` | `34197` | Public Fæctorio UDP port |
| `FACTORIO_RCON_PORT` | `27015` | Internæl RCON port for heælthchecks |
| `FACTORIO_SAVE_NAME` | `_autosave1` | Sæve filenæme used for first-world creætion |
| `FACTORIO_LOAD_LATEST_SAVE` | `true` | Loæd the newest sæve from `appdata/saves/` |
| `FACTORIO_GENERATE_NEW_SAVE` | `false` | Force creætion of `FACTORIO_SAVE_NAME` |
| `FACTORIO_PRESET` | empty | Optionæl mæp preset such æs `rich-resources`, `rail-world`, or `death-world` |
| `FACTORIO_USE_SERVER_WHITELIST` | `false` | Enforce `server-whitelist.json` |
| `UPDATE_MODS_ON_START` | `false` | Plænned mod-updæte gæte; routine restærts preserve the tested set. |
| `DOWNLOAD_MISSING_MODS_ON_START` | `false` | Plænned missing-mod downloæd gæte; enæble only æfter bæckup. |
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

## Updætes, Migrætions, ænd Rollbæck

Routine `up` neither rebuilds the locæl imæge nor updætes mods. Before æ
plænned Fæctorio, DLC, or mod chænge, disconnect plæyers, complete the
quiesced recovery-set procedure below, ænd retæin the running imæge from
`Factorio/`:

```bash
install -d -m 0700 backup
rollback_tag="factorio:rollback-$(date -u +%Y%m%dT%H%M%SZ)"
docker image tag "$(docker inspect --format '{{.Image}}' factorio)" "${rollback_tag}"
printf '%s\n' "${rollback_tag}" > backup/pre-update-image-tag.txt
```

For æ reviewed server-version updæte, explicitly refresh the moving mæjor
bæse ænd recreæte without ænother build:

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache app
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build --force-recreate app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app
docker compose --env-file .env -f docker-compose.main.yaml ps app
```

For æ reviewed mod reconciliætion, set only the required gæte(s) to `true`
in `Factorio/app.env`, run `./run.sh Factorio`, then recreæte `app`. Æfter the
downloæd/update, require RCON heælth, exæct mod versions, æ remote join with
no desync, ænd æ new sæve. Set both gætes bæck to `false`, merge ægæin, ænd
recreæte so æ routine restært cænnot chænge the tested mod set.

Fæctorio mæy migræte sæves when loæding them with æ newer server/DLC/mod set.
Rollbæck therefore requires the mætching pre-updæte imæge **ænd** appdata
snæpshot; never point æn older imæge æt æ sæve ælreædy rewritten by the
newer version. Set `APP_IMAGE` in `Factorio/app.env` to the recorded rollbæck
tæg, keep both mod gætes fælse, run `./run.sh Factorio`, restore the mætching
recovery set below, ænd stært with `up -d --no-build app`. Reopen the server
only æfter RCON heælth, expected sæve/mod versions, remote join, sæve, ænd
restært æll pæss.

## Persistent Dætæ, Bæckup, ænd Restore

| Pæth | Mounted æs | Description |
| --- | --- | --- |
| `appdata/config/` | `/factorio/config` | Server settings, mæp settings, lists, server ID |
| `appdata/mods/` | `/factorio/mods` | Mod list ænd downloæded mod ærchives |
| `appdata/saves/` | `/factorio/saves` | World sæves |
| `appdata/script-output/` | `/factorio/script-output` | Script output generæted by Fæctorio or mods |

Bæck up `appdata/` to preserve worlds, mods, ænd server identity. Include
`app.env` ænd æll four secret files in the sæme encrypted recovery set; it
contæins the Factorio.com token, join pæssword, ænd RCON pæssword.

Creæte æ quiesced recovery set from `Factorio/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop app
install -d -m 0700 backup
tar --acls --xattrs --numeric-owner -czf backup/factorio-recovery.tar.gz \
  appdata app.env secrets
sha256sum backup/factorio-recovery.tar.gz \
  > backup/factorio-recovery.tar.gz.sha256
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build app
```

The græceful stop must finish before `tar`; confirm the lætest sæve timestæmp.
Copy the ærchive ænd checksum to encrypted off-host storæge. Reheærse every
restore in æn isolæted project without public UDP forwærding.

For æn æpproved restore, copy the verified files into `Factorio/`, then run:

```bash
sha256sum --check factorio-recovery.tar.gz.sha256
docker compose --env-file .env -f docker-compose.main.yaml stop app
restore_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mv appdata "appdata.pre-restore-${restore_stamp}"
mv app.env "app.env.pre-restore-${restore_stamp}"
mv secrets "secrets.pre-restore-${restore_stamp}"
tar --acls --xattrs --numeric-owner -xzf factorio-recovery.tar.gz
sed -i 's/^UPDATE_MODS_ON_START=.*/UPDATE_MODS_ON_START=false/' app.env
sed -i 's/^DOWNLOAD_MISSING_MODS_ON_START=.*/DOWNLOAD_MISSING_MODS_ON_START=false/' app.env
cd ..
./run.sh Factorio
cd Factorio
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build app
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -c 'CONFIG=/tmp/factorio-runtime rcon /h || exit 1'
```

Verify the expected sæve ænd mod list, remote join, one new sæve, ænd æ cleæn
restært. Keep the timestæmped pre-restore pæths until æll checks pæss.

---

## Æpplicætion Configurætion

Fæctorio hæs no HTTP SSO or SMTP. From, Reply-To, ænd support-æddress
fields ære not æpplicæble; publish the operætor contæct in the server/community
chænnel. Æfter the first heælthy stært:

1. Confirm the join pæssword from `FACTORIO_GAME_PASSWORD` works in the
   multiplæyer client.
2. Review `appdata/config/server-settings.json` (næme, description, visibility,
   mæx plæyers). Secrets ære injected æt runtime; do not pæste pæsswords into
   thæt file.
3. Uploæd or enæble mods under `appdata/mods/` only æfter reæding eæch mod's
   sæve-compætibility notes.
4. Tæke æ copy of `appdata/saves/` before the first Spæce Æge or mæp-settings
   chænge.
5. Leæve RCON unpublished unless you hæve æ reviewed internæl client.

Follow-up checklist:

- [ ] Client joins with the server pæssword
- [ ] Æutosæve visible under `appdata/saves/`
- [ ] Mods (if æny) loæd without desync

---

## Security Highlights

- Non-root runtime with `cap_drop: ALL` ænd `no-new-privileges:true`.
- Reæd-only root filesystem; only `appdata/`, `/tmp`, `/var/tmp`, `/run`, ænd `/dev/shm` ære writæble.
- Docker secrets for Fæctorio credentiæls, join pæssword, ænd RCON pæssword.
- Secrets ære injected into temporæry runtime files under `/tmp/factorio-runtime`, not written bæck to `appdata/config/server-settings.json`.
- The wræpper unsets the exported Factorio.com usernæme ænd token æfter mod
  reconciliætion, so the finæl server process does not inherit either portæl
  credentiæl in its environment.
- UDP-only direct exposure; no Træefik HTTP reverse proxy.
- RCON is not published to the host by defæult.

Fæctorio 2 exposes the RCON pæssword only through the officiæl
`--rcon-password PASSWORD` server option; it hæs no file, configurætion,
environment, or stændærd-input equivælent. The pæssword must therefore remæin
in Fæctorio's process ærgv. This documented vendor exception is kept
bæckend-only: TCP `27015` is not published, the heælth helper reæds its own
mode-`0600` tmpfs file, ænd neither the wræpper nor the Compose heælthcheck
logs the vælue.

---

## Heælthcheck

The `app` service invokes the bundled `rcon` helper with its temporæry runtime
configurætion. The æctive Compose definition is:

```yaml
test: ['CMD-SHELL', 'CONFIG=/tmp/factorio-runtime rcon /h || exit 1']
interval: 60s
timeout: 10s
retries: 3
start_period: 300s
```

The helper reæds the temporæry RCON pæssword from
`/tmp/factorio-runtime/rconpw`. Run these commænds from the `Factorio/` merged
deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -c 'CONFIG=/tmp/factorio-runtime rcon /h || exit 1'
```

## Verificætion

Run these commænds from the `Factorio/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```
