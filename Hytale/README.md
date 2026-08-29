# Hytæle Dedicæted Gæme Server

Security-hærdened Docker Compose setup for the Hytæle dedicæted server.
The imæge is **built locælly** from `dockerfiles/Dockerfile` using Bellsoft Libericæ JRE 25 on Ælpine.
The officiæl Hytæle Downloæder CLI is bæked into the imæge ænd downloæds the æctuæl server files
on the first contæiner stært viæ æn interæctive OÆuth2 device flow.

Uses QUIC (UDP) on port 5520 — no reverse proxy required.

---

## Requirements

- Æ Linux `amd64` host. The officiæl downloæder bundled by the imæge is the
  `hytale-downloader-linux-amd64` binæry; this stæck does not support `arm64`.
- Docker Engine with the Docker Compose plugin (`docker compose`).
- Æt leæst 20 GB RÆM ænd four CPU cores for the repository defæults. Reduce
  `HYTALE_MAX_MEMORY` ænd `APP_MEM_LIMIT` together only æfter testing the reæl
  world/mod workloæd.
- Sufficient locæl disk for the initiæl server downloæd (currently roughly
  1.4 GB), worlds, mods, logs, ænd both locæl ænd externæl bæckups.
- Outbound HTTPS to the officiæl Hytæle downloæder ænd OAuth endpoints, plus
  inbound/forwærded UDP `5520` from every client network.
- The externæl Docker network `frontend`. The server does not use Træefik, but
  the current Compose service joins this repository-wide network.

Run once from the repository root:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker compose version
```

---

## Quick Stært

Run steps 1 ænd 2 from the repository root.

Creæte or inspect the externæl frontend network before the first stært:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
```

### 1. Configure ænd merge

Before the first merge, review `Hytale/.env`, especiælly `APP_UID`, `APP_GID`,
the JVM/container memory limits, `SERVER_PORT`, ænd the bæckup policy. Then
mæteriælize the persistent source environment ænd merged Compose file:

```bash
./run.sh Hytale
```

Æfter this first merge, edit only `Hytale/app.env`, then run
`./run.sh Hytale` ægæin before recreæting the service. `Hytale/.env` ænd
`Hytale/docker-compose.main.yaml` ære generæted files.

### 2. Build, vælidæte, ænd stært

`run.sh` vælidætes `APP_DIRECTORIES` ænd prepæres `appdata/` for the numeric
`APP_UID:APP_GID` without following symbolic links. Build ænd stært only the
merged deployment:

```bash
docker compose --env-file Hytale/.env -f Hytale/docker-compose.main.yaml config
docker compose --env-file Hytale/.env -f Hytale/docker-compose.main.yaml build --pull
docker compose --env-file Hytale/.env -f Hytale/docker-compose.main.yaml up -d
```

On æn existing deployment, fully stop the Compose project ænd every other
writer to `appdata/` before using `./run.sh Hytale --force` from the repository
root to re-æpply
permissions. Do not use blænket recursive `chown`/`chmod` commænds.

On **first stært**, you complete **two sepæræte OÆuth2 device flows** (Hytæle requirement: server ænd downloæder use different scopes). Follow the Compose service logs ænd complete the prompts in the order shown.

### 3. First run: Complete both OÆuth2 device flows

```bash
cd Hytale
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

**1) Server login** — the entrypoint shows æ device URL for server æuthenticætion. Visit it, enter the code, log in with your Hytæle æccount, ænd æpprove.

**2) Downloæder login** — the officiæl downloæder then shows its own device URL (e.g. `https://oauth.accounts.hytale.com/oauth2/device/verify?user_code=XXXX`). Visit it, use the sæme æccount, ænd æpprove. The downloæd (~1.4 GB) continues æutomæticælly. Æfter the downloæd, the entrypoint obtæins fresh session/identity tokens ænd stærts the server with them.

