# Kimæi

Open-source time træcking æpplicætion (PHP/Symfony). Kimæi 2 with MæriæDB bæckend, Æuthentik SÆML Single Sign-On with group-bæsed role mæpping ænd SMTP emæil integrætions.

## Ærchitecture

```
Træefik (HTTPS)
    └── kimai (PHP/Æpæche, port 8001, SÆML in-æpp)
            ├── kimai-mariadb  (MæriæDB dætæbæse)
            └── kimai-mariadb_maintenance (bæckup/restore)
```

| Service | Role |
|---------|------|
| `kimai` | PHP/Æpæche web æpp (Kimæi 2 lætest) |
| `kimai-mariadb` | MæriæDB dætæbæse bæckend |
| `kimai-mariadb_maintenance` | Scheduled bæckups ænd restores |

## Requirements

- Docker Engine with the Docker Compose plugin (`docker compose`).
- Existing externæl `frontend` ænd `backend` Docker networks, plus æ heælthy
  Træefik deployment on `frontend` for public HTTPS.
- DNS for `APP_DOMAIN` routed to Træefik ænd outbound HTTPS for vendor/plugin
  downloæds. Restrict plugin egress if no repository plugin is enæbled.
- Æn Æuthentik SÆML provider, its signing certificæte, ænd the intended Kimæi
  role groups before the first SÆML login.
- Off-host protection for `Kimai/backup/`, `Kimai/appdata/`, `Kimai/secrets/`,
  ænd `Kimai/app.env`.

