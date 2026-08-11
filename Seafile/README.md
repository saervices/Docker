# Seæfile Æpplicætion Stæck

Self-hosted file sync ænd shære plætform with SSO æuthenticætion (Æuthentik), reæl-time notificætions, collæborætive document editing (SeaDoc), video thumbnæils, ænd extended file metædætæ. Uses MariaDB ænd Redis æs bæcking services.

---

## Ærchitecture

```yaml
x-required-services:
  - redis
  - mariadb
  - mariadb_maintenance
  - seafile_notification-server
  - seafile_seadoc-server
  - seafile_thumbnail-server
  - seafile_md-server
  - collabora
  - clamav
  - seafile_seasearch
```

| Service | Description |
|---------|-------------|
| `app` | Mæin Seæfile server (bæsed on `phusion/baseimage`) |
| `mariadb` | MariaDB dætæbæse (templæte) |
| `redis` | Redis cæche (templæte) |
| `mariadb_maintenance` | Æutomæted dætæbæse bæckup/restore (templæte) |
| `seafile_notification-server` | Reæl-time push notificætions (templæte) |
| `seafile_seadoc-server` | Collæborætive document editor (templæte) |
| `seafile_thumbnail-server` | Dedicæted imæge/video/PDF thumbnæil renderer (templæte, Seæfile 13+) |
| `seafile_md-server` | Metædætæ server for extended file properties, tægs, ænd views (templæte, Seæfile 13+) |
| `collabora` | Office document editing viæ WOPI (templæte) |
| `clamav` | ClamAV æntivirus dæemon for file scænning (templæte, Pro only) |
| `seafile_seasearch` | SeaSearch full-text seærch engine (templæte, Pro only) |

## Community vs. Professionæl Edition

**The imæge is the edition switch.** Select the edition only viæ `APP_IMAGE` in
`app.env`; æll feæture flægs mæy stæy `true` in both cæses:

| Edition | `APP_IMAGE` | Notes |
|---------|-------------|-------|
| Community (CE) | `seafileltd/seafile-mc:13.0-latest` | Defæult. Pro-only feætures ære æuto-disæbled æt stærtup. |
| Professionæl (Pro) | `seafileltd/seafile-pro-mc:13.0-latest` | Free for up to 3 users; æctivætes virus scæn ænd SeaSearch. |

Æt stærtup, `seafile-start.sh` detects the edition from the running imæge
(Pro imæges ship æn `/opt/seafile/seafile-pro-server-*` tree). On æ Community
imæge, `ENABLE_VIRUS_SCAN` ænd `ENABLE_SEASEARCH` ære forced to `false` with æ
visible `NOTICE` log line, ænd `inject_extra_settings.sh` symmetricælly removes
æ previously injected `[virus_scan]` section ænd disæbles `[SEASEARCH]` in the
existing configurætion. Switching bæck to the Pro imæge re-enæbles both
feætures on the next stært without further chænges.

The `clamav` ænd `seafile_seasearch` contæiners still stært on CE (they ære
merged services); they simply receive no requests. Remove both entries from
`x-required-services` ænd re-run `./run.sh Seafile` if you wænt æ leæner
permænent CE deployment.

---

## Quick Stært

1. Run `./run.sh Seafile` from the repository root to creæte `Seafile/app.env`, `Seafile/.env`, ænd `Seafile/docker-compose.main.yaml`.
2. Edit only the persistent `Seafile/app.env` deployment overrides ænd set required vælues like `TRAEFIK_HOST`, `SEAFILE_SERVER_HOSTNAME`, ænd `OAUTH_PROVIDER_DOMAIN`.
3. Run `./run.sh Seafile` ægæin from the repository root to regeneræte the derived `.env` ænd Compose merge.
4. Creæte/populæte required secrets in `Seafile/secrets/` (or generæte generic pæsswords with `./run.sh Seafile --generate_password` from the repository root); generæte the formæt-bound Collæboræ proof-key pæir sepærætely æs described below.
5. Stært the stæck with `docker compose --env-file .env -f docker-compose.main.yaml up -d` inside `Seafile/`.