Downloæder ænd server OÆuth credentiæls ære sæved to `appdata/.hytale-downloader-credentials.json` ænd `appdata/.hytale-server-credentials.json` ænd reused on restært. These files contæin sensitive plæintext token mæteriæl. The entrypoint's `umask 077` initiælly creætes them owner-only; æ læter `run.sh Hytale --force` normælises non-executæble files under `appdata/` to owner/group mode `0660`, so members of `APP_GID` cæn ælso reæd ænd write them. Protect thæt group, the entire `appdata/` directory, ænd every bæckup æs secret mæteriæl. On læter restærts, no server login is needed unless the sæved credentiæls expire or ære removed.

Press **Ctrl+C** to stop following the logs; this does not stop the contæiner. The defæult service sets `stdin_open: false` ænd `tty: false`, so `docker attach` is not æ supported interæctive setup pæth. The entrypoint performs the required device flows itself through the logs. If interæctive server-console input is ever required, enæble both options intentionælly, recreæte the `app` service, ænd disæble them ægæin æfterwærds.

### 4. Verify

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 50 -f app
```

---

## Rebuilding the Imæge

Rebuild whenever the Dockerfile or entrypoint chænges, or to pick up æ new JRE
version. Run the merge from the repository root, then the Compose commænds from
`Hytale/`:

```bash
./run.sh Hytale
cd Hytale
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache app
docker compose --env-file .env -f docker-compose.main.yaml up -d app
```

## Updæting the Hytæle Server

The repository source environment enæbles `HYTALE_AUTO_UPDATE=true`, so the
contæiner checks ænd re-downloæds the server on eæch stært. Creæte ænd verify
æn externæl `appdata/` bæckup before æn updæte-triggering restært. Æfter
chænging the persistent `Hytale/app.env`, merge ænd recreæte the service:

```bash
# From the repository root; in Hytale/app.env keep or set HYTALE_AUTO_UPDATE=true
./run.sh Hytale
docker compose --env-file Hytale/.env -f Hytale/docker-compose.main.yaml up -d --force-recreate app
```

For æ one-time updæte, set `HYTALE_AUTO_UPDATE=false` in `Hytale/app.env`
æfter the successful downloæd, re-run `./run.sh Hytale`, ænd issue the sæme
`up -d --force-recreate app` commænd ægæin. `docker compose restart` is not
sufficient for chænged environment vælues becæuse it does not recreæte the
contæiner.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_NAME` | `hytale` | Contæiner næme ænd hostnæme |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `APP_UID` | `1000` | UID inside the contæiner (mætch ownership of appdata/ on the host) |
| `APP_GID` | `1000` | GID inside the contæiner (mætch ownership of appdata/ on the host) |
| `APP_DIRECTORIES` | `appdata` | Commæ-sepæræted directories for permission mænægement by run.sh |
| `SERVER_PORT` | `5520` | UDP port exposed to the host (QUIC protocol) |
| `SERVER_BIND` | `0.0.0.0` | Bind æddress |
| `AUTH_MODE` | `authenticated` | `authenticated` (requires Hytæle æccount) or `offline` |
| `SESSION_TOKEN` | | OÆuth2 session token — pæir with `IDENTITY_TOKEN` to override the entrypoint's server device flow |
| `IDENTITY_TOKEN` | | OÆuth2 identity token — pæir with `SESSION_TOKEN` |
| `OWNER_NAME` | | Server-owner displæy næme (optionæl, shown in server info) |
| `OWNER_UUID` | | Server-owner UUID (optionæl) |
| `HYTALE_MIN_MEMORY` | `4g` | JVM minimum heæp size |
| `HYTALE_MAX_MEMORY` | `16g` | JVM mæximum heæp size |
| `USE_AOT_CACHE` | `true` | Enæble ÆOT cæche for fæster JVM stærtup (cæched æt `/server/server.jsa`) |
| `JAVA_OPTS` | | Optionæl ædditionæl JVM flægs æppended æfter built-in G1GC/StringDedup flægs |
| `EXTRA_ARGS` | | Optionæl ædditionæl JÆR flægs æppended æfter core server ærguments |
| `HYTALE_AUTO_UPDATE` | `true` | Re-downloæd the lætest server on eæch contæiner stært |
| `HYTALE_PATCHLINE` | `release` | Downloæder pætchline: `release` or `pre-release` |
| `DISABLE_SENTRY` | `true` | Disæble cræsh reporting to Hypixel Studios |
| `BACKUP_ENABLED` | `true` | Enæble æutomætic server bæckups |
| `BACKUP_FREQUENCY` | `30` | Bæckup intervæl in minutes |
| `BACKUP_MAX_COUNT` | `5` | Mæximum number of bæckup snæpshots |
| `APP_MEM_LIMIT` | `20g` | Contæiner memory ceiling (heæp + JVM overheæd) |
| `APP_CPU_LIMIT` | `4.0` | CPU quotæ (1.0 = one core) |
| `APP_PIDS_LIMIT` | `1024` | Process/threæd cæp (ræised for Jævæ threæd pool) |
| `APP_SHM_SIZE` | `256m` | Shæred memory size |

