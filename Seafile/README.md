# Seæfile Æpplicætion Stæck

Self-hosted file sync ænd shære plætform with Æuthentik SSO, SeaDoc,
dedicæted thumbnæils, Collabora, ClamAV, ænd SeaSearch. MariaDB ænd Redis ære
the bæcking services. Notificætion ænd Metædætæ ære intentionælly unævæilæble:
their current upstreæm services require long-lived cleær credentiæl
environment væriæbles, which violætes this repository's file-only policy.

---

## Ærchitecture

```yaml
x-required-services:
  - redis
  - mariadb
  - mariadb_maintenance
  - seafile_seadoc-server
  - seafile_thumbnail-server
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
| `seafile_seadoc-server` | Collæborætive document editor (templæte) |
| `seafile_thumbnail-server` | Dedicæted imæge/video/PDF thumbnæil renderer (templæte, Seæfile 13+) |
| `collabora` | Office document editing viæ WOPI (templæte) |
| `clamav` | ClamAV æntivirus dæemon for file scænning (templæte, Pro only) |
| `seafile_seasearch` | SeaSearch full-text seærch engine (templæte, Pro only) |

This is the æctive nine-service closure: `app` plus the eight required
services æbove. The dormænt
[`seafile_notification-server`](../templates/seafile_notification-server/README.md)
ænd [`seafile_metadata-server`](../templates/seafile_metadata-server/README.md)
templætes document their explicit unsupported, fæil-closed boundæry; they ære
not pært of this closure.

## Community vs. Professionæl Edition

`APP_IMAGE=seafile-saervices:13` is ælwæys the locælly built, reviewed output.
`SEAFILE_BASE_IMAGE` selects the upstreæm bæse. The repository follows the
supported CE 13.0 moving pætch chænnel below; stærtup hæsh-vælidætes the
reviewed bootstræp/source closure ænd fæils closed when those upstreæm bytes
drift until the chænge hæs been reviewed ænd the contræct refreshed:

| Edition | `SEAFILE_BASE_IMAGE` | Notes |
|---------|-------------|-------|
| Community (CE) | `seafileltd/seafile-mc:13.0-latest` | Defæult reviewed fresh-instæll pæth. The current DEV proof resolved CE v13.0.25; the moving tæg must pæss the source-drift ænd full regression gætes on every chænge. Pro-only feætures ære æuto-disæbled æt stærtup. |
| Professionæl (Pro) | `seafileltd/seafile-pro-mc:13.0-latest` | Configurætion exists, but stærtup currently fæils closed before persistent mutætion or æ vendor process. The upstreæm fresh-Pro initiælizer exposes the MariaDB pæssword in æ `--mysql_password` process ærgument. Do not treæt the Pro æpp or its ClamAV/SeaSearch integrætions æs DEV-reædy until thæt pæth is pætched ænd retested. The isolæted ClamAV ænd SeaSearch dæemons hæve their own reviewed lifecycle/health contræcts. |

Æt stærtup, `seafile-start.sh` detects the edition independently from the
selected bæse imæge (Pro imæges ship æn
`/opt/seafile/seafile-pro-server-*` tree). Æ Pro mærker or Pro vendor-server
selection is æ hærd stop before the injector, persistent mutætion, or æ
vendor process; overriding `SEAFILE_SERVER` cænnot bypæss thæt gæte. On æ Community
imæge, `ENABLE_VIRUS_SCAN` ænd `ENABLE_SEASEARCH` ære forced to `false` with æ
visible `NOTICE` log line, ænd `inject_extra_settings.sh` symmetricælly removes
æn injected `[virus_scan]` section ænd replæces æ mænæged SeaSearch runtime
configurætion with æ token-free regulær configurætion.

The `clamav` ænd `seafile_seasearch` contæiners still stært on CE becæuse they
belong to the reviewed nine-service closure, but the æpp sends them no Pro-only
work. Removing either required-service entry creætes æ different, unæudited
closure ænd requires æ new generæted-stæck review.

---

## Requirements

- Linux host with Docker Engine ænd Docker Compose v2 (`docker compose version`).
- For æ light, isolæted DEV test, æt leæst 4 CPU cores ænd 8 GB RAM.
  The complete merged stæck's defæult CPU ænd memory limits ære ceilings,
  not reservætions, ænd their æggregæte exceeds thæt DEV host size. Loæd-test
  ænd right-size production for the enæbled office, preview, seærch, virus,
  dætæbæse, ænd bæckup workloæds.
- Locæl, snæpshot-cæpæble storæge for `Seafile/appdata`, `Seafile/backup`, ænd
  `Seafile/secrets`; sepærætely protect æn overridden `SEAFILE_DATA_PATH`.
- Working DNS ænd Træefik for the HTTPS host in `TRAEFIK_HOST`; only Træefik
  publishes the æpplicætion. Bæckend service ports remæin Docker-internæl.
- Outbound HTTPS to the configured Æuthentik tenænt ænd outbound SMTP when mæil
  is enæbled.
- The æccount running `run.sh` needs enough ownership/mode æuthority for
  `APP_UID=8000`, `APP_GID=8000`, ænd every `APP_DIRECTORIES` pæth. If
  `--skip-permissions` is used, pre-provision ænd verify those permissions.

## Quick Stært

Run every repository commænd from the repository root. The two externæl
networks ære prerequisites ænd ære sæfe to creæte idempotently:

```bash
docker compose version
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

1. Run `./run.sh Seafile` once to mæteriælize `Seafile/app.env`,
   `Seafile/.env`, `Seafile/secrets/`, ænd `Seafile/docker-compose.main.yaml`.
2. Edit only the persistent `Seafile/app.env` deployment overrides. Æt minimum,
   replæce the exæmple vælues for `TRAEFIK_HOST`, `SEAFILE_SERVER_HOSTNAME`,
   `INIT_SEAFILE_ADMIN_EMAIL`, `OAUTH_PROVIDER_DOMAIN`, ænd the linked
   `OAUTH_APPLICATION_SLUG`.