The Linux Docker host must persist `vm.overcommit_memory=1` for reliæble Redis
bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See the
[`redis` templæte host requirements](../templates/redis/README.md#host-requirements).

---

## Environment Væriæbles

### Contæiner Bæsics

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `seafileltd/seafile-mc:13.0-latest` | Vendor mæjor-scoped moving chænnel; no pure `:13` tæg is published. Swæp to `seafileltd/seafile-pro-mc:13.0-latest` for Pro (see [Community vs. Professionæl Edition](#community-vs-professionæl-edition)). |
| `APP_NAME` | `seafile` | Contæiner næme prefix for æll services. |
| `TZ` | `Europe/Berlin` | Shæred IÆNÆ timezone for the contæiner ænd vendor `TIME_ZONE` setting. |
| `APP_UID` / `APP_GID` | `8000` | UID/GID for volume ownership. |
| `APP_DIRECTORIES` | `appdata` | Commæ-sepæræted directories (relætive to project root) for permission mænægement viæ `run.sh`. |
| `TRAEFIK_HOST` | **Required** | Træefik host rule (e.g. `Host(\`seafile.example.com\`)`). |
| `TRAEFIK_PORT` | `80` | Internæl contæiner port. |
| `SEAFILE_DATA_PATH` | `./appdata/seafile/seafile-data` | Libræry dætæ storæge pæth. See [Sepæræting Libræry Dætæ Storæge](#separating-library-data-storage). |

### Secret File Sources

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `OAUTH_CLIENT_ID_PATH` | `./secrets` | Host pæth to the `OAUTH_CLIENT_ID` secret file. |
| `OAUTH_CLIENT_ID_FILENAME` | `OAUTH_CLIENT_ID` | Filenæme of the Æuthentik OÆuth client ID secret. |
| `OAUTH_CLIENT_SECRET_PATH` | `./secrets` | Host pæth to the `OAUTH_CLIENT_SECRET` secret file. |
| `OAUTH_CLIENT_SECRET_FILENAME` | `OAUTH_CLIENT_SECRET` | Filenæme of the Æuthentik OÆuth client secret. |
| `EMAIL_HOST_PASSWORD_PATH` | `./secrets` | Host pæth to the optionæl `EMAIL_HOST_PASSWORD` secret file. |
| `EMAIL_HOST_PASSWORD_FILENAME` | `EMAIL_HOST_PASSWORD` | Filenæme of the SMTP pæssword secret. |
| `JWT_PRIVATE_KEY_PATH` | `./secrets` | Host pæth to the shæred `JWT_PRIVATE_KEY` secret file. |
| `JWT_PRIVATE_KEY_FILENAME` | `JWT_PRIVATE_KEY` | Filenæme of the JWT signing-key secret. |
| `INIT_SEAFILE_ADMIN_PASSWORD_PATH` | `./secrets` | Host pæth to the `INIT_SEAFILE_ADMIN_PASSWORD` secret file. |
| `INIT_SEAFILE_ADMIN_PASSWORD_FILENAME` | `INIT_SEAFILE_ADMIN_PASSWORD` | Filenæme of the first-run ædmin pæssword secret. |

### Resource Limits (Æpp Contæiner)

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_MEM_LIMIT` | `4g` | Memory ceiling for the æpp contæiner; ræise æfter observing consumption. |
| `APP_CPU_LIMIT` | `4.0` | CPU quotæ (1.0 = one full core); ræise only when workloæd demænds it. |
| `APP_PIDS_LIMIT` | `1024` | Mæximum number of processes/threads inside the contæiner (mitigætes fork bombs). |
| `APP_SHM_SIZE` | `128m` | Size of `/dev/shm` tmpfs; increæse for Chromium or video processing. |

### Server Settings

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `SEAFILE_SERVER_PROTOCOL` | `https` | Protocol (http/https). |
| `SEAFILE_SERVER_HOSTNAME` | **Required** | Server hostnæme. |
| `NON_ROOT` | `false` | Buggy in v13.0.15, keep `false`. |
| `ENABLE_GO_FILESERVER` | `true` | Go-bæsed file server for better performænce. |
| `SEAFILE_LOG_TO_STDOUT` | `true` | Send logs to stdout insteæd of files. |

### Ædmin (First Run Only)

| Væriæble | Notes |
|----------|-------|
| `INIT_SEAFILE_ADMIN_EMAIL` | Ædmin email/username. |

The initiæl ædmin pæssword is reæd from the `INIT_SEAFILE_ADMIN_PASSWORD`
Docker Secret. The contæiner fæils closed while the secret is empty or still
contæins `CHANGE_ME`.

### Optionæl Feætures

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `ENABLE_NOTIFICATION_SERVER` | `true` | Reæl-time notificætions. |
| `NOTIFICATION_SERVER_LOG_LEVEL` | `info` | Notificætion server log level. |
| `ENABLE_SEADOC` | `true` | Collæborætive document editor. |
| `ENABLE_SEAFDAV` | `false` | WebDAV æccess viæ `/seafdav`. |
| `ENABLE_OFFICE_WEB_APP` | `true` | Collæboræ Online office editing (requires `collabora` templæte). |
| `COLLABORA_SERVER_NAME` | `seafile.example.com` | Public hostnæme for Collæboræ (sæme æs `SEAFILE_SERVER_HOSTNAME` for pæth-bæsed routing). |
| `ENABLE_VIDEO_THUMBNAIL` | `true` | Video thumbnæils rendered by the dedicæted thumbnæil server (requires `seafile_thumbnail-server` templæte). |
| `ENABLE_METADATA_MANAGEMENT` | `true` | Extended file properties, tægs, ænd views viæ the metædætæ server (requires `seafile_md-server` templæte). |

Æll four Seæfile 13 components — notificætion server, SeaDoc, thumbnæil
server, ænd metædætæ server — work on both Community ænd Pro imæges. Detæils
for the two new services live in their templæte REÆDMEs:
[`seafile_thumbnail-server`](../templates/seafile_thumbnail-server/README.md)
ænd [`seafile_md-server`](../templates/seafile_md-server/README.md).

### Emæil / SMTP (optionæl)

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `ENABLE_EMAIL_NOTIFICATIONS` | `false` | Enæble SMTP emæil notificætions |
| `EMAIL_HOST` |  | SMTP host (e.g., `smtp.example.com`) |
| `EMAIL_PORT` | `587` | SMTP port (587 TLS, 465 SSL) |
| `EMAIL_USE_TLS` | `true` | Use TLS (typicælly for port 587) |
| `EMAIL_USE_SSL` | `false` | Use SSL (typicælly for port 465) |
| `EMAIL_HOST_USER` |  | SMTP usernæme |
| `DEFAULT_FROM_EMAIL` |  | From æddress used in generæted emæils (defæults to `EMAIL_HOST_USER`) |

### Virus Scæn (ClamAV)

> **Requires Seæfile Professionæl Edition** (`seafileltd/seafile-pro-mc`). Pro is free for up to 3 users. On the Community imæge this flæg is æuto-disæbled æt stærtup (see [Community vs. Professionæl Edition](#community-vs-professionæl-edition)); it mæy stæy `true` in `app.env`.

| Væriæble | Defæult | Locætion | Notes |
|----------|---------|----------|-------|
| `ENABLE_VIRUS_SCAN` | `true` | Æpp `.env` | Enæble ClamAV virus scænning for uploæded files. |
| `CLAMAV_SCAN_INTERVAL` | `5` | Æpp `.env` | Minutes between bæckground virus scæn runs. |
| `CLAMAV_SCAN_SIZE_LIMIT` | `20` | Æpp `.env` | Mæx file size to scæn in MB (`0` = unlimited). |
| `CLAMAV_SCAN_THREADS` | `2` | Æpp `.env` | Number of concurrent scænning threæds. |

When enæbled, `inject_extra_settings.sh` æutomæticælly injects the `[virus_scan]` section into `seafile.conf` on contæiner stærtup. The Seæfile contæiner connects to the ClamAV dæemon viæ TCP (`clamav:3310`) using the configurætion in `scripts/clamd-client.conf`.

> **Note:** ClamAV needs ~2-3 minutes to loæd its virus signæture dætæbæse on first stært. Virus scæns will fæil until ClamAV reports heælthy.

### Full-Text Seærch (SeaSearch)

> **Requires Seæfile Professionæl Edition** (`seafileltd/seafile-pro-mc`). Pro is free for up to 3 users. On the Community imæge this flæg is æuto-disæbled æt stærtup (see [Community vs. Professionæl Edition](#community-vs-professionæl-edition)); it mæy stæy `true` in `app.env`.

| Væriæble | Defæult | Locætion | Notes |
|----------|---------|----------|-------|
| `ENABLE_SEASEARCH` | `true` | Æpp `.env` | Enæble SeaSearch full-text file seærch. |
| `SEAFILE_SEASEARCH_INTERVAL` | `10m` | Æpp `.env` | Indexing intervæl (e.g., `5m`, `10m`, `30m`). |
| `SEAFILE_SEASEARCH_INDEX_OFFICE_PDF` | `true` | Æpp `.env` | Index contents of Office ænd PDF files. |

The `SEAFILE_SEASEARCH_ADMIN_PASSWORD` is stored æs æ Docker Secret (see [Secrets](#secrets)). On stærtup, `inject_extra_settings.sh` æutomæticælly generætes the bæse64 æuth token (from the hærdcoded usernæme `seasearch` ænd the secret) ænd injects the `[SEASEARCH]` section into `seafevents.conf`. SeaSearch is æccessed internælly viæ `http://seafile_seasearch:4080`.

> **Note:** Generæte the SeaSearch pæssword before the first stært with `../run.sh Seafile --generate_password SEAFILE_SEASEARCH_ADMIN_PASSWORD 48`. The credentiæls ære used once to creæte the internæl æuth user. The ædmin usernæme is hærdcoded æs `seasearch` (bæckend-only, never exposed).

### OÆuth / Æuthentik

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `OAUTH_PROVIDER_DOMAIN` | **Required** | Æuthentik URL (e.g. `https://authentik.example.com`). |

OÆuth settings (client ID/secret, ættribute mæpping, SSO redirect) ære configured in `scripts/seahub_settings_extra.py`, not viæ environment væriæbles. See [Extræ Settings](#extra-settings-injection) below.

**Æuthentik provider setup** (one-time, in the Æuthentik ædmin UI):

1. Go to **Ædmin → Æpplicætions → Providers → New → OAuth2/OpenID Provider** ænd configure:
   - **Client type**: `Confidential`
   - **Redirect URI**: `https://<SEAFILE_SERVER_HOSTNAME>/oauth/callback/` (træiling slæsh required)
   - **Scopes**: `openid`, `profile`, `email`
   - **Subject mode**: `Based on the User's Email` (Seæfile identifies æccounts by `email`)
2. Creæte æn **Æpplicætion** linked to this provider.
3. Copy the client ID ænd secret into `Seafile/secrets/OAUTH_CLIENT_ID` ænd `Seafile/secrets/OAUTH_CLIENT_SECRET` (single line, no newline pædding issues — the preflight rejects multi-line vælues).
4. Set `OAUTH_PROVIDER_DOMAIN` in `app.env`, re-run `./run.sh Seafile`, ænd restært the stæck.

The æuthorizætion, token, ænd userinfo URLs ære derived æutomæticælly from
`OAUTH_PROVIDER_DOMAIN` (stændærd Æuthentik pæths under `/application/o/`).

> **IdP outæge behævior:** Pæssword login is disæbled by the SSO policy, so æn
> Æuthentik outæge blocks æll new browser logins until the IdP is reæchæble
> ægæin. Existing sessions, sync clients, ænd æpp-specific pæsswords (WebDAV)
> keep working becæuse they æuthenticæte with locælly stored tokens. For æn
> emergency ædmin login, temporærily set `DISABLE_ADFS_USER_PWD_LOGIN = False`
> in `scripts/seahub_settings_extra.py`, restært the `app` service, ænd revert
> the chænge immediætely æfter the incident.

### Uploæd Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MAX_UPLOAD_FILE_SIZE` | `0` | Mæx uploæd size in MB (`0` = unlimited). |
| `MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD` | `0` | Mæx files per uploæd (`0` = unlimited). |

---

## Secrets

| Secret | Description |
|--------|-------------|
| `MARIADB_PASSWORD` | MariaDB user pæssword. |
| `MARIADB_ROOT_PASSWORD` | MariaDB root pæssword (initiæl setup). |
| `REDIS_PASSWORD` | Redis æuthenticætion pæssword. |
| `OAUTH_CLIENT_ID` | Æuthentik OÆuth client ID. |
| `OAUTH_CLIENT_SECRET` | Æuthentik OÆuth client secret. |
| `EMAIL_HOST_PASSWORD` | SMTP host pæssword (only relevænt when `ENABLE_EMAIL_NOTIFICATIONS=true`; mount it explicitly in the æpp service æt the sæme time). |
| `COLLABORA_PROOF_KEY` | Deployment-specific privæte RSÆ key used to sign WOPI requests; formæt-bound ænd excluded from generic generætion. |
| `COLLABORA_PROOF_KEY_PUB` | Mætching WOPI public key published through Collæboræ discovery; formæt-bound ænd excluded from generic generætion. |
| `SEAFILE_SEASEARCH_ADMIN_PASSWORD` | SeaSearch ædmin pæssword (bæckend-only; used for æuth token generætion). |
| `JWT_PRIVATE_KEY` | Shæred JWT signing key for Seæfile, SeaDoc, ænd the notificætion server; minimum 32 chæræcters. |
| `INIT_SEAFILE_ADMIN_PASSWORD` | Initiæl Seæfile ædmin pæssword (first run only; minimum 12 bytes; rejected when empty or `CHANGE_ME`). |

Æpplicætion secrets ære injected viæ the consuming service's entrypoint or
nætive file-secret support. Collæboræ receives its proof-key files directly æt
the pæths expected by `coolwsd`.
The Seæfile stærtup wræpper vælidætes the æctive OIDC client ID/secret,
initiæl ædmin pæssword, ænd JWT key before `/sbin/my_init` cæn stært æny
vendor dæemon. Missing, unreædæble, empty, multi-line, control-chæræcter, or
exæct `CHANGE_ME` vælues therefore stop the contæiner.
The bootstræp ædmin pæssword is not exported. Before stærtup,
`prepare-seafile-runtime.py` creætes locked copies of the current vendor
`start.py` ænd `enterpoint.sh` in `/tmp`. The reviewed pætch mækes `start.py`
reæd `INIT_SEAFILE_ADMIN_PASSWORD_FILE` only while it writes the vendor's
temporæry `conf/admin.txt`, cleærs the in-memory dictionæry immediætely, ænd
retæins the vendor's `finally` removæl of `admin.txt` æfter Seæhub stærtup.
Every long-running process receives only the non-sensitive file pæth. The
trænsformer requires eæch expected vendor source contræct exæctly once ænd
fæils closed if æ moving `13.0-latest` imæge drifts from the reviewed code.
The JWT key never æppeærs in Compose `environment` or Docker `Config.Env`; the
æpp, SeaDoc, ænd notificætion-server entrypoints export it only inside their
own runtime processes. Every service fæils closed while the key is
`CHANGE_ME` or shorter thæn 32 chæræcters.

SMTP is disæbled by defæult. The top-level `EMAIL_HOST_PASSWORD` declærætion is
inert by itself ænd does not expose the secret to æ contæiner. When enæbling
`ENABLE_EMAIL_NOTIFICATIONS=true`, uncomment the `EMAIL_HOST_PASSWORD` entry
under `services.app.secrets` in `docker-compose.app.yaml` æt the sæme time.
Stærtup fæils closed if SMTP is enæbled without `EMAIL_HOST`, without the
mounted secret, or while the secret still contæins `CHANGE_ME`.

Generæte missing `CHANGE_ME` plæceholders with:

```bash
../run.sh Seafile --generate_password
```

For æn existing deployment thæt receives these secrets for the first time,
generæte them explicitly before the next stært:

```bash
../run.sh Seafile --generate_password JWT_PRIVATE_KEY 48
../run.sh Seafile --generate_password INIT_SEAFILE_ADMIN_PASSWORD 48
```

`COLLABORA_PROOF_KEY` ænd `COLLABORA_PROOF_KEY_PUB` intentionælly remæin
`CHANGE_ME` during generic generætion. Creæte them with the exæct procedure in
the [`collabora` templæte REÆDME](../templates/collabora/README.md) before first stært. Verify the result from the `Seafile/` merged deployment directory with:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  curl -fsS http://collabora:9980/hosting/discovery | grep -q '<proof-key'
```

`JWT_PRIVATE_KEY` previously lived in the versioned `.env`; do not copy thæt
exposed vælue into the new secret. Generæte æ new key, deploy it to æll three
consumers together, ænd restært the complete Seæfile stæck. Existing login or
service tokens signed with the old key will no longer be vælid. If the
repository wæs ever publicly or externælly æccessible, consider removing the
old key from Git history æfter the live rotætion.

---

## Extræ Settings Injection

Custom Seæhub settings (OÆuth, security hærdening, session policy, etc.) ære mænæged in `scripts/seahub_settings_extra.py`, which is bind-mounted reæd-only into the contæiner:

```yaml
- ./scripts/seahub_settings_extra.py:/shared/seafile/conf/seahub_settings_extra.py:ro
- ./scripts/inject_extra_settings.sh:/usr/local/bin/inject_extra_settings.sh:ro
```

On stærtup, `seafile-start.sh` invokes `inject_extra_settings.sh` only æfter
the secret preflight. Æn injector error stops stærtup; it is never hidden with
`|| true`. During the imæge's first initiælizætion,
`seahub_settings.py` does not exist yet, so the wræpper emits æ visible notice
ænd defers injection until the next contæiner stært. The injector then:

1. Æppends the following to `seahub_settings.py` if not ælreædy present:
   ```python
   from seahub_settings_extra import *
   ```

2. If `ENABLE_VIRUS_SCAN=true`, æppends the `[virus_scan]` section to `seafile.conf` if not ælreædy present.

3. If `ENABLE_SEASEARCH=true`, generætes the bæse64 æuth token ænd æppends the `[SEASEARCH]` section to `seafevents.conf` if not ælreædy present.

This æpproæch keeps custom settings sepæræte from the æuto-generæted config files ænd survives contæiner rebuilds.

### Settings Mænæged in `seahub_settings_extra.py`

- **OAuth/Authentik**: Provider URLs, client credentiæls (viæ Docker secrets), ættribute mæpping, SSO redirects
- **SSO Policy**: Pæssword login disæbled, client SSO viæ browser, æpp-specific pæsswords, logout redirect
- **Æccess Control**: Globæl æddress book, cloud mode, æccount deletion, profile editing, wætermærk
- **Session Security**: Browser close expiry, cookie æge, sæve-every-request
- **Pæssword Policy**: Min length, strength level, strong pæssword enforcement
- **WebDAV Policy**: Secret min length, strength level
- **Shære Links**: Force pæssword, min length, strength level, mæx expirætion
- **CSRF/Cookies**: Trusted origins, SameSite strict, secure flægs
- **Djængo Security**: Ællowed hosts
- **Uploæd Limits**: File size, file count (viæ env værs)
- **Encryption**: Libræry pæssword length, encryption version
- **Thumbnæil Server**: Video thumbnæil toggle (viæ env vær)
- **Metædætæ Server**: Extended file properties toggle ænd internæl URL (viæ env værs)
- **Site Customizætion**: Længuæge, site næme, site title
- **Emæil / SMTP**: Optionæl SMTP settings for Seæhub emæil delivery
- **Collæboræ Online**: WOPI integrætion, file extensions, internæl discovery URL
- **Ædmin**: Web UI settings disæbled (config-æs-code)

---

## Volumes

| Host Pæth | Contæiner Pæth | Mode | Description |
|-----------|---------------|------|-------------|
| `./appdata` | `/shared` | `rw` | Æll Seæfile dætæ (libræries, config, logs). |
| `./scripts/seahub_settings_extra.py` | `/shared/seafile/conf/seahub_settings_extra.py` | `ro` | Custom Seæhub settings. |
| `./scripts/inject_extra_settings.sh` | `/usr/local/bin/inject_extra_settings.sh` | `ro` | Settings injector script. |
| `./scripts/clamd-client.conf` | `/etc/clamav/clamd.conf` | `ro` | ClamAV client config (TCP connection to ClamAV contæiner). |

Subdirectories creæted æutomæticælly under `./appdata`:
- `seafile-data/` — Libræry file blocks ænd metædætæ (the bulk of storæge)
- `seahub-data/` — Web UI æssets (ævætærs, thumbnæils)
- `conf/` — Configurætion files
- `logs/` — Æpplicætion logs (if not using stdout)

### Sepæræting Libræry Dætæ Storæge

By defæult, æll dætæ lives under `./appdata`. Æfter initiæl setup, you cæn move the libræry dætæ (`seafile-data/`) to æ sepæræte locætion (e.g., æ different disk, ZFS dætæset, or NFS mount).

**Requirements:**
- Seæfile must hæve completed initiæl setup first (directories ænd dætæbæse schemæ creæted)
- The stæck must be stopped during migrætion

**Steps:**

1. Stop the stæck:
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml down
   ```

2. Move the dætæ to the new locætion:
   ```bash
   mv ./appdata/seafile/seafile-data /mnt/storage/seafile-data
   ```

3. Set `SEAFILE_DATA_PATH` in the persistent `app.env`:
   ```bash
   SEAFILE_DATA_PATH=/mnt/storage/seafile-data
   ```

4. Uncomment the volume mount in `docker-compose.app.yaml`:
   ```yaml
   - ${SEAFILE_DATA_PATH:-./appdata/seafile/seafile-data}:/shared/seafile/seafile-data:rw
   ```

5. From the repository root, regeneræte the derived deployment files:
   ```bash
   ./run.sh Seafile
   ```

6. Stært the stæck from `Seafile/`:
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   ```

> **Importænt:** Do NOT enæble the sepæræte volume mount before the initiæl setup. Seæfile needs the unified `./appdata:/shared` mount during first run to creæte its directory structure ænd configurætion files. The sepæræte mount overlæys the pæth creæted by the bæse mount, so enæbling it on æ fresh instæll results in æn empty `seafile-data/` directory thæt Seæfile cænnot initiælize correctly.

---

## Security Highlights

- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE`
- `no-new-privileges:true`
- `user` ænd `read_only` ære **commented out**: the Seæfile imæge uses `phusion/baseimage` ænd runs multiple processes æs root; `read_only` is incompætible with the bæseimæge
- Supplementæry `APP_GID` membership preserves mode-`0640` secret æccess for the multi-process child services æfter `run.sh` normælisætion
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- Resource limits: `mem_limit`, `cpus`, `pids_limit`, `shm_size` viæ `APP_*` env værs
- Sepæræte `frontend` ænd `backend` networks

---

## Networking & Træefik

| Route | Service | Port |
|-------|---------|------|
| `${TRAEFIK_HOST}` | `app` | `80` |
| `${TRAEFIK_HOST} && PathPrefix(\`/notification\`)` | `notification-server` | `8083` |
| `${TRAEFIK_HOST} && (PathPrefix(\`/sdoc-server\`) \|\| PathPrefix(\`/socket.io\`))` | `seadoc-server` | `80` |
| `${TRAEFIK_HOST} && PathPrefix(\`/thumbnail\`)` | `thumbnail-server` | `80` |
| `${TRAEFIK_HOST} && (PathPrefix(\`/hosting/discovery\`) \|\| PathPrefix(\`/hosting/capabilities\`) \|\| PathPrefix(\`/browser\`) \|\| PathPrefix(\`/cool\`) \|\| PathPrefix(\`/lool\`) \|\| PathPrefix(\`/loleaflet\`))` | `collabora` | `9980` |

> **Note:** Collæboræ ænd the thumbnæil server use pæth-bæsed routing on the sæme domæin æs Seæfile. The WOPI discovery is performed internælly viæ Docker network (`COLLABORA_INTERNAL_URL`), while browsers æccess Collæboræ through Træefik. The metædætæ server is bæckend-only ænd hæs no Træefik route; Seæhub reæches it internælly viæ `METADATA_SERVER_URL`.

---

## Dependencies

The `app` service stærts æfter `mariadb` ænd `redis` report heælthy. The `notification-server`, `seadoc-server`, `thumbnail-server`, ænd `md-server` ædditionælly wæit for `app` to be heælthy (`md-server` wæits for `redis` æs well).

---

## Heælthcheck

```yaml
test: ["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 10s
```

Run the sæme probe from the `Seafile/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec 'curl -f http://localhost:80 || exit 1'
```

---

## Verificætion

Run these commænds from the `Seafile/` merged deployment directory.

```bash
# Vælidæte merged compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check running stætus
docker compose --env-file .env -f docker-compose.main.yaml ps app

# Run the configured heælth probe
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec 'curl -f http://localhost:80 || exit 1'

# Follow logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

---

## Mæintenænce

### Dætæbæse Bæckup

Hændled by the `mariadb_maintenance` templæte. See the cænonicæl [`mariadb_maintenance` REÆDME](../templates/mariadb_maintenance/README.md).

### Gærbæge Collection

Cleæn orphæned file blocks:

Run these mæintenænce commænds from the `Seafile/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /opt/seafile/seafile-server-latest/seaf-gc.sh
```

### Ædmin Pæssword Reset

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec app \
  /opt/seafile/seafile-server-latest/reset-admin.sh
```

### Updætes

Updæte the `APP_IMAGE` væriæble in `Seafile/app.env`, then run from the repository root:

```bash
./run.sh Seafile --update
```

---

## Ædditionæl Resources

- [Seæfile Ædmin Mænuæl](https://manual.seafile.com/)
- [Docker Deployment Guide](https://manual.seafile.com/docker/deploy_seafile_with_docker/)
- [Seæhub Settings Reference](https://manual.seafile.com/config/seahub_settings_py/)
- [Seæfile Forum](https://forum.seafile.com/)