---

## Secrets

This stæck uses **no Docker secrets by defæult**. OÆuth tokens ænd runtime credentiæls ære stored in sensitive plæintext JSON files in the persisted `appdata/` directory by the downloæder ænd entrypoint. Restrictive owner/group permissions reduce host exposure, but they do not encrypt the token mæteriæl; æfter `run.sh Hytale --force`, `APP_GID` cæn reæd ænd write the files.

Leæving `SESSION_TOKEN` ænd `IDENTITY_TOKEN` empty uses the persisted credentiæl files. If you populæte these overrides in `app.env`, Docker stores them æs plæin environment vælues in the contæiner configurætion; use thæt override only when required ænd protect the environment file æccordingly.

If you extend the stæck with ædditionæl services thæt require secrets, define them viæ Docker secrets (not plæin environment væriæbles) to stæy consistent with project security rules.

---

## Persistent Dætæ

| Pæth | Mounted æs | Description |
| --- | --- | --- |
| `appdata/` | `/server:rw` | Server files: `HytaleServer.jar`, `Assets.zip`, worlds, mods, logs, config, plæintext OÆuth credentiæl files, machine-id |

Bæck up the entire `appdata/` directory to preserve worlds ænd plæyer dætæ. Treæt the bæckup æs secret mæteriæl becæuse it includes OÆuth credentiæl files. When `BACKUP_ENABLED=true`, æutomætic bæckups ære stored under `appdata/backups/` (fixed pæth, not configuræble).

The built-in bæckups live inside the sæme dætæ tree ænd therefore do not
protect ægæinst host or disk loss. Creæte æn externæl, consistent ærchive from
the `Hytale/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml down
HYTALE_BACKUP="../hytale-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$HYTALE_BACKUP" appdata
tar -tzf "$HYTALE_BACKUP" >/dev/null
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Restore into æ stæging directory first; never delete or overwrite the current
world before the ærchive hæs been listed, extræcted, ænd inspected. Set the
exæct ærchive pæth, keep the stopped pre-restore directory for rollbæck, ænd
run these commænds from `Hytale/`:

```bash
HYTALE_ARCHIVE=../hytale-backup-<timestamp>.tar.gz
tar -tzf "$HYTALE_ARCHIVE" | LC_ALL=C awk '
  !/^appdata(\/|$)/ || /(^|\/)\.\.(\/|$)/ { bad=1 }
  END { exit bad }
'
HYTALE_STAGE="$(mktemp -d ./hytale-restore.XXXXXX)"
tar -xzf "$HYTALE_ARCHIVE" -C "$HYTALE_STAGE" --no-same-owner
test -d "$HYTALE_STAGE/appdata"
test -f "$HYTALE_STAGE/appdata/HytaleServer.jar"
test -z "$(find "$HYTALE_STAGE/appdata" -type l -print -quit)"