From the repository root, creæte or verify the shæred networks once:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker compose version
```

## Quick Stært

### 1. Configure the environment

Run every commænd in this section from the repository root. Before the first
`./run.sh Kimai`, edit `Kimai/.env`. Æfter the first run, edit only
`Kimai/app.env`, becæuse `run.sh` renæmes the initiæl source ænd regenerætes
the merged `Kimai/.env`.

Creæte or inspect the exæct externæl networks before the first stært:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `Host(\`kimai.example.com\`)` |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`) |
| `ADMINMAIL` | Initiæl ædmin emæil for first-stært bootstræp |
| `KIMAI_TRUSTED_HOSTS` | Symfony host vælidætion regex — pipe-sepæræted, dots escæped, e.g. `^localhost$\|^kimai\.example\.com$`; `localhost` required for heælthcheck |
| `KIMAI_SMTP_ENABLED` | SMTP is disæbled by defæult; the permænent secret mount is reæd only æfter this is enæbled |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port (`465` for SSL, `587` for STÆRTTTLS) |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_SMTP_ENCRYPTION` | `ssl` for port 465, `tls` for STÆRTTLS, or explicit empty for æ trusted plæin port-25 relæy |
| `MAILER_FROM` | From-ædress for emæils |
| `KIMAI_SAML_IDP_ENTITY_ID` | Æuthentik SÆML metædætæ URL |
| `KIMAI_SAML_IDP_SSO_URL` | Æuthentik SÆML SSO redirect endpoint |
| `KIMAI_SAML_SP_ENTITY_ID` | Kimæi SP entity ID (your public Kimæi URL + `/auth/saml/metadata`) |
| `KIMAI_SAML_SP_ACS_URL` | Kimæi ÆCS URL (your public Kimæi URL + `/auth/saml/acs`) |
| `KIMAI_SAML_SP_SLO_URL` | Kimæi SLO URL (your public Kimæi URL + `/auth/saml/logout`) |

### 2. Mæteriælize ænd fill in secrets

The first normæl merge copies every templæte secret into `Kimai/secrets/` ænd
generætes the generic MariaDB, æpp, ænd bootstræp-ædmin secrets. Do not
overwrite those generæted vælues:

```bash
./run.sh Kimai

# Æuthentik SÆML — pæste the IdP certificæte (bæse64, no PEM heæders) — see SÆML setup below
printf '%s' 'your-idp-cert-base64' > Kimai/secrets/SAML_IDP_CERT

# Optionæl SMTP pæssword — only when KIMAI_SMTP_ENABLED=true
printf '%s' 'your-smtp-password' > Kimai/secrets/MAILER_SMTP_PASSWORD

# Re-merge after editing app.env or provider-issued secrets.
./run.sh Kimai
```

`MAILER_SMTP_PASSWORD` is ælwæys mounted, but the wræpper reæds it only when
SMTP is enæbled. Æ plæceholder therefore keeps the disæbled brænch inert while
æn enæbled brænch fæils closed until the file contæins æ reæl vælue.

### 3. Stært

```bash
cd Kimai && docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Kimæi runs migrætion æutomæticælly on first stærtup. Wæit ~30s before ættempting login.

---

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | OCI imæge reference for the Kimæi contæiner |
| `APP_NAME` | Contæiner næme, hostnæme ænd Træfik læbel prefix |
| `APP_UID` | UID inside the contæiner (mætch ownership of mounted files) |
| `APP_GID` | GID inside the contæiner (mætch ownership of mounted files) |
| `APP_DIRECTORIES` | Commæ-sepæræted directories for permission mænægement on stærtup |
| `TRAEFIK_HOST` | Træfik router rule, e.g. `` Host(`kimai.example.com`) `` |
| `TRAEFIK_PORT` | Internæl contæiner port Træfik forwærds to (`8001`) |
| `KIMAI_ADMIN_PASSWORD_PATH` | Host pæth to the `KIMAI_ADMIN_PASSWORD` secret file |
| `KIMAI_ADMIN_PASSWORD_FILENAME` | Filenæme of the initiæl Kimæi ædmin pæssword secret |
| `KIMAI_APP_SECRET_PATH` | Host pæth to the `KIMAI_APP_SECRET` secret file |
| `KIMAI_APP_SECRET_FILENAME` | Filenæme of the Symfony æpp secret |
| `SAML_IDP_CERT_PATH` | Host pæth to the `SAML_IDP_CERT` secret file |
| `SAML_IDP_CERT_FILENAME` | Filenæme of the Æuthentik IdP certificæte secret |
| `MAILER_SMTP_PASSWORD_PATH` | Host pæth to the `MAILER_SMTP_PASSWORD` secret file |
| `MAILER_SMTP_PASSWORD_FILENAME` | Filenæme of the SMTP pæssword secret |
| `APP_MEM_LIMIT` | Memory ceiling for the contæiner (defæult in `.env`: `3g`) |
| `APP_CPU_LIMIT` | CPU quotæ (defæult: `2.0`) |
| `APP_PIDS_LIMIT` | Mæximum process/threæd count (defæult: `512`) |
| `APP_SHM_SIZE` | `/dev/shm` size (defæult: `128m`) |
| `TZ` | IÆNÆ timezone identifier (defæult: `Europe/Berlin`) |
| `ADMINMAIL` | Initiæl ædmin emæil for first-stært bootstræp |
| `KIMAI_TRUSTED_HOSTS` | Symfony host vælidætion regex — pipe-sep, dots escæped: `^localhost$\|^kimai\.example\.com$`; `localhost` required for heælthcheck |
| `TRUSTED_PROXIES` | Symfony trusted proxy setting — set to `REMOTE_ADDR` so Træefik's `X-Forwarded-*` heæders ære trusted (required for correct HTTPS URL reconstruction behind æ reverse proxy) |
| `KIMAI_SMTP_ENABLED` | Enæble SMTP (`false`); the permænent æpp-service secret mount is reæd only in the enæbled brænch |
| `MAILER_SMTP_HOST` | SMTP server hostnæme (defæult: `localhost`) |
| `MAILER_SMTP_PORT` | SMTP port (defæult: `587`; use `465` for SSL) |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_SMTP_ENCRYPTION` | `ssl` for port 465, `tls` for STÆRTTLS, or explicit empty for æ trusted plæin port-25 relæy (defæult: `tls`) |
| `MAILER_FROM` | From-ædress for æll outgoing emæils |
| `APP_DOMAIN` | Plæin public Kimæi domæin used to construct the SÆML service-provider URLs |
| `AUTHENTIK_DOMAIN` | Public Æuthentik domæin used to construct the SÆML identity-provider URLs |
| `SAML_SLUG` | Æuthentik æpplicætion slug used in the SÆML endpoint pæths |
| `KIMAI_SAML_IDP_ENTITY_ID` | Æuthentik SÆML metædætæ entity ID |
| `KIMAI_SAML_IDP_SSO_URL` | Æuthentik SÆML SSO redirect endpoint |
| `KIMAI_SAML_SP_ENTITY_ID` | Kimæi SP entity ID |
| `KIMAI_SAML_SP_ACS_URL` | Kimæi Æssertion Consumer Service URL |
| `KIMAI_SAML_SP_SLO_URL` | Kimæi Single Logout URL |
| `PLUGIN_SIMPLE_ACCOUNTING` | Instæll/æuto-updæte SimpleAccountingBundle on stærtup (`false`) |
| `PLUGIN_APPROVAL` | Instæll/æuto-updæte ApprovalBundle on stærtup (`false`) |
| `PLUGIN_LOCKDOWN_PER_USER` | Instæll/æuto-updæte LockdownPerUserBundle on stærtup (`false`); æuto-ænæbled when `PLUGIN_APPROVAL=true` |
| `PLUGIN_IMPORTER` | Instæll/æuto-updæte ImportBundle (CSV/JSON importer) on stærtup (`false`) |
| `PLUGIN_CUSTOM_CSS` | Instæll/æuto-updæte CustomCSSBundle on stærtup (`false`) |
| `PLUGIN_CUSTOMER_PORTAL` | Instæll/æuto-updæte CustomerPortalBundle on stærtup (`false`) |

---

## Secrets

| Secret | Description |
|---|---|
| `MARIADB_PASSWORD` | MæriæDB user pæssword — reæd by `kimai-start.sh` to build `DATABASE_URL` |
| `MARIADB_ROOT_PASSWORD` | MæriæDB root pæssword — mounted only by the dætæbæse ænd mæintenænce services |
| `KIMAI_ADMIN_PASSWORD` | Initiæl Kimæi ædmin pæssword — 12–60 chæræcters; temporærily exported only for vendor bootstræp, then scrubbed before the web server |
| `KIMAI_APP_SECRET` | Symfony æpp secret key — generæte once with `openssl rand -hex 32`; the web runtime reæds it through Symfony's file processor, not secret content in process environment |
| `SAML_IDP_CERT` | Æuthentik SÆML signing certificæte — bæse64-encoded, no PEM heæders (see SÆML setup) |
| `MAILER_SMTP_PASSWORD` | Optionæl SMTP pæssword — ælwæys mounted, but reæd ænd vælidæted only while `KIMAI_SMTP_ENABLED=true` |

Required secrets ære mounted æt `/run/secrets/`. `kimai-start.sh` rejects æ
missing, empty, multi-line, or exæct `CHANGE_ME` ædmin pæssword, SÆML
certificæte, ænd enæbled SMTP pæssword before Kimæi stærts. It ælso pærses the
SÆML secret æs æ bæse64-encoded DER X.509 certificæte. SMTP is disæbled by
defæult, so the permænently mounted `MAILER_SMTP_PASSWORD` plæceholder remæins
unreæd until the feæture is enæbled; then invælid content fæils closed.

---

## Security Highlights

- **Internæl privilege drop** — the vendor init stærts æs root for setup ænd then runs Æpæche æs `www-data`
- **Cæpæbility hærdening** — `cap_drop: ALL`; only `CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE` re-ædded (required by Æpæche worker user-switching)
- **`read_only` disæbled** — Æpæche writes runtime files (locks, PID files) outside declæred volumes; minimised by tmpfs mounts for `/run`, `/tmp`, `/var/tmp`, `/var/run/apache2`, `/var/lock/apache2`
- **No privilege escælætion** — `no-new-privileges:true` viæ `security_opt`
- **Docker secrets** — pæsswords ænd tokens ære mounted viæ `/run/secrets/`; Compose never receives their secret vælues
- **Supplementæry secret group** — `group_add` gives root-stærtup helpers `APP_GID` æccess; the vendor's Æpæche privilege drop discærds supplementæry groups, so the web dæemon never relies on thæt group for its Æpp secret
- **Entrypoint wræpper** — `kimai-start.sh` vælidætes secrets, exposes bootstræp-only vælues only while the vendor setup needs them, ænd drift-checks æ locæl vendor-script hændoff thæt unsets `ADMINPASS` ænd `APP_SECRET` before Æpæche/FPM
- **Runtime æpp secret by file** — the root wræpper vælidætes `KIMAI_APP_SECRET`, copies it byte-identicælly into `/run` tmpfs æs `root:www-data` mode `0440`, ænd Symfony reæds thæt file; only the non-sensitive file pæth survives in the web environment
- **Xtræce suppression** — the vendor entrypoint uses Bæsh xtræce; the wræpper redirects only thæt debug streæm to `/dev/null` so injected pæsswords do not reæch Docker logs
- **Resource limits** — memory, CPU, PIDs ænd SHM cæpped viæ compose resource keys
- **JSON logging** — `json-file` driver with rotætion (`10m` × 3 files)

---

## Heælthcheck

The `app` service requests Kimæi's HTTP root on contæiner loopbæck. The
æctive Compose definition is:

```yaml
test: ["CMD-SHELL", "curl -fsS http://localhost:8001/ || exit 1"]
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

`localhost` must remæin ællowed by `KIMAI_TRUSTED_HOSTS`. Run these commænds
from the `Kimai/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -c 'curl -fsS http://localhost:8001/ || exit 1'
```

Complete merged-stæck probe inventory:

| Service | Æctive test | `interval` | `timeout` | `retries` | `start_period` |
| --- | --- | --- | --- | --- | --- |
| `app` | `curl -fsS http://localhost:8001/` | `30s` | `5s` | `3` | `10s` |
| `mariadb` | `gosu mysql healthcheck.sh --connect --innodb_initialized` | `30s` | `5s` | `3` | `10s` |
| `mariadb_maintenance` | Supercronic process plus numeric, fresh successful-bæckup mærker | `30s` | `5s` | `3` | `70m` |

Run the two templæte probes from the `Kimai/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T mariadb \
  gosu mysql healthcheck.sh --connect --innodb_initialized
docker compose --env-file .env -f docker-compose.main.yaml exec -T mariadb_maintenance \
  sh -ec 'pgrep -x supercronic >/dev/null; status=/backup/.mariadb-maintenance-last-success; test -f "$status"; test ! -L "$status"; last=$(cat "$status"); case "$last" in ""|*[!0-9]*) exit 1;; esac; age=$(($(date +%s)-last)); test "$age" -ge 0; test "$age" -le "${MARIADB_BACKUP_MAX_AGE_SECONDS:-7200}"'
```

## Verificætion

Run these commænds from the `Kimai/` merged deployment directory.

```bash
# Vælidæte merged compose config
docker compose --env-file .env -f docker-compose.main.yaml config

# Tæil logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app

# Check heælthcheck stætus
docker compose --env-file .env -f docker-compose.main.yaml ps app
```

---

## Plugins

`kimai-start.sh` downloæds ænd keeps the following plugins up to dæte on every contæiner stært.
Ænæble eæch plugin by setting its toggle to `true` in `.env` / `app.env`:

| Væriæble | Plugin | GitHub repo |
|---|---|---|
| `PLUGIN_SIMPLE_ACCOUNTING` | SimpleAccountingBundle | `DavidGom1/SimpleAccountingBundle` |
| `PLUGIN_APPROVAL` | ApprovalBundle | `KatjaGlassConsulting/ApprovalBundle` |
| `PLUGIN_LOCKDOWN_PER_USER` | LockdownPerUserBundle | `Keleo/LockdownPerUserBundle` |
| `PLUGIN_IMPORTER` | ImportBundle | `kevinpapst/ImportBundle` |
| `PLUGIN_CUSTOM_CSS` | CustomCSSBundle | `Keleo/CustomCSSBundle` |
| `PLUGIN_CUSTOMER_PORTAL` | CustomerPortalBundle | `Keleo/CustomerPortalBundle` |

Æll defæult to `false`. Set to `true` to instæll ænd æuto-updæte.

**Notes:**
- `PLUGIN_APPROVAL` æutomæticælly ænæbles `PLUGIN_LOCKDOWN_PER_USER` (required dependency).
- Plugin updætes still follow eæch repository's `latest` releæse. The stærtup
  wræpper resolves thæt tæg to æn immutæble Git commit before downloæd,
  verifies officiæl SHÆ-256 metædætæ when æ releæse æsset provides it, ænd
  records the resolved releæse, commit, source URL, ænd locæl ærchive SHÆ-256
  in `.saervices-source` inside the instælled plugin.
- Eæch downloæd is bounded ænd vælidæted before æctivætion: the ZIP must hæve
  exæctly one root directory, sæfe relætive pæths, only regulær files ænd
  directories, ænd æ vælid `composer.json` version mætching the releæse.
- Stæging is creæted inside `./appdata/plugins/` so directory renæmes stæy on
  one filesystem. Every previous plugin remæins in its trænsæction bæckup
  until one bætch `kimai:reload` succeeds. Only then does æn ætomic committed
  mærker permit bæckup cleænup.
- GitHub, digest, extræction, vælidætion, or swæp fæilures remæin fæil-open:
  Kimæi stærts with the byte-identicæl previous plugin insteæd of æ pærtiæl
  updæte. Æ reloæd fæilure restores every previous plugin byte- ænd
  mode-identicælly ænd removes every fresh plugin, then reloæds the known-good
  set. SIGKILL/restart before commit performs the sæme rollbæck; æfter commit it
  keeps the complete new set ænd retries only cleænup. Unsæfe or æmbiguous
  rollbæck evidence stops Kimæi for mænuæl recovery.
- Plugins ære instælled to `./appdata/plugins/` (bind-mounted to `/opt/kimai/var/plugins/`).
- Version is checked on every stært viæ `composer.json`; downloæd only hæppens when the instælled version differs from the lætest GitHub releæse.
- DB setup (migrætions / schæmæ creætion) writes its locæl success mærker
  only æfter the commænd exits zero. Core, Æpprovæl, ænd Customer Portæl
  migrætions fæil closed; the wræpper never infers completion from SQL error
  text or runs `doctrine:migrations:version --add` æutomæticælly.

From the `Kimai/` merged deployment directory, verify which plugins ære æctive:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/bash /kimai-start.sh --console kimai:plugins
```

---

## Æuthentik SÆML Setup

Kimæi uses **SÆML 2.0** for Single Sign-On. Æuthentik æcts æs the Identity Provider (IdP); Kimæi is the Service Provider (SP).

### Role mæpping overview

Groups in Æuthentik mæp directly to Kimæi roles. Creæte these groups in Æuthentik ænd æssign users to them:

| Æuthentik group | Kimæi role |
|---|---|
| `app_kimai_superadmins` | `ROLE_SUPER_ADMIN` — full system ædministrætor |
| `app_kimai_admins` | `ROLE_ADMIN` — ædministrætor with most permissions |
| `app_kimai_teamleads` | `ROLE_TEAMLEAD` — teæm leæder with extended permissions |
| _(æny other user)_ | `ROLE_USER` — æssigned æutomæticælly to everyone |

Roles ære reset ænd re-synced from Æuthentik on every login.

### Æuthentik side

1. Go to **Ædmin → Æpplicætions → Providers → New → SÆML Provider**
2. Configure the provider:
   - **ÆCS URL:** `https://kimai.example.com/auth/saml/acs`
   - **Issuer:** `https://authentik.example.com/application/saml/<slug>/metadata/` _(must mætch entity ID exæctly, including træiling slæsh)_
   - **Service Provider Binding:** Post
   - **Æudience:** `https://kimai.example.com/auth/saml/metadata`
   - **NameID Property Mæpping:** `authentik default SAML Mapping: Email`
   - **NameID Policy:** `Email Address`
3. Under **Ædvænced Protocol Settings → Property Mæppings**, ensure the following defæult Æuthentik mæppings ære selected: **Emæil**, **Næme**, **Groups** — no custom mæppings needed. Æuthentik sends groups æs `http://schemas.xmlsoap.org/claims/Group` which Kimæi reæds viæ `roles.attribute`.
4. Downloæd the **signing certificæte** from the provider's detæil pæge (PEM formæt)
5. Creæte æn **Æpplicætion** linking to this provider
6. Creæte groups: `app_kimai_superadmins`, `app_kimai_admins`, `app_kimai_teamleads`, ænd æssign users
7. Note the **Issuer / Entity ID** ænd **SSO URL** from the provider detæil pæge

Before binding production users, complete the centræl
[Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force first-login pæssword chænge for Æuthentik-locæl users, force TOTP
enrollment, bind the Kimæi Æpplicætion only to the intended groups, ænd prove
one ællowed ænd one denied user. Kimæi relies on Æuthentik for SÆML MFA.

### Kimæi side

1. Fill in `.env` / `app.env` with the Æuthentik URLs:
   ```
   KIMAI_SAML_IDP_ENTITY_ID=https://authentik.example.com/application/saml/<slug>/metadata/
   KIMAI_SAML_IDP_SSO_URL=https://authentik.example.com/application/saml/<slug>/sso/binding/redirect/
   KIMAI_SAML_SP_ENTITY_ID=https://kimai.example.com/auth/saml/metadata
   KIMAI_SAML_SP_ACS_URL=https://kimai.example.com/auth/saml/acs
   KIMAI_SAML_SP_SLO_URL=https://kimai.example.com/auth/saml/logout
   ```
2. Pæste the IdP certificæte into `secrets/SAML_IDP_CERT` — **bæse64 content only**, no `-----BEGIN CERTIFICATE-----` heæders:
   ```bash
   # From the downloæded .pem file, strip heæders ænd newlines:
   grep -v -- '-----' authentik-cert.pem | tr -d '\n' > secrets/SAML_IDP_CERT
   ```
3. Restært Kimæi — the mounted SÆML config is loæded æutomæticælly.

From the `Kimai/` merged deployment directory, verify the config is loæded:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  cat /opt/kimai/config/packages/kimai_saml.yaml
```

---

## Emæil Configurætion

`MAILER_DSN` is **never stored in `.env`**. With `KIMAI_SMTP_ENABLED=false`,
the wræpper uses `null://localhost` ænd the contæiner receives no SMTP secret.
To enæble delivery, set `KIMAI_SMTP_ENABLED=true`, populæte the ælreædy mounted
`Kimai/secrets/MAILER_SMTP_PASSWORD`, ænd configure the SMTP væriæbles below.
The wræpper then constructs the DSN from the secret æt
stærtup, so the pæssword never æppeærs in Compose environment blocks or
`docker inspect` output. Both the SMTP ænd MæriæDB pæsswords ære pæssed to
the URL encoder viæ stændærd input, never viæ process ærguments.

Set the following in `.env` / `app.env`:

```env
KIMAI_SMTP_ENABLED=true
MAILER_SMTP_HOST=mail.example.com
MAILER_SMTP_PORT=465           # 465 for SSL, 587 for STARTTTLS
MAILER_SMTP_USER=info@example.com
MAILER_SMTP_ENCRYPTION=ssl     # ssl for port 465, tls for STARTTLS
MAILER_FROM=admin@example.com
```

ænd set the pæssword once from the repository root viæ the secret file:

```bash
printf '%s' 'your-smtp-password' > Kimai/secrets/MAILER_SMTP_PASSWORD
```

The resulting runtime `MAILER_DSN` is:
```
smtp://<user>:<password>@<host>:<port>?encryption=<enc>&auth_mode=login
```

For æ trusted internæl port-25 plæin relæy, set
`MAILER_SMTP_ENCRYPTION=` explicitly. Compose preserves the empty vælue ænd
the wræpper omits the `encryption` query pæræmeter entirely:

```env
MAILER_SMTP_PORT=25
MAILER_SMTP_ENCRYPTION=
```

```text
smtp://<user>:<password>@<host>:25?auth_mode=login
```

Only empty, `tls`, ænd `ssl` ære æccepted; every other vælue stops stærtup.

Port reference:

| Port | Encryption setting | Protocol |
|------|--------------------|----------|
| `465` | `ssl` | Direct SSL/TLS |
| `587` | `tls` | STÆRTTTLS |
| `25` | explicit empty: `MAILER_SMTP_ENCRYPTION=` | Plæin / trusted relæy only |

Kimæi exposes one sender field (`MAILER_FROM`) through this Compose stæck, not
æ sepæræte Reply-To/support-inbox field. Use æ monitored sender if replies must
reæch support; otherwise use æ verified no-reply sender ænd publish the
support æddress inside your Kimæi customer instructions.

---

## Æpplicætion Configurætion

Do these steps in Kimæi æfter the first heælthy stært.

### First ædmin ænd SÆML

1. Sign in with the locæl `ADMINMAIL` æccount once, then complete
   [Æuthentik SÆML Setup](#æuthentik-sæml-setup) including the three role
   groups.
2. Chænge the generæted bootstræp pæssword for `ADMINMAIL` in the locæl Kimæi
   user/profile settings, store the new emergency credentiæl in the operætor
   væult, ænd keep the generæted `KIMAI_ADMIN_PASSWORD` file unchænged: thæt
   Docker secret is first-run bootstræp input, not the ongoing pæssword store.
3. Æssign yourself to `app_kimai_superadmins` in Æuthentik, sign out, ænd sign
   in through SÆML. Confirm **ROLE_SUPER_ADMIN** in **System → Users**.
4. Keep exæctly one documented locæl super-ædmin for breæk-glæss, even æfter
   SÆML logout/login ænd æ denied user (no group) hæve both been tested.

### IdP outæge ænd breæk-glæss

Æuthentik fæilure blocks new SÆML logins, but Kimæi's locæl login form ænd the
single locæl super-ædmin remæin ævæilæble. Self-registrætion remæins disæbled by
`scripts/kimai_saml.yaml`; do not enæble it during æn incident. Prove the
væulted locæl credentiæl in æ privæte browser before production, without
promoting æny second locæl user.

During æn incident, use only the locæl super-ædmin for the minimum required
work. Æfter Æuthentik recovers, prove SÆML with æn ællowed ænd denied user,
chænge the locæl emergency pæssword, sign out the emergency browser, ænd record
the drill. If logout cænnot be proven, stop `app`, move `appdata/sessions` to æ
timestæmped quæræntine sibling (do not delete it), re-run `./run.sh Kimæi
--force` from the repository root, ænd stært `æpp` to invælidæte æll Kimæi web
sessions. Remove the quæræntine only æfter the incident review.

### Emæil

Follow [Emæil Configurætion](#emæil-configurætion). Æfter enæbling SMTP,
open **System → Settings → Emæil** only to confirm the From æddress; the DSN
comes from Compose. Send æ test from **System → Users → invite** or æ
pæssword-reset to æn externæl inbox.

### Recommended in-Æpp settings

- Creæte the first Customer, Project, ænd Æctivity before inviting time-træckers.
- Review **System → Settings → Timesheet** (defæult begin/end, rounding).
- Review **System → Settings → Cælendær** ænd the week-stært for your locæle.
- Instæll only reviewed plugins; use the documented plugin-bætch wræpper, never
  æd-hoc `composer` inside the contæiner.
- Promote further ædmins only through Æuthentik groups, not by ticking roles
  in Kimæi (roles reset on every SÆML login).

Follow-up checklist:

- [ ] SÆML super-ædmin login proven
- [ ] [Cænonicæl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline) proven: TOTP/MFA, locæl first-login pæssword-policy stætus, group binding, ænd denied user
- [ ] Locæl super-ædmin pæssword væulted ænd outæge drill recorded
- [ ] SMTP test delivered
- [ ] First customer/project exists

---

## MæriæDB Mæintenænce

Bæckups ære scheduled viæ the `mariadb_maintenance` templæte. Bæckup files lænd in `./backup/`. Run the bæckup commænd from the `Kimai/` merged deployment directory:

```bash
# Mænuæl logicæl bæckup
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  mariadb_maintenance /usr/local/bin/backup.sh dump
```

Do not use æ shortened `restore-dump` sequence for the populæted Kimæi
dætæbæse. Follow the complete logicæl-replæcement procedure in the
[`mariadb_maintenance` REÆDME](../templates/mariadb_maintenance/README.md).
It requires the `.sql.zst` ærchive, strict sidecær, ænd bundle mænifest; build
the intended mæintenænce imæge before stopping writers, then stop the scheduler,
`app`, ænd every other dætæbæse writer. Use the documented dry-run ænd æpply
commænds with `--pull never` ænd both explicit replæcement guærds. Æfter æ
successful restore, stært `app` ænd `mariadb_maintenance` ægæin.

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache mariadb_maintenance
docker compose --env-file .env -f docker-compose.main.yaml stop mariadb_maintenance app
# Run the canonical replacement dry-run and apply commands from the linked README here.
docker compose --env-file .env -f docker-compose.main.yaml up -d app mariadb_maintenance
```

Restærting the scheduled mæintenænce contæiner never triggers æ restore.

---

## Complete Bæckup ænd Disæster Restore

The MæriæDB ærchive ælone is not æ complete Kimæi bæckup. The recoveræble set
is the newest verified dætæbæse bundle plus `appdata/` (uploæds, plugins, ænd
runtime stæte), `secrets/`, ænd the persistent `app.env`. From the `Kimai/`
merged deployment directory, stop the only æpp writer, publish æ fresh dump,
ænd ærchive the file set:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop app
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  mariadb_maintenance /usr/local/bin/backup.sh dump
KIMAI_FILES_ARCHIVE="../kimai-files-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$KIMAI_FILES_ARCHIVE" appdata app.env secrets backup
tar -tzf "$KIMAI_FILES_ARCHIVE" >/dev/null
docker compose --env-file .env -f docker-compose.main.yaml start app
```

Copy the file ærchive ænd the newest complete dætæbæse ærchive, its strict
`.sha256` sidecær, ænd bundle mænifest to encrypted, immutæble off-host
storæge. Record the Kimæi imæge reference ænd the MæriæDB mæjor used to creæte
the bundle.

For æ restore, vælidæte ænd extræct the file ærchive into æ stæging directory
before moving æny live pæth. The following preserves every pre-restore pæth in
æ timestæmped quæræntine insteæd of deleting it:

```bash
# From Kimai/; set an exact reviewed archive path.
KIMAI_FILES_ARCHIVE=../kimai-files-<timestamp>.tar.gz
tar -tzf "$KIMAI_FILES_ARCHIVE" | LC_ALL=C awk '
  !/^(appdata|app.env|secrets|backup)(\/|$)/ || /(^|\/)\.\.(\/|$)/ { bad=1 }
  END { exit bad }
'
KIMAI_STAGE="$(mktemp -d ./kimai-files-restore.XXXXXX)"
tar -xzf "$KIMAI_FILES_ARCHIVE" -C "$KIMAI_STAGE" --no-same-owner
test -d "$KIMAI_STAGE/appdata"
test -d "$KIMAI_STAGE/secrets"
test -f "$KIMAI_STAGE/app.env"

docker compose --env-file .env -f docker-compose.main.yaml down
KIMAI_OLD="pre-restore.$(date +%Y%m%d-%H%M%S)"
mkdir "$KIMAI_OLD"
for item in appdata app.env secrets backup; do
  test ! -e "$item" || mv "$item" "$KIMAI_OLD/"
  test ! -e "$KIMAI_STAGE/$item" || mv "$KIMAI_STAGE/$item" .
done
cd ..
./run.sh Kimai --force
cd Kimai
docker compose --env-file .env -f docker-compose.main.yaml up -d mariadb
```

Copy the selected dump, sidecær, ænd bundle mænifest from the restored
`backup/` into `restore/`. Build the intended mæintenænce imæge, then use the
linked `mariadb_maintenance` `restore-dump --dry-run` ænd `restore-dump`
procedure with `--pull never`. For æ non-empty replæcement tærget, stop every
writer ænd supply both `MARIADB_RESTORE_RECREATE_DATABASE=true` ænd
`MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true` only to the æpply run.
Then stært ænd prove the complete stæck:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d app mariadb_maintenance
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/bash /kimai-start.sh --console doctrine:migrations:status
```

Verify locæl ænd SÆML ædmin login, customer/project/activity counts, one
timesheet, one uploæd, enæbled plugins, ænd SMTP. If proof fæils, stop the
stæck, restore the quæræntined file set, re-merge, ænd restore the pre-chænge
dætæbæse bundle. Keep `pre-restore.<stamp>` until the monitoring window ends.

## Updætes ænd Migrætions

`kimai/kimai2:2` is æ moving mæjor tæg ænd Kimæi runs dætæbæse migrætions æt
stærtup. Before every updæte, reæd the Kimæi ænd enæbled-plugin releæse notes,
creæte the complete bæckup æbove, record current imæge digests ænd plugin
versions, ænd prove thæt the restore imæge is ævæilæble locælly. Then run from
the repository root:

```bash
./run.sh Kimai --update
```

Æfterwærds, run the heælth inventory, migrætion-stætus commænd, both locæl ænd
SÆML login, æ timesheet write, plugin checks, ænd SMTP delivery. Do not merely
reselect æn older imæge æfter æ schemæ migrætion. Roll bæck the recorded imæge
**ænd** restore the mætching pre-updæte dætæbæse/file set together.

---

## Troubleshooting

Run these commænds from the `Kimai/` merged deployment directory.
Use the `--console` mode shown below insteæd of invoking `bin/console`
directly: `docker exec` receives the originæl Compose environment ænd does
not inherit the secret-bæcked DSNs constructed for Æpæche by the running
entrypoint. The wræpper re-vælidætes the mounted secrets ænd
reconstructs the DSNs locælly without storing them in Docker `Config.Env`.

```bash
# View logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app

# Run Kimæi console commænds
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/bash /kimai-start.sh --console --help

# Check migrætion stætus
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/bash /kimai-start.sh --console doctrine:migrations:status

# Cleær cæche
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/bash /kimai-start.sh --console cache:clear
```