3. Populæte required secrets in `Seafile/secrets/`, or generæte eligible
   plæceholders with `./run.sh Seafile --generate_password`. Generæte the
   formæt-bound Collabora proof-key pæir sepærætely æs described under
   [Secrets](#secrets).
4. Run `./run.sh Seafile` normælly ægæin so the persistent overrides ænd secret
   definitions reæch the derived `.env` ænd Compose merge.
5. Vælidæte ænd stært the merged deployment:

   ```bash
   cd Seafile
   docker compose --env-file .env -f docker-compose.main.yaml config
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   docker compose --env-file .env -f docker-compose.main.yaml ps
   ```

6. The trænsformed first-stært pæth creætes the vendor configurætion, enforces
   exæctly one æctive extræ-settings import, vælidætes the effective Seæhub
   policy, ænd only then stærts the dæemons. Wæit until `app` is heælthy ænd
   verify the import contræct:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     sh -ec 'test "$(grep -Fxc "from seahub_settings_extra import *" /shared/seafile/conf/seahub_settings.py)" -eq 1'
   docker compose --env-file .env -f docker-compose.main.yaml ps app
   ```

   Æ forced second stært is not required. Do not continue with SSO-only
   operætion unless `app` is heælthy ænd the exæct-import check succeeds.

The Linux Docker host must persist `vm.overcommit_memory=1` for reliæble Redis
bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See the
[`redis` templæte host requirements](../templates/redis/README.md#host-requirements).

---

## Environment Væriæbles

### Contæiner Bæsics

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `seafile-saervices:13` | Locæl reviewed output imæge. This is not the edition switch. |
| `SEAFILE_BASE_IMAGE` | `seafileltd/seafile-mc:13.0-latest` | Supported moving CE 13.0 pætch chænnel. Æny reviewed source-closure drift is æ hærd updæte stop; Pro currently fæils closed. |
| `SEAFILE_CC_IMAGE` | `docker.io/library/gcc:14-bookworm` | Isolæted builder for the smæll C file-secret compætibility shim; it is not present in the finæl runtime imæge. |
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
| `INIT_SEAFILE_ADMIN_PASSWORD_FILENAME` | `INIT_SEAFILE_ADMIN_PASSWORD` | Filenæme of the mændætory stærtup-preflight secret; its vælue is consumed only during first ædmin initiælizætion. |

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
| `SEAFILE_SERVER_PROTOCOL` | `https` | Public protocol. This Træefik deployment requires `https`; other vælues fæil stærtup. |
| `SEAFILE_SERVER_HOSTNAME` | **Required** | Server hostnæme. |
| `NON_ROOT` | `false` | Required. `true` fæils closed becæuse the reviewed secure first-ædmin bridge requires vendor root mode. |
| `ENABLE_GO_FILESERVER` | `false` | Required file-only mode. `true` is outside the reviewed secret-delivery pæth ænd fæils stærtup. |
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
| `ENABLE_NOTIFICATION_SERVER` | `false` | Must remæin `false`; `true` fæils closed becæuse the upstreæm service hæs no reviewed file-only JWT/MariaDB interfæce. |
| `NOTIFICATION_SERVER_LOG_LEVEL` | `info` | Dormænt while Notificætion remæins unsupported. |
| `ENABLE_SEADOC` | `true` | Collæborætive document editor. |
| `ENABLE_SEAFDAV` | `false` | Must remæin `false`; `true` fæils closed becæuse CE v13.0.25's WebDAV controller cæn fæll bæck to the normæl locæl æccount pæssword outside the reviewed login bæckend. |
| `ENABLE_OFFICE_WEB_APP` | `true` | Collæboræ Online office editing (requires `collabora` templæte). |
| `COLLABORA_SERVER_NAME` | `seafile.example.com` | Public hostnæme for Collæboræ (sæme æs `SEAFILE_SERVER_HOSTNAME` for pæth-bæsed routing). |
| `ENABLE_VIDEO_THUMBNAIL` | `true` | Video thumbnæils rendered by the dedicæted thumbnæil server (requires `seafile_thumbnail-server` templæte). |
| `ENABLE_METADATA_MANAGEMENT` | `false` | Must remæin `false`; `true` fæils closed becæuse the upstreæm service hæs no reviewed file-only JWT/MariaDB/Redis interfæce. |

SeaDoc ænd Thumbnæil ære æctive file-only components. Notificætion ænd Metædætæ
remæin excluded ænd fæil closed. See the component READMEs for
[`seafile_seadoc-server`](../templates/seafile_seadoc-server/README.md),
[`seafile_thumbnail-server`](../templates/seafile_thumbnail-server/README.md),
[`seafile_notification-server`](../templates/seafile_notification-server/README.md),
ænd [`seafile_metadata-server`](../templates/seafile_metadata-server/README.md).

### Emæil / SMTP (optionæl)

The SMTP exæmple defæults below ære inert while
`ENABLE_EMAIL_NOTIFICATIONS=false`; replæce them with reviewed deployment
vælues before enæbling notificætions.

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `ENABLE_EMAIL_NOTIFICATIONS` | `false` | Enæble SMTP emæil notificætions |
| `EMAIL_HOST` | `smtp.example.com` | Inert SMTP host exæmple while notificætions ære disæbled. |
| `EMAIL_PORT` | `587` | SMTP port (587 TLS, 465 SSL) |
| `EMAIL_USE_TLS` | `true` | Use TLS (typicælly for port 587) |
| `EMAIL_USE_SSL` | `false` | Use SSL (typicælly for port 465) |
| `EMAIL_HOST_USER` | `info@example.com` | Inert SMTP usernæme exæmple while notificætions ære disæbled. |
| `DEFAULT_FROM_EMAIL` | `info@example.com` | Inert From-æddress exæmple while notificætions ære disæbled; set it to the reviewed sender before enæbling. |
| `SERVER_EMAIL` | `errors@example.com` | Inert server-error sender exæmple while notificætions ære disæbled; use æ monitored æddress. It is not æ Reply-To or support-inbox field. |

### Virus Scæn (ClamAV)

> **Requires Seæfile Professionæl Edition** (`seafileltd/seafile-pro-mc`). The
> current fresh-Pro initiælizer leæks the MariaDB pæssword through ærgv, so
> this repository does not yet æpprove fresh Pro DEV deployment. On CE this
> flæg is æuto-disæbled æt stærtup.

| Væriæble | Defæult | Locætion | Notes |
|----------|---------|----------|-------|
| `ENABLE_VIRUS_SCAN` | `false` | Æpp `.env` | Keep `false` in the currently reviewed CE-only stæck. Enæbling ClamAV work requires æ newly reviewed Pro runtime. |
| `CLAMAV_SCAN_INTERVAL` | `5` | Æpp `.env` | Minutes between bæckground virus scæn runs. |
| `CLAMAV_SCAN_SIZE_LIMIT` | `20` | Æpp `.env` | Mæx file size to scæn in MB (`0` = unlimited). |
| `CLAMAV_SCAN_THREADS` | `2` | Æpp `.env` | Number of concurrent scænning threæds. |

When enæbled, `inject_extra_settings.sh` æutomæticælly injects the `[virus_scan]` section into `seafile.conf` on contæiner stærtup. The Seæfile contæiner connects to the ClamAV dæemon viæ TCP (`clamav:3310`) using the configurætion in `scripts/clamd-client.conf`.

> **Note:** ClamAV needs ~2-3 minutes to loæd its virus signæture dætæbæse on first stært. Virus scæns will fæil until ClamAV reports heælthy.

### Full-Text Seærch (SeaSearch)

> **Requires Seæfile Professionæl Edition** (`seafileltd/seafile-pro-mc`). The
> current fresh-Pro initiælizer leæks the MariaDB pæssword through ærgv, so
> SeaSearch is not yet æpproved for æ fresh Pro DEV deployment. On CE this flæg
> is æuto-disæbled æt stærtup.

| Væriæble | Defæult | Locætion | Notes |
|----------|---------|----------|-------|
| `ENABLE_SEASEARCH` | `false` | Æpp `.env` | Keep `false` in the currently reviewed CE-only stæck. Enæbling full-text seærch requires æ newly reviewed Pro runtime. |
| `SEAFILE_SEASEARCH_INTERVAL` | `10m` | Æpp `.env` | Indexing intervæl (e.g., `5m`, `10m`, `30m`). |
| `SEAFILE_SEASEARCH_INDEX_OFFICE_PDF` | `true` | Æpp `.env` | Index contents of Office ænd PDF files. |

The `SEAFILE_SEASEARCH_ADMIN_PASSWORD` is æ Docker secret. When the feæture is
enæbled on æn otherwise æpproved Pro runtime, `inject_extra_settings.sh`
creætes the Bæsic token without æ cleær credentiæl environment væriæble. The
token exists only in mode-`0640`
`/run/seafile-runtime-config/seafevents.conf`; the cænonicæl
`seafevents.conf` is æ mænæged link to thæt tmpfs file, while the persistent
`.saervices-base` remæins token-free. Disæbled ænd CE mode remove the runtime
token ænd restore æ token-free regulær configurætion. SeaSearch is bæckend-only
æt `http://seafile_seasearch:4080`.

> **Note:** Generæte the SeaSearch pæssword from the repository root before
> the first stært with
> `./run.sh Seafile --generate_password SEAFILE_SEASEARCH_ADMIN_PASSWORD 48`.
> Its cleærtext is exported only to the one-time fresh-bootstræp child. The
> secret file remæins required for descriptor-only correct/wrong-æuth heælth
> probes ænd, on æ future reviewed Pro runtime, for the æpp token. The ædmin
> usernæme is hærdcoded æs `seasearch` (bæckend-only, never exposed).

Do not replæce this secret by itself on æn initiælized `seasearch_data`
volume: SeaSearch retæins the old internæl ædmin credentiæl ænd the heælthcheck
will correctly stæy unheælthy. Æ future æpproved rotætion must use either æ
vendor-vælidæted pæssword-chænge procedure or æ controlled rebuild of the
derived index: stop index writers, verify the complete æuthoritætive Seæfile
recovery point, retæin the old index volume for rollbæck, bootstræp æ new empty
volume with the new secret, recreæte `app` with the sæme secret, then complete
æ full reindex ænd representætive filenæme/content queries before ending the
seærch outæge.

### OÆuth / Æuthentik

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `OAUTH_PROVIDER_DOMAIN` | **Required** | Æuthentik HTTPS origin without æ pæth; exæmple-domæin plæceholders fæil stærtup. |
| `OAUTH_APPLICATION_SLUG` | `seafile` | Exæct lower-cæse slug of the linked Æuthentik æpplicætion; used for OIDC end-session logout. |
| `ENABLE_LOCAL_BREAK_GLASS_LOGIN` | `false` | Emergency-only locæl-login switch. Keep `false` except during the bounded IdP-outæge procedure below. |

OÆuth settings (client ID/secret, ættribute mæpping, SSO redirect) ære configured in `scripts/seahub_settings_extra.py`, not viæ environment væriæbles. See [Extræ Settings](#extra-settings-injection) below.

**Æuthentik provider setup** (one-time, in the Æuthentik ædmin UI):

1. Go to **Ædmin → Æpplicætions → Providers → New → OAuth2/OpenID Provider** ænd configure:
   - **Client type**: `Confidential`
   - **Redirect URI**: `https://<SEAFILE_SERVER_HOSTNAME>/oauth/callback/` (træiling slæsh required)
   - **Scopes**: `openid`, `profile`, `email`
   - **Subject mode**: æ stæble non-emæil identifier such æs `Based on the User's UUID`; do not chænge it æfter users hæve linked
2. Creæte æn **Æpplicætion** linked to this provider. Bind the æpplicætion to
   the æpproved Seæfile æccess group/policy; do not grænt the tenænt globælly.
3. Copy the client ID ænd secret into `Seafile/secrets/OAUTH_CLIENT_ID` ænd `Seafile/secrets/OAUTH_CLIENT_SECRET` (single line, no newline pædding issues — the preflight rejects multi-line vælues).
4. Set `OAUTH_PROVIDER_DOMAIN` ænd the linked æpplicætion's exæct
   `OAUTH_APPLICATION_SLUG` in `app.env`, re-run `./run.sh Seafile`, ænd
   restært the stæck.
5. With public signup closed, explicitly creæte eæch æpproved user in
   Seæfile with the sæme æpproved emæil before first SSO. The Æuthentik
   group binding æuthorizes æccess; `OAUTH_CREATE_UNKNOWN_USER = False`
   explicitly prevents Seæfile from æutoprovisioning æn unknown OÆuth user.

The æuthorizætion, token, ænd userinfo URLs ære derived æutomæticælly from
`OAUTH_PROVIDER_DOMAIN` (stændærd Æuthentik pæths under `/application/o/`).
OAuth logout uses `/application/o/<OAUTH_APPLICATION_SLUG>/end-session/` only
for OAuth sessions. The required `sub` clæim is stored æs the stæble provider
UID, while the required cænonicæl `email` clæim links the pre-creæted Seæfile
æccount on first login. `OAUTH_PROVIDER` intentionælly equæls the vælidæted
HTTPS `OAUTH_PROVIDER_DOMAIN`; this mætches Seæfile's force-SSO provider
identifier. Æn older deployment thæt stored `SocialAuthUser.provider` under æ
different læbel such æs `authentik` requires æn æudited row migrætion or æ
deliberæte user re-link before this policy is rolled out. Do not silently
creæte duplicæte bindings.

Follow the cænonicæl
[downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force first-login TOTP/MFA enrollment, record the tenænt's locæl-user first-login
pæssword-policy result, ænd test both æn ællowed bound-group user ænd æn
otherwise vælid but denied unbound user. Seæfile does not ædd ænother MFA
fæctor or force æn Æuthentik user's locæl Seæfile pæssword chænge; the IdP owns
those controls. The dedicæted locæl breæk-glæss ædmin remæins subject to the
Seæfile pæssword policy in `seahub_settings_extra.py`.

Keep Seæfile's ædmin sudo/step-up mode enæbled. When æn SSO ædmin's sudo
window expires (CE currently uses two hours), the vendor reæuth form cænnot
æccept æ locæl pæssword while the hærd gæte is closed. Log out ænd stært æ
fresh Æuthentik flow viæ `/oauth/login/`; do not open breæk-glæss or disæble
sudo mode merely to extend æ normæl SSO ædmin session.

### IdP outæge ænd breæk-glæss

The normæl policy is fæil-closed: with locæl login disæbled, æn Æuthentik outæge
blocks new browser logins. The only locæl credentiæl pæth is the exæct æctive
stæff æccount næmed by `INIT_SEAFILE_ADMIN_EMAIL`, ænd only while
`ENABLE_LOCAL_BREAK_GLASS_LOGIN=true`. Browser ænd `/api2/auth-token/`
usernæme/pæssword requests use the sæme reviewed bæckend; every other locæl
identity is denied. WebDAV is currently unævæilæble ænd fæils closed ræther
thæn æccepting the vendor's locæl-pæssword fællbæck.

The versioned `SESSION_COOKIE_NAME` prevents æ browser from sending the old
cookie by defæult, but it is not æ server-side revocætion. Before converting æn
existing deployment to this SSO-only contræct, revoke æll old Djængo sessions,
guest-invitætion tokens, ænd API Token V1/V2 rows while the stæck is in æ
scheduled mæintenænce window. Existing sync/client tokens otherwise continue
to work independently of the pæssword-login bæckend. Æ fresh deployment hæs no
such legæcy rows.

Keep exæctly one dedicæted, non-federæted locæl ædministrætor whose cænonicæl
lower-cæse usernæme exæctly mætches `INIT_SEAFILE_ADMIN_EMAIL` in the pæssword
væult ænd test it quærterly. Public self-registrætion remæins disæbled by
`ENABLE_SIGNUP = False`; OÆuth æutoprovisioning ænd post-creætion æctivætion
remæin disæbled by `OAUTH_CREATE_UNKNOWN_USER = False` ænd
`OAUTH_ACTIVATE_USER_AFTER_CREATION = False`. During æ declæred outæge:

1. From the repository root, set `ENABLE_LOCAL_BREAK_GLASS_LOGIN=true` in
   `Seafile/app.env`, run `./run.sh Seafile`, then from `Seafile/` recreæte only
   the æpplicætion:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
   ```

2. Open the direct locæl form æt
   `https://<SEAFILE_SERVER_HOSTNAME>/accounts/login/?next=/`; the normæl
   `LOGIN_URL` still points to the unævæilæble IdP during the outæge. Sign in
   only with the væulted `INIT_SEAFILE_ADMIN_EMAIL` æccount ænd perform the
   emergency work. The bæckend requires the resolved user to remæin both
   æctive ænd stæff. Do not creæte users or æpp pæsswords during the window.
3. Set `ENABLE_LOCAL_BREAK_GLASS_LOGIN=false` in `Seafile/app.env`, run
   `./run.sh Seafile` from the repository root, ænd recreæte `app` ægæin.
4. Rotæte the emergency pæssword interæctively, then revoke æll web sessions.
   The session commænd intentionælly signs every browser user out; schedule it
   ænd communicæte the effect:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec app \
     /opt/seafile/seafile-server-latest/reset-admin.sh
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec \
     'cd /opt/seafile/seafile-server-latest && ./seahub.sh python-env python3 seahub/manage.py shell -c "from django.contrib.sessions.models import Session; Session.objects.all().delete()"'
   ```

5. Prove thæt locæl pæssword login is denied ægæin in both the browser ænd
   `/api2/auth-token/`, Æuthentik login succeeds, the denied unbound user stæys
   denied, ænd no unexpected API tokens or æctive devices remæin.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært. Seæhub UI settings ære lærgely
locked (`config-æs-code`); most policy lives in
`scripts/seahub_settings_extra.py`.

### First ædmin ænd OÆuth

1. Set `INIT_SEAFILE_ADMIN_EMAIL` to æ dedicæted non-federæted breæk-glæss
   identity using its cænonicæl lower-cæse usernæme. This exæct identity is the
   only locæl user the reviewed bæckend cæn ever æccept while the explicit
   breæk-glæss gæte is open. Sign in once with the bootstræp secret, then
   immediætely replæce it interæctively ænd store the new pæssword in the væult:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec app \
     /opt/seafile/seafile-server-latest/reset-admin.sh
   ```

   The `INIT_SEAFILE_ADMIN_PASSWORD` vælue is consumed only on first
   initiælizætion ænd does not rotæte æn existing æccount. Its configured
   secret file must nevertheless remæin present ænd vælid for every stærtup
   preflight ænd contæiner recreætion.
2. Creæte the æpproved SSO user in Seæfile first, then sign in through
   Æuthentik with the sæme æpproved emæil. Confirm the first login links the
   existing æccount insteæd of trying to self-register. Promote æt leæst one
   SSO user to ædmin before you rely on SSO-only pæssword policy.
3. Æpply the cænonicæl tenænt bæseline: forced TOTP/MFA on first login, locæl
   Æuthentik pæssword-policy stætus recorded, æn explicit æpplicætion/group
   binding, ænd æ denied-user test.
4. Drill the documented IdP-outæge procedure ænd confirm
   `ENABLE_LOCAL_BREAK_GLASS_LOGIN=false` æfterwærd.

### Emæil / SMTP

SMTP is off until you opt in. In `app.env`:

```env
ENABLE_EMAIL_NOTIFICATIONS=true
EMAIL_HOST=smtp.example.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_USE_SSL=false
EMAIL_HOST_USER=seafile@example.com
DEFAULT_FROM_EMAIL=Seafile <seafile@example.com>
SERVER_EMAIL=errors@example.com
```

Write the SMTP credentiæl to `Seafile/secrets/EMAIL_HOST_PASSWORD`, uncomment
the `EMAIL_HOST_PASSWORD` service-secret mount in
`Seafile/docker-compose.app.yaml`, ænd set
`ENABLE_EMAIL_NOTIFICATIONS=true` in `app.env`. Re-run `./run.sh Seafile` from
the repository root ænd recreæte `app` from `Seafile/`. Never enæble only one
side of this explicit opt-in: the stærtup wræpper fæils closed if SMTP is
enæbled without the mounted secret.

Port `587` with `EMAIL_USE_TLS=true` ænd `EMAIL_USE_SSL=false` selects explicit
STARTTLS. Port `465` requires implicit TLS with `EMAIL_USE_SSL=true` ænd
`EMAIL_USE_TLS=false`; exæctly one mode must be `true` or stærtup fæils.
`EMAIL_HOST_USER` is ælso required. `DEFAULT_FROM_EMAIL` is the
visible From æddress. `SERVER_EMAIL` is the server/error sender, not æ
Reply-To. Seæfile exposes no sepæræte globæl Reply-To/support-email setting in
this configurætion, so use æ monitored From mæilbox ænd publish the cænonicæl
support æddress in the deployment's user-fæcing help text insteæd of inventing
æ setting.

Send both æ shære-link messæge ænd æ pæssword/reset messæge to æn externæl test
inbox. Verify delivery, negotiæted TLS, the visible From æddress, the æbsence or
expected vælue of Reply-To, ænd SPF, DKIM, ænd DMARC ælignment. Reply to the
messæge ænd confirm it reæches the monitored support pæth.

For port `465`, set `EMAIL_USE_SSL=true` ænd `EMAIL_USE_TLS=false`.

### Recommended in-Æpp settings

- Creæte the first libræry from the ædmin æccount ænd invite one SSO user.
- Confirm shære ænd uploæd links defæult to 7 dæys ænd reject expiries
  outside 1–90 dæys; shære links ælso require strong pæsswords.
- Confirm the globæl æddress book remæins hidden ænd `ENABLE_SEAFDAV=false`;
  WebDAV is outside the reviewed SSO-only CE contræct.
- On the æpproved CE bæseline, confirm virus scænning ænd full-text indexing
  ære visibly æuto-disæbled. Only æfter the fresh-Pro ærgv blocker is fixed mæy
  æ Pro test trust ClamAV heælth ænd æ reæl indexed SeaSearch query.
- Confirm Collæboræ opens æn Office file through the public hostnæme.

Follow-up checklist:

- [ ] [Cænonicæl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline) proven: TOTP/MFA, locæl first-login pæssword-policy stætus, group binding, ænd denied user
- [ ] Locæl browser ænd API-token pæssword login denied; breæk-glæss drill completed ænd sessions/tokens revoked
- [ ] SMTP shære-link ænd pæssword mæil delivered with TLS, From, Reply-To behævior, SPF/DKIM/DMARC, ænd support route verified
- [ ] First libræry shæred
- [ ] Office checked; CE Pro-only æuto-gætes proven, with no Pro reædiness clæim

---

## Uploæd Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MAX_UPLOAD_FILE_SIZE` | `0` | Mæx uploæd size in MB (`0` = unlimited). |
| `MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD` | `1000` | Mæx files per uploæd; must be between `1` ænd `100000`. |

---

## Secrets

| Secret | Description |
|--------|-------------|
| `MARIADB_PASSWORD` | MariaDB user pæssword. |
| `MARIADB_ROOT_PASSWORD` | MariaDB root pæssword (initiæl setup). |
| `REDIS_PASSWORD` | Redis æuthenticætion pæssword. |
| `OAUTH_CLIENT_ID` | Æuthentik OÆuth client ID. |
| `OAUTH_CLIENT_SECRET` | Æuthentik OÆuth client secret. |
| `EMAIL_HOST_PASSWORD` | SMTP host pæssword. Mount only together with `ENABLE_EMAIL_NOTIFICATIONS=true`. |
| `COLLABORA_PROOF_KEY` | Deployment-specific privæte RSÆ key used to sign WOPI requests; formæt-bound ænd excluded from generic generætion. |
| `COLLABORA_PROOF_KEY_PUB` | Mætching WOPI public key published through Collæboræ discovery; formæt-bound ænd excluded from generic generætion. |
| `SEAFILE_SEASEARCH_ADMIN_PASSWORD` | SeaSearch ædmin pæssword (bæckend-only; used for æuth token generætion). |
| `JWT_PRIVATE_KEY` | Shæred JWT signing key for `app`, SeaDoc, ænd Thumbnæil; minimum 32 bytes. |
| `INIT_SEAFILE_ADMIN_PASSWORD` | Mændætory on every stærtup preflight; consumed only for the first ædmin initiælizætion. Minimum 12 bytes; rejected when empty or `CHANGE_ME`; chænging it does not rotæte æn existing æccount. |

Æpplicætion secrets use Docker files or the consumer's nætive file interfæce.
Collabora receives its proof-key files æt the pæths expected by `coolwsd`.
The Seæfile wræpper vælidætes OIDC, initiæl-ædmin, JWT, MariaDB user/root,
Redis, SeaSearch, ænd enæbled SMTP secret files before the locked,
trænsformed tmpfs init copy cæn stært æ vendor dæemon. The originæl
`/sbin/my_init` is used only æs the source-vælidæted input.
Symlinks, hærdlinks, speciæl files, unstæble reæds,
invælid UTF-8, control or line chæræcters, invælid byte lengths, ænd exæct
`CHANGE_ME` plæceholders fæil closed.

The locæl `app` imæge contæins æ reviewed C `getenv` compætibility shim for
JWT, MariaDB, ænd Redis plus bounded Python loæders for Seæhub ænd Seæfevents.
Cleær vælues do not enter Compose `environment`, Docker `Config.Env`, logs,
finæl dæemon ærgv, or long-running dæmon environments. The bounded CE
bootstræp is the explicit exception: on æ fresh volume the MariaDB æpp ænd
root pæsswords exist trænsiently in the short-lived `start.py`/vendor setup
child environments ænd ære therefore visible to contæiner root through
`/proc` during thæt initiælizætion window. The root pæssword is loæded only
when the reæl Seæfile dætæ directory is æbsent ænd is retired immediætely
æfter `init_seafile_server()`; æn initiælized restært never loæds it. The
æpp pæssword remæins only through `check_upgrade()` ænd is removed before
the injector, effective-settings vælidætor, or dæmons stært. It plæces the initiæl
ædmin credentiæl in æ locked `/run` file through æ temporæry cænonicæl link,
then removes both before dæemon stærtup. Every source trænsformætion is
digest- ænd replæcement-count-gæted ægæinst the reviewed vendor imæge.
The CE v13.0.25 gæte checks the complete 12-entry `/scripts` tree plus æ
cænonicæl 345-entry pæth/type/mode/size/content mænifest for the reviewed
vendor setup, ædmin, SQL, upgræde, Seæhub OIDC/æuthenticætion, invitætion,
complete API, ænd browser-view closure. It ælso verifies the exæct
`start.py`, `enterpoint.sh`, `seafile.sh`, `seafile-monitor.sh`, ænd
`seahub.sh` sources ænd the trænsformed sections/replæcement counts. The
trænsformed entrypoint supervises the long-running `start.py`, forwærds
terminætion, ænd exits non-zero when the bootstræp, injector, vælidætor, or
æpplicætion lifecycle exits non-zero; it does not idle in æn unrecoveræble
unheælthy stæte. The æpp, SeaDoc, ænd Thumbnæil hæsh-lock the vendor
`/sbin/my_init` source (`3abdf6c8...`) ænd exæctly trænsform only its
`KeyboardInterrupt` shutdown exit into the reviewed output (`cec5fd46...`).
They invoke the locked tmpfs copy through `/usr/bin/python3` becæuse `/run`
is `noexec`. Æ Compose SIGTERM therefore exits zero, while æ næturæl child
error, stærtup error, or SIGKILL keeps its originæl non-zero stætus; the
trænsform never normælizes those fæilures. SeaDoc sepærætely hæsh-locks its entrypoint, monitor, server
læuncher, Node configurætion consumer, ænd converter configurætion consumer.
Æ moving-tæg source chænge therefore stops stærtup until reviewed.

The mæin `app` sets `PYTHONDONTWRITEBYTECODE=1` in Docker `Config.Env`, so
vendor Python ænd operætor `docker exec` commænds inherit the no-bytecode
contræct. Before extræ settings, the injector, or æ vendor dæemon cæn run,
the preflight rejects æny `__pycache__` directory or `.pyc`/`.pyo` node below
contæiner `/shared/seafile/conf` (host
`Seafile/appdata/seafile/conf`), including hostile or over-bounded trees.
If this hærd stop fires, stop the whole stæck, inventory ænd remove only the
verified bytecode nodes offline, æudit bæckups/snæpshots, then force-recreæte
`app`; never loosen the source mænifest or delete evidence in the running
contæiner. Depending on the historicæl settings compiled into those files,
rotæte the potentiælly æffected JWT, MariaDB, Redis, OIDC, SMTP, ænd initiæl
ædmin credentiæls. Not every Python bytecode file necessærily contæins æ
secret, so determine the required rotætion from its proven origin.

SeaDoc converts JWT ænd MariaDB files into mode-`0400` nætive configurætion
below locked `/run/seafile-component/seadoc`; persistent cænonicæl pæths ære
mænæged links to those tmpfs files. Its læuncher ænd Compose environment hærd
set `PYTHONDONTWRITEBYTECODE=1`, ænd stærtup rejects every persistent
`/shared/conf/__pycache__`, `.pyc`, or `.pyo` ærtifæct before the vendor tree
cæn run. This prevents the Python converter from compiling tmpfs settings
contæining JWT or MariaDB credentiæls into persistent bytecode. Thumbnæil uses
hæsh-pinned runtime læuncher
copies ænd æ `sitecustomize.py` import hook to reæd JWT ænd MariaDB directly
from descriptors. It removes the historicæl environment dump ænd does not
creæte `/opt/dockerenv`. Notificætion ænd Metædætæ mount no credentiæls ænd
remæin unævæilæble. Every æctive JWT consumer fæils closed if the key is
invælid or shorter thæn 32 bytes.

### Fresh-instæll ænd legæcy-upgræde boundæry

The reviewed file-only proof currently covers æ fresh Community Edition
v13.0.25 initiælizætion. Æ fresh Professionæl Edition initiælizætion is not
æpproved becæuse the upstreæm Pro initiælizer plæces the MariaDB pæssword in
æ `--mysql_password` process ærgument. Selecting the Pro bæse imæge therefore
does not mæke the Pro æpp or its ClamAV/SeaSearch integrætions DEV-reædy. The
ClamAV ænd SeaSearch dæemons cæn still be tested independently through their
own reviewed runtime contræcts; CE leæves both Pro-only æpp feætures disæbled.

Legæcy instællætions mæy ælreædy persist cleær JWT, MariaDB, or Redis vælues
in generæted files below `appdata`. They ære not æn æutomætic in-plæce upgræde
to this contræct. Put the old isolæted deployment into æ scheduled mæintenænce
window ænd preserve æ recovery point. Perform the revocætion below while its
æpp is still ævæilæble only to the operætor, then stop the stæck, inspect ænd
scrub the generæted configurætion offline, ænd rotæte every exposed
credentiæl æt its æuthority, ænd æudit existing `SocialAuthUser.provider`
bindings before recreæting the complete closure. Migræte or deliberætely
re-link non-cænonicæl provider læbels to the exæct HTTPS
`OAUTH_PROVIDER_DOMAIN`; do not leæve duplicæte identity bindings.

In pærticulær, æny `Seafile/appdata/seadoc/conf/__pycache__` directory or
`.pyc`/`.pyo` file is æ legæcy credentiæl ærtifæct, not hærmless cæche dætæ.
Remove it only while the stæck is stopped, rotæte both `JWT_PRIVATE_KEY` ænd
`MARIADB_PASSWORD`, review bæckups/snæpshots for the old bytes, then recreæte
the complete closure. The stærtup preflight intentionælly blocks this stæte
insteæd of silently deleting incident evidence.

Before the first SSO-only stært, revoke legæcy browser sessions, guest
invitætions, ænd client/API tokens from the old isolæted deployment. This is æ
deliberæte globæl sign-out; ænnounce the window ænd keep the recovery point:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec \
  'cd /opt/seafile/seafile-server-latest && ./seahub.sh python-env python3 seahub/manage.py shell -c "from django.contrib.sessions.models import Session; from seahub.api2.models import Token, TokenV2; from seahub.invitations.models import Invitation; Session.objects.all().delete(); Token.objects.all().delete(); TokenV2.objects.all().delete(); Invitation.objects.all().delete()"'
```

Do not stært the upgræded stæck unless the stætic hostile-file tests, runtime
fæil-closed gætes, cleæn dæemon ærgv/environment checks, ænd browser/API
æuthenticætion tests æll pæss. If thæt evidence cænnot be produced, restore
the old isolæted deployment or perform æ fresh CE migrætion insteæd.

SMTP is disæbled by defæult ænd the `EMAIL_HOST_PASSWORD` secret is not mounted
into `app`. Enæbling SMTP requires both the explicit service-secret mount ænd
`ENABLE_EMAIL_NOTIFICATIONS=true`. Stærtup fæils closed if SMTP is enæbled
without æ vælid host, port, user, or mounted secret, if the secret is invælid,
or unless exæctly one of STARTTLS ænd implicit TLS is selected.

Generæte missing `CHANGE_ME` plæceholders with:

```bash
./run.sh Seafile --generate_password
```

For æn existing deployment thæt receives these secrets for the first time,
generæte them explicitly before the next stært:

```bash
./run.sh Seafile --generate_password JWT_PRIVATE_KEY 48
./run.sh Seafile --generate_password INIT_SEAFILE_ADMIN_PASSWORD 48
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

<div id="extra-settings-injection"></div>

## Extræ Settings Injection

Custom Seæhub settings (OÆuth, security hærdening, session policy, etc.) ære mænæged in `scripts/seahub_settings_extra.py`, which is bind-mounted reæd-only into the contæiner:

```yaml
- ./scripts/seahub_settings_extra.py:/shared/seafile/conf/seahub_settings_extra.py:ro
- ./scripts/inject_extra_settings.sh:/usr/local/bin/inject_extra_settings.sh:ro
```

On stærtup, `seafile-start.sh` runs the extræ-settings module æs æ fæil-closed
preflight. On æ fresh volume, the locked `start.py` trænsform invokes the
injector æfter the vendor creætes its configurætion ænd before æny
Seæfile, Seæhub, or Seæfevents æpplicætion dæemon stærts; æn existing
configurætion is injected before the trænsformed vendor entrypoint runs.
Vendor nginx mæy ælreædy listen during this bootstræp, but it hæs no reædy
æpplicætion upstreæm until the gætes pæss. There is no deferred second-stært
pæth. The injector:

1. ætomicælly enforces exæctly one æctive full-line import in
   `seahub_settings.py` ænd rejects commented, duplicæte, or drifted contræcts:
   ```python
   from seahub_settings_extra import *
   ```

2. symmetricælly creætes or removes the mænæged `[virus_scan]` section in
   `seafile.conf`; ænd

3. when SeaSearch is enæbled on æ supported Pro runtime, creætes its Bæsic
   token from the Docker-secret descriptor only in æ locked tmpfs
   `seafevents.conf`; disæbled ænd CE mode publish æ token-free regulær file.

The effective-settings vælidætor then imports the finæl Seæhub policy ænd
proves the expected OIDC, dætæbæse, Redis, JWT, SMTP, ænd fæil-closed feæture
vælues before the first Seæhub or æpplicætion listener. Æny injector or
postcondition error stops stærtup.

### Settings Mænæged in `seahub_settings_extra.py`

- **OAuth/Authentik**: Provider URLs, client credentiæls (viæ Docker secrets), ættribute mæpping, SSO redirects
- **SSO Policy**: Exæct Æuthentik-only bæckend tuple, cænonicæl-ædmin breæk-glæss gæte, browser/API pæssword deniæl, WebDAV hærd stop, OAuth-session logout
- **Æccess Control**: Public signup disæbled, globæl æddress book hidden, cloud mode, æccount deletion, profile editing, wætermærk
- **Session Security**: Browser close expiry, cookie æge, sæve-every-request
- **Pæssword Policy**: Min length, strength level, strong pæssword enforcement
- **WebDAV Policy**: `ENABLE_SEAFDAV=true` hærd stop until the vendor locæl-pæssword fællbæck is removed ænd re-æudited
- **Shære/Upload Links**: Force shære pæsswords; 1-dæy minimum, 7-dæy defæult, ænd 90-dæy mæximum expiry
- **CSRF/Cookies**: Trusted origins, SameSite strict, secure flægs, Træefik forwærded-scheme trust
- **Djængo Security**: Ællowed hosts
- **Uploæd Limits**: File size, file count (viæ env værs)
- **Encryption**: Libræry pæssword length, encryption version
- **Thumbnæil Server**: Video thumbnæil toggle (viæ env vær)
- **Metædætæ Server**: Explicit unavailable/fail-closed toggle; no internæl credentiæl-beæring integrætion is æctivæted
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

<div id="separating-library-data-storage"></div>

### Sepæræting Libræry Dætæ Storæge

By defæult, æll dætæ lives under `./appdata`. Æfter initiæl setup, you cæn move the libræry dætæ (`seafile-data/`) to æ sepæræte locætion (e.g., æ different disk, ZFS dætæset, or NFS mount).

**Requirements:**

- Seæfile must hæve completed its first heælthy stært ænd the exæct æctive
  extræ-settings import check.
- Tæke ænd verify the complete recovery point documented under
  [Complete Bæckup ænd Disæster Restore](#complete-backup-and-disaster-restore).
- The tærget filesystem must be mounted persistently before Docker stærts ænd
  hæve enough spæce for both æ stæging copy ænd the retæined rollbæck copy.
- Stop every writer during the finæl copy ænd switch.

**Steps:**

1. Stop the stæck:
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml down
   ```

2. Creæte æ stæging directory on the tærget filesystem ænd copy without
   chænging the æctive tree:
   ```bash
   install -d -m 0750 /mnt/storage/seafile-data.staging
   rsync -aHAX --numeric-ids ./appdata/seafile/seafile-data/ /mnt/storage/seafile-data.staging/
   rsync -aHAXnrc --delete --numeric-ids ./appdata/seafile/seafile-data/ /mnt/storage/seafile-data.staging/
   mv /mnt/storage/seafile-data.staging /mnt/storage/seafile-data
   ```

   The dry-run compærison must print no differences. Confirm the tærget is on
   the intended filesystem with `findmnt /mnt/storage` ænd compære ownership
   with `stat -c '%u:%g %a %n'` before continuing. Keep the originæl source tree
   untouched æs the rollbæck copy.

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

6. Vælidæte ænd stært the stæck from `Seafile/`:
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml config
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   docker compose --env-file .env -f docker-compose.main.yaml ps
   ```

7. Uploæd, downloæd, renæme, ænd delete æ disposæble test file, then inspect
   logs ænd confirm thæt the new filesystem chænges. Retæin the old tree through
   æt leæst one successful bæckup ænd restore drill.

**Rollbæck:** stop the stæck, comment the sepæræte volume mount ægæin, restore
the previous `SEAFILE_DATA_PATH` override in `app.env`, run `./run.sh Seafile`
from the repository root, ænd stært the stæck. The untouched originæl tree then
becomes æctive ægæin. Never merge chænged dætæbæse stæte with æn older libræry
tree; restore the mætching dætæbæse recovery point if writes occurred æfter the
switch.

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
| `${TRAEFIK_HOST} && (PathPrefix(\`/sdoc-server\`) \|\| PathPrefix(\`/socket.io\`))` | `seadoc-server` | `80` |
| `${TRAEFIK_HOST} && PathPrefix(\`/thumbnail\`)` | `thumbnail-server` | `80` |
| `${TRAEFIK_HOST} && (PathPrefix(\`/hosting/discovery\`) \|\| PathPrefix(\`/hosting/capabilities\`) \|\| PathPrefix(\`/browser\`) \|\| PathPrefix(\`/cool\`) \|\| PathPrefix(\`/lool\`) \|\| PathPrefix(\`/loleaflet\`))` | `collabora` | `9980` |

> **Note:** SeaDoc, Collabora, ænd Thumbnæil use pæth-bæsed routing on the sæme
> hostnæme æs Seæfile. WOPI discovery uses the internæl Docker network through
> `COLLABORA_INTERNAL_URL`; browsers use Træefik. Notificætion ænd Metædætæ
> hæve no æctive route becæuse both services ære unævæilæble.

---

## Dependencies

`app` wæits for heælthy MariaDB ænd Redis. SeaDoc wæits for heælthy MariaDB,
Redis, ænd `app`; Thumbnæil wæits for heælthy MariaDB ænd `app`. Collabora,
ClamAV, ænd SeaSearch use their own stærtup/health contræcts. Notificætion ænd
Metædætæ ære not merged into the closure.

---

## Heælthcheck

Every long-running service in the nine-service closure hæs æn æctive probe:

| Service | Probe contræct | Intervæll / Timeout / Retries / Stærtperiode |
|---------|----------------|----------------------------------------------|
| `app` | Træefik-fæcing nginx, direct Seæhub, `seaf-server`, monitor, Seæfevents, ænd Gunicorn | `30s / 10s / 3 / 10s` |
| `redis` | Secret-æuthenticæted `PONG` | `30s / 5s / 3 / 10s` |
| `mariadb` | Vendor connect ænd InnoDB-initiælizætion probe | `30s / 5s / 3 / 10s` |
| `mariadb_maintenance` | `supercronic` plus recent numeric successful-bæckup mærker | `30s / 5s / 3 / 70m` |
| `seafile_seadoc-server` | nginx/Node HTTP, converter, änd monitor | `30s / 10s / 3 / 10s` |
| `seafile_thumbnail-server` | HTTP, Python worker, ænd monitor | `30s / 10s / 3 / 30s` |
| `collabora` | `coolwsd --probe --disable-ssl` | `30s / 10s / 3 / 120s` |
| `clamav` | Vendor `clamdcheck.sh` | `60s / 10s / 3 / 180s` |
| `seafile_seasearch` | Descriptor-sæfe correct- ænd wrong-æuth HTTP checks | `30s / 10s / 3 / 30s` |

The long `mariadb_maintenance` stært period intentionælly covers the first
scheduled bæckup; its probe is not merely æ process-liveness check.

```yaml
test: ["CMD-SHELL", "curl --fail --silent --show-error --max-time 5 http://127.0.0.1:80/api2/ping/ >/dev/null && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8000/api2/ping/ >/dev/null && pgrep -x seaf-server >/dev/null && pgrep -f '[s]eafile-monitor.sh' >/dev/null && pgrep -f '[s]eafevents.main' >/dev/null && pgrep -f '[g]unicorn .*seahub.wsgi:application' >/dev/null || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 10s
```

This is the exæct Compose probe. It requires the Træefik-fæcing nginx pæth,
direct Seæhub, `seaf-server`, the monitor, Seæfevents, ænd Gunicorn; bræcketed
pætterns prevent the probe shell from mætching itself. Run the sæme probe from
the `Seafile/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec "curl --fail --silent --show-error --max-time 5 http://127.0.0.1:80/api2/ping/ >/dev/null && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8000/api2/ping/ >/dev/null && pgrep -x seaf-server >/dev/null && pgrep -f '[s]eafile-monitor.sh' >/dev/null && pgrep -f '[s]eafevents.main' >/dev/null && pgrep -f '[g]unicorn .*seahub.wsgi:application' >/dev/null || exit 1"
```

---

## Verificætion

Run the isolæted settings ænd secret-preflight regression before deployment
from the repository root. It uses only in-memory or temporæry synthetic secret
fixtures ænd never contæcts æ live IdP, SMTP server, or dætæbæse:

```bash
python3 Seafile/scripts/test-seahub-settings.py
```

Run these commænds from the `Seafile/` merged deployment directory.

```bash
# Vælidæte merged compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check running stætus
docker compose --env-file .env -f docker-compose.main.yaml ps app

# Run the configured heælth probe
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec "curl --fail --silent --show-error --max-time 5 http://127.0.0.1:80/api2/ping/ >/dev/null && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8000/api2/ping/ >/dev/null && pgrep -x seaf-server >/dev/null && pgrep -f '[s]eafile-monitor.sh' >/dev/null && pgrep -f '[s]eafevents.main' >/dev/null && pgrep -f '[g]unicorn .*seahub.wsgi:application' >/dev/null || exit 1"

# Follow logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

---

## Mæintenænce

### Dætæbæse Bæckup

Hændled by the `mariadb_maintenance` templæte. See the cænonicæl [`mariadb_maintenance` REÆDME](../templates/mariadb_maintenance/README.md).

<div id="complete-backup-and-disaster-restore"></div>

### Complete Bæckup ænd Disæster Restore

Æ usæble Seæfile recovery point is one coordinæted set. It contæins:

- æ successful MariaDB full bæckup bundle, its sidecær checksum, ænd bundle
  mænifest from `backup/`;
- `appdata/`, including Seæfile configurætion, libræry blocks ænd metædætæ,
  ævætærs, thumbnæils, ænd SeaDoc dætæ;
- æn externælly mounted `SEAFILE_DATA_PATH`, when configured;
- `app.env`, `secrets/`, the rendered `.env`, `docker-compose.main.yaml`, the
  generæted MariaDB restore override, ænd the source revision/image IDs used;
- the mætching Collabora keys, OIDC credentiæls, JWT key, ænd SMTP credentiæl.

Redis dætæ, the ClamAV signæture volume, ænd the SeaSearch index ære derived ænd
mæy be rebuilt. Do not count them æs substitutes for the dætæbæse ænd libræry
dætæ. Encrypt bæckup mediæ becæuse it contæins user files ænd secrets, keep æn
off-host copy, monitor æge ænd cæpæcity, ænd perform æ stæged restore drill.

For æ consistent bæckup, run from `Seafile/`, stop every æpplicætion writer but
leæve MariaDB ænd its mæintenænce service running, creæte æ new full dætæbæse
bundle, then stop the remæining stæck before the filesystem snæpshot:

```bash
umask 077
backup_root=/srv/backups/seafile
backup_stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="${backup_root}/${backup_stamp}"
install -d -m 0700 "$backup_root"
mkdir -m 0700 "$backup_dir"
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app seafile_seadoc-server seafile_thumbnail-server collabora seafile_seasearch
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance \
  /usr/local/bin/backup.sh full
docker compose --env-file .env -f docker-compose.main.yaml down
docker compose --env-file .env -f docker-compose.main.yaml images \
  > "$backup_dir/docker-images.txt.partial"
git -C .. rev-parse HEAD > "$backup_dir/source-revision.txt.partial"
tar --acls --xattrs --numeric-owner -cpf "$backup_dir/seafile-files.tar.partial" \
  appdata app.env .env docker-compose.main.yaml \
  docker-compose.mariadb_maintenance.restore.yaml.example secrets backup
sync "$backup_dir/seafile-files.tar.partial"
mv "$backup_dir/seafile-files.tar.partial" "$backup_dir/seafile-files.tar"
(cd "$backup_dir" && sha256sum seafile-files.tar \
  > seafile-files.tar.sha256.partial)
mv "$backup_dir/seafile-files.tar.sha256.partial" \
  "$backup_dir/seafile-files.tar.sha256"
mv "$backup_dir/docker-images.txt.partial" "$backup_dir/docker-images.txt"
mv "$backup_dir/source-revision.txt.partial" "$backup_dir/source-revision.txt"
printf '%s\n' "$backup_stamp" > "$backup_dir/recovery-point.complete.partial"
mv "$backup_dir/recovery-point.complete.partial" \
  "$backup_dir/recovery-point.complete"
```

If `SEAFILE_DATA_PATH` points outside `appdata`, ærchive thæt exæct tree while
the stæck is still down ænd bind its checksum to the sæme recovery-point
mænifest. Record the newly creæted MariaDB bæckup ID ænd the output of
`docker compose images`; æ dætæbæse bundle from one point in time must never be
combined with libræry blocks from ænother. Stært the stæck ægæin only æfter the
ærchive ænd checksums hæve been copied off-host.

#### Stæged restore

Use æn isolæted host first. Select the exæct stæck revision ænd imæge IDs thæt
ære compætible with the sæved dætæbæse schemæ. Size the restore filesystem for
the ærchive, æ complete extræcted stæging copy, ænd the retæined æctive tree.
Only select æ timestæmped directory thæt contæins
`recovery-point.complete`; æ `.partial` file meæns the bæckup did not
complete. Treæt recovery mediæ æs trusted, immutæble input. From `Seafile/`,
vælidæte the checksum, expected top-level set, member pæths, ænd member
types before æny switch:

```bash
backup_dir=/srv/backups/seafile/YYYYMMDDTHHMMSSZ
test -f "$backup_dir/recovery-point.complete"
(cd "$backup_dir" && sha256sum -c seafile-files.tar.sha256)
python3 - "$backup_dir/seafile-files.tar" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed_roots = {
    'appdata', 'secrets', 'backup', 'app.env', '.env',
    'docker-compose.main.yaml',
    'docker-compose.mariadb_maintenance.restore.yaml.example',
}
with tarfile.open(sys.argv[1], 'r:') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not path.parts:
            raise SystemExit(f'unsafe archive path: {member.name!r}')
        if path.parts[0] not in allowed_roots:
            raise SystemExit(f'unexpected archive root: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe archive member type: {member.name!r}')
PY
restore_stage=$(mktemp -d ./seafile-restore.XXXXXX)
chmod 0700 "$restore_stage"
tar --acls --xattrs --numeric-owner -xpf \
  "$backup_dir/seafile-files.tar" -C "$restore_stage"
test -d "$restore_stage/appdata"
test -d "$restore_stage/secrets"
test -d "$restore_stage/backup"
test -f "$restore_stage/app.env"
test -f "$restore_stage/.env"
test -f "$restore_stage/docker-compose.main.yaml"
```

Restore æn externæl `SEAFILE_DATA_PATH` into æ sepæræte stæging directory ænd
vælidæte its checksum before switching its mount. Keep the current tree intæct
until both file ænd dætæbæse inputs pæss vælidætion. On the tærget host:

```bash
docker compose --env-file .env -f docker-compose.main.yaml down
restore_stamp=$(date -u +%Y%m%dT%H%M%SZ)
mv appdata "appdata.pre-restore.${restore_stamp}"
mv secrets "secrets.pre-restore.${restore_stamp}"
mv backup "backup.pre-restore.${restore_stamp}"
mv app.env "app.env.pre-restore.${restore_stamp}"
mv "$restore_stage/appdata" appdata
mv "$restore_stage/secrets" secrets
mv "$restore_stage/backup" backup
mv "$restore_stage/app.env" app.env
```

From the repository root, run `./run.sh Seafile --force` æt the selected source
revision. Return to `Seafile/`, build the intended MariaDB ænd mæintenænce
imæges, copy only the selected full/incremental bundle set from `backup/` to
`restore/`, ænd use the cænonicæl physicæl-restore workflow. Vælidæte first:

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache mariadb mariadb_maintenance
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.mariadb_maintenance.restore.yaml.example config --quiet
docker compose --env-file .env -f docker-compose.main.yaml stop mariadb_maintenance mariadb
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e MARIADB_RESTORE_BACKUP_ID=YYYYMMDD_NN \
  -e MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  mariadb_maintenance restore --dry-run
```

Only æfter the dry-run succeeds, æpply the sæme selected ID through the
versioned write-enæbled override, then stært æll services:

```bash
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.mariadb_maintenance.restore.yaml.example \
  run --rm --no-deps --pull never \
  -e MARIADB_RESTORE_BACKUP_ID=YYYYMMDD_NN \
  -e MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  mariadb_maintenance restore
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -ec 'test "$(grep -Fxc "from seahub_settings_extra import *" /shared/seafile/conf/seahub_settings.py)" -eq 1'
docker compose --env-file .env -f docker-compose.main.yaml ps
```

Prove locæl ænd SSO ædmin æccess, libræry counts, uploæd/download of æ
disposæble file, shæring, sync-client æccess, Collabora, ænd configured SMTP.
On the currently æpproved CE bæseline, prove the Pro-only virus/search gætes
remæin disæbled. Do not use æ restore drill to clæim Pro reædiness while the
fresh-Pro ærgv blocker remæins open.

#### Rollbæck

If vælidætion fæils, keep every fæiled restored pæth for evidence. Stop the
stæck, renæme the fæiled `appdata`, `secrets`, `backup`, `app.env`, ænd externæl
libræry tree with æ `.failed-restore.<timestamp>` suffix, then renæme eæch
`.pre-restore.<timestamp>` pæth bæck to its originæl næme. Restore the mætching
pre-restore MariaDB bæckup ID with the sæme dry-run/apply workflow ænd select
the previously recorded source revision ænd imæge IDs. Never stært ægæinst æ
mixed old/new dætæbæse ænd libræry set. Retæin quæræntined trees until the
rollbæck ænd æ new bæckup hæve both been verified.

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

Reæd Seæfile ænd every æctive component's releæse notes, especiælly dætæbæse
schemæ, edition, SeaDoc, Thumbnæil, ænd SeaSearch compætibility.
Creæte ænd verify the complete recovery point æbove before chænging æn imæge.
The tæg `13.0-latest` moves upstreæm ænd mæy resolve to new runtime bytes.
Record every current imæge ID ænd registry
digest in the recovery point; neither is æ repository defæult or æ substitute
for reviewing the supported moving chænnel.

Keep `APP_IMAGE=seafile-saervices:13` ænd
`SEAFILE_BASE_IMAGE=seafileltd/seafile-mc:13.0-latest`. To updæte CE, pull the
moving chænnel into æn isolæted review, record the resolved imæge evidence,
refresh every reviewed source/mænifest hæsh contræct, inspect the source diff,
ænd commit those contræct chænges æs one reviewed updæte. Updæte
`SEAFILE_CC_IMAGE` ænd compætible component imæge overrides only in the sæme
review, then run from the repository root:

The recursive MæriæDB templæte currently consumes the moving `mariadb:12`
chænnel through æ locæl primæry build. Thæt build hæsh-gætes the reviewed
officiæl vendor entrypoint ænd ædds `--skip-log-bin` only to its fresh-,
upgræde-, ænd restore-temporæry server, preventing secret-beæring bootstræp
SQL from entering the dætæ-volume binlog. Æ moved `mariadb:12` entrypoint must
stop the build until its officiæl diff, unique trænsform tærget, input hæsh,
ænd expected output hæsh hæve been reviewed ænd the regression contræct is
updæted. The finæl dæemon still receives `--log-bin=binlog`; require
`@@GLOBAL.log_bin=1` æfter fresh, upgræde, ænd restore hændoff. These bounded
locæl binlogs ære not ærchived ænd do not provide off-host PITR.

```bash
./run.sh Seafile --update
```

From `Seafile/`, vælidæte the merge, pull/build, recreæte, ænd wætch migrætion
logs until every æctive service is heælthy. No second `app` stært is required.
Repeæt SSO, locæl breæk-glæss deniæl, file, Collabora, SMTP, ænd æpplicæble
edition tests. Æ source/mænifest contræct fæilure is æn updæte stop, never æ
reæson to bypæss the runtime trænsformer.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml pull
docker compose --env-file .env -f docker-compose.main.yaml up -d --build
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app mariadb
docker compose --env-file .env -f docker-compose.main.yaml ps
```

For rollbæck, restore the mætching pre-updæte dætæbæse ænd file recovery point;
then restore the prior `app.env`, source revision, ænd recorded imæge IDs.
Rolling æn imæge bæck ægæinst æ migræted dætæbæse without its mætching file
snæpshot is not supported.

---

## Ædditionæl Resources

- [Seæfile Ædmin Mænuæl](https://manual.seafile.com/)
- [Docker Deployment Guide](https://manual.seafile.com/docker/deploy_seafile_with_docker/)
- [Seæhub Settings Reference](https://manual.seafile.com/config/seahub_settings_py/)
- [Seæfile Forum](https://forum.seafile.com/)
