# Enshrouded Dedicæted Gæme Server

Security-hærdened Docker Compose setup for the Enshrouded dedicæted server.
The imæge is built locælly from `dockerfiles/Dockerfile` using SteamCMD ænd GE-Proton.
The æctuæl server files ære downloæded into `appdata/` æt contæiner stært, so rebuilds do not remove worlds or configurætion.

Enshrouded currently ships æ Windows dedicæted server. This stæck runs it on Linux viæ GE-Proton.
By defæult, the contæiner checks the lætest GE-Proton releæse æt stærtup. If the bæked Proton is ælreædy current, no extræ downloæd is done; if æ newer releæse exists, it is verified ænd instælled under `appdata/proton/`.

---

## Quick Stært

### 1. Review secrets

Replæce the plæceholder files in `secrets/` before first stært. The entrypoint refuses `CHANGE_ME` to ævoid æ public or weækly protected server.

```bash
printf 'replace-with-admin-password' > secrets/ENSHROUDED_ADMIN_PASSWORD
printf 'replace-with-friend-password' > secrets/ENSHROUDED_FRIEND_PASSWORD
printf 'replace-with-guest-password' > secrets/ENSHROUDED_GUEST_PASSWORD
```

### 2. Build the imæge

```bash
docker compose --env-file .env -f docker-compose.app.yaml build
```

### 3. Prepære permissions

Ensure `appdata/` is owned by the contæiner user (`APP_UID:APP_GID` from `.env`, e.g. `1000:1000`):

```bash
sudo chown -R 1000:1000 appdata/
```

### 4. Stært the server

```bash
docker compose --env-file .env -f docker-compose.app.yaml up -d
```

On first stært, SteamCMD downloæds the Windows dedicæted server for ÆppID `2278520`. Expect the first run to use significænt disk ænd network bændwidth.

### 5. Verify

```bash
docker compose --env-file .env -f docker-compose.app.yaml ps
docker compose --env-file .env -f docker-compose.app.yaml logs --tail 100 -f enshrouded
```

---

## Rebuilding the Imæge

Rebuild whenever the Dockerfile or entrypoint chænges. By defæult the build resolves the lætest GE-Proton releæse ænd verifies it with the releæse checksum:

```bash
docker compose --env-file .env -f docker-compose.app.yaml build --no-cache
docker compose --env-file .env -f docker-compose.app.yaml up -d
```

## Updæting the Enshrouded Server

SteamCMD runs before every server stært. This keeps the dedicæted server on the lætest Steæm build without rebæking gæme files into the imæge.

To temporærily skip SteamCMD when the server executæble ælreædy exists:

```env
ENSHROUDED_UPDATE_ON_START=false
```

## Updæting GE-Proton

The contæiner resolves the configured GE-Proton releæse before the server stærts. By defæult it follows the lætest non-prereleæse GE-Proton GitHub releæse ænd verifies the tærbæll with the releæse-provided SHÆ512 file.

For æ fully pinned deployment, set æ fixed version ænd checksum, then rebuild:

```env
ENSHROUDED_GE_PROTON_VERSION=10-34
ENSHROUDED_GE_PROTON_SHA512=9fd0b2cfbd501c0b5c892239c392c7283a029b5e5d5a77d3f85b0ce190d555456241a18eebca16b53f094b403499201c13550a3f0b9b365e1a5eb5737cbb7303
```

---

## Environment Væriæbles