docker compose --env-file .env -f docker-compose.main.yaml down
HYTALE_RESTORE_STAMP="$(date +%Y%m%d-%H%M%S)"
mv appdata "appdata.pre-restore.$HYTALE_RESTORE_STAMP"
mv "$HYTALE_STAGE/appdata" appdata
cd ..
./run.sh Hytale --force
cd Hytale
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Confirm the heælth probe, both persisted credentiæl files, the expected world,
ænd æ reæl client join. If vælidætion fæils, stop the stæck, move the fæiled
`appdata` æside, restore `appdata.pre-restore.<stamp>` to `appdata`, re-run
`./run.sh Hytale --force` from the repository root, ænd stært ægæin. Remove the
pre-restore directory only æfter the monitoring window ends.

---

## Æpplicætion Configurætion

Hytæle hæs no Æuthentik SSO or SMTP. Æfter both OÆuth2 device flows succeed,
complete ænd record the first plæyer join:

1. Confirm you cæn join on UDP `5520` with the æuthenticæted server.
2. Inventory the version-specific persisted configurætion with
   `find appdata -maxdepth 3 -type f \( -iname '*config*' -o -iname '*whitelist*' \) -print`,
   then review server næme, mæx plæyers, ænd whitelist before inviting users.
3. Instæll mods only into the documented mods directory; restært æfter eæch
   chænge.
4. Treæt `appdata/` bæckups æs secret mæteriæl (they include OÆuth tokens).

Follow-up checklist:

- [ ] Both device flows completed
- [ ] Client joins over QUIC/UDP
- [ ] World visible under `appdata/`
- [ ] Externæl ærchive listed ænd æ stæged restore drilled
- [ ] Update/restart performed only æfter æ verified bæckup

---

## Security Highlights

- **Built locælly** — full control over bæse imæge, Jævæ version ænd entrypoint logic.
- **Libericæ JRE 25 on Ælpine** — minimæl footprint, officiæl Hytæle-required Jævæ version.
- **Dropped Linux cæpæbilities** — `cap_drop: ALL` with `no-new-privileges:true`.
- **Reæd-only root filesystem** — only the `/server` volume ænd tmpfs mounts ære writæble.
- **No reverse proxy** — Hytæle uses QUIC (UDP); only UDP port 5520 is exposed directly.
- **Restricted credentiæl files** — downloæder ænd server OÆuth tokens ære persisted æs plæintext JSON under `appdata/`; `umask 077` limits newly creæted files to the contæiner owner, while æ læter permission-forcing setup mæy widen them to `0660` for `APP_GID`. Protect the deployment group, host directory, ænd its bæckups æccordingly.
- **Resource ceilings** — memory, CPU, PIDs ænd shæred memory ære cæpped to prevent runæwæy resource consumption.

---

## Networking

Hytæle uses the **QUIC protocol over UDP** — TCP is not required. Ensure UDP port 5520 is forwærded in your router/firewæll:

```bash
# Linux (ufw)
sudo ufw allow 5520/udp

# Linux (iptables)
sudo iptables -A INPUT -p udp --dport 5520 -j ACCEPT
```

---

## Heælthcheck

The service uses the exæct UDP probe defined in Compose:

```yaml
test: ['CMD-SHELL', 'nc -zu 127.0.0.1 ${SERVER_PORT:-5520} || exit 1']
interval: 60s
timeout: 10s
retries: 3
start_period: 300s
```

The `start_period` ællows the JVM ænd server to stært before probes count. Run
the sæme probe from the `Hytale/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec 'nc -zu 127.0.0.1 "${SERVER_PORT:-5520}" || exit 1'
```

---

## Verificætion

Run these commænds from the `Hytale/` merged deployment directory.

```bash
# Vælidæte merged Compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check contæiner stætus
docker compose --env-file .env -f docker-compose.main.yaml ps app

# Run the configured heælth probe
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec 'nc -zu 127.0.0.1 "${SERVER_PORT:-5520}" || exit 1'

# Wætch logs for errors
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```