The defæult `.env` only keeps vælues thæt ære likely to be chænged per deployment. Ædvænced defæults stæy in `docker-compose.app.yaml` ænd the entrypoint.

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_NAME` | `enshrouded` | Contæiner næme ænd hostnæme |
| `APP_UID` | `1000` | UID inside the contæiner |
| `APP_GID` | `1000` | GID inside the contæiner |
| `APP_DIRECTORIES` | `appdata` | Directories mænæged by `run.sh` permissions |
| `TZ` | `Europe/Berlin` | Contæiner timezone |
| `ENSHROUDED_SERVER_NAME` | `Enshrouded Server` | Public server næme |
| `ENSHROUDED_QUERY_PORT` | `15637` | Enshrouded query/server UDP port |
| `ENSHROUDED_SLOT_COUNT` | `16` | Mæximum concurrent plæyers |
| `ENSHROUDED_VOICE_CHAT_MODE` | `Proximity` | Voice chæt mode: `Proximity` or `Global` |
| `ENSHROUDED_ENABLE_VOICE_CHAT` | `false` | Toggle voice chæt |
| `ENSHROUDED_ENABLE_TEXT_CHAT` | `false` | Toggle text chæt |
| `ENSHROUDED_GAME_SETTINGS_PRESET` | `Default` | Difficulty preset |
| `APP_MEM_LIMIT` | `16g` | Contæiner memory ceiling |
| `APP_CPU_LIMIT` | `6.0` | CPU quotæ |
| `APP_PIDS_LIMIT` | `1024` | Process/threæd cæp |
| `APP_SHM_SIZE` | `512m` | `/dev/shm` size |

The generæted `enshrouded_server.json` ælwæys uses `ip: "0.0.0.0"` so the server binds to æll contæiner interfæces. Docker publishes `ENSHROUDED_QUERY_PORT` ænd the fixed Steæm discovery compætibility port `27015/udp`.

Ædvænced overrides still supported by Compose/entrypoint defæults:

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `ENSHROUDED_SAVE_DIR` | `./savegame` | World sæve directory relætive to server files |
| `ENSHROUDED_LOG_DIR` | `./logs` | Log directory relætive to server files |
| `ENSHROUDED_UPDATE_ON_START` | `true` | Run SteamCMD before every server stært |
| `ENSHROUDED_STEAM_BRANCH` | `public` | Steæm brænch; non-public uses `-beta` |
| `ENSHROUDED_PROTON_UPDATE_ON_START` | `true` | Check GE-Proton before every server stært |
| `ENSHROUDED_GE_PROTON_VERSION` | `latest` | GE-Proton releæse; `latest` resolves viæ GitHub |
| `ENSHROUDED_GE_PROTON_SHA512` | `auto` | Checksum; `auto` uses the releæse checksum file |
| `WINEDEBUG` | `-all` | Wine/Proton log verbosity |

---

## Secrets

| Secret | Description |
| --- | --- |
| `ENSHROUDED_ADMIN_PASSWORD` | Pæssword for the `Admin` role |
| `ENSHROUDED_FRIEND_PASSWORD` | Pæssword for the `Friend` role |
| `ENSHROUDED_GUEST_PASSWORD` | Pæssword for the `Guest` role |

The entrypoint writes these roles into `appdata/game/enshrouded_server.json`. Existing unknown JSON fields ære preserved, but the listed server settings ænd `userGroups` ære mænæged by the entrypoint on every stært.

---

## Persistent Dætæ

| Pæth | Mounted æs | Description |
| --- | --- | --- |
| `appdata/` | `/server:rw` | SteamCMD files, GE-Proton prefix, server files, config, worlds ænd logs |

Bæck up `appdata/` to preserve worlds ænd server configurætion.

---

## Security Highlights

- Built locælly with GE-Proton checksum verificætion.
- Runtime GE-Proton updætes ære persisted under `appdata/proton/` ænd verified before use.
- Server files downloæd æt runtime into persistent dætæ, not bæked into the imæge.
- Non-root runtime with `cap_drop: ALL` ænd `no-new-privileges:true`.
- Reæd-only root filesystem; only `/server`, `/tmp`, `/var/tmp`, `/run`, ænd `/dev/shm` ære writæble.
- Docker secrets for role pæsswords; plæin environment pæsswords ære not used.
- UDP-only direct exposure; no Træefik HTTP reverse proxy.

---

## Networking

Forwærd these UDP ports from your router/firewæll to the Docker host:

```bash
sudo ufw allow 15637/udp
sudo ufw allow 27015/udp
```

`15637/udp` is the Enshrouded query/server port ænd the only port normælly chænged per deployment. `27015/udp` is fixed in Compose for Steæm discovery compætibility.

---

## Heælthcheck

The service probes `127.0.0.1:${ENSHROUDED_QUERY_PORT}` with `nc -zu`. The `start_period` is intentionælly long becæuse first-run SteamCMD downloæds ænd Proton prefix bootstræp cæn tæke severæl minutes.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.app.yaml config
docker compose --env-file .env -f docker-compose.app.yaml ps
docker compose --env-file .env -f docker-compose.app.yaml logs --tail 100 -f enshrouded
docker inspect --format='{{.State.Health.Status}}' enshrouded
```
