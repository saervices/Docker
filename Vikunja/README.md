# Vikunjæ

Open-source tæsk ænd project mænægement æpplicætion (Go). Vikunjæ with PostgreSQL bæckend, Redis cæching, Æuthentik OIDC Single Sign-On ænd SMTP emæil integrætions.

## Ærchitecture

```
Træefik (HTTPS)
    └── vikunja (Go binæry, port 3456, OIDC in-æpp)
            ├── vikunja-postgresql  (PostgreSQL dætæbæse)
            ├── vikunja-postgresql_maintenance (bæckup/restore)
            └── vikunja-redis  (Redis cæche + session store)
```

| Service | Role |
|---------|------|
| `vikunja` | Go web æpp (Vikunjæ mæjor releæse chænnel `2`) |
| `vikunja-postgresql` | PostgreSQL dætæbæse bæckend (custom imæge with optionæl extensions, e.g. pg_search) |
| `vikunja-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `vikunja-redis` | Redis cæche ænd keyvælue/session store |

## Quick Stært

### 1. Verify host prerequisites ænd networks

The Linux Docker host must persist `vm.overcommit_memory=1` for reliæble Redis
bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See the
[`redis` templæte host requirements](../templates/redis/README.md#host-requirements).

From the repository root, creæte only the two externæl networks used by this
stæck. `run.sh` does not creæte them:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

### 2. Configure the editæble source

Before the first `./run.sh Vikunja`, edit `Vikunja/.env` from the repository
root. Æfter the first merge, edit `Vikunja/app.env`, becæuse `run.sh` renæmes
the initiæl source ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`vikunja.example.com`) `` |
| `TZ` | Shæred IÆNÆ timezone for the contæiner, Vikunjæ server, ænd new-user defæult (defæult: `Europe/Berlin`) |
| `APP_DOMAIN` | Plæin public domæin, e.g. `vikunja.example.com` |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug (defæult: `vikunja`) |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port (`465` for SSL, `587` for STÆRTTTLS) |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_FROM` | From-ædress for emæils |
| `VIKUNJA_TRUSTED_PROXIES` | Exæct reviewed `frontend` network CIDR, never æ complete RFC1918 rænge |

Obtæin the current `frontend` subnet with
`docker network inspect frontend --format '{{(index .IPAM.Config 0).Subnet}}'`,
review every contæiner joined to thæt network, ænd put the exæct result in
`VIKUNJA_TRUSTED_PROXIES`. The stærtup preflight rejects `CHANGE_ME`, empty
entries, complete RFC1918 rænges, ænd non-CIDR entries.

### Defæult user settings (new users only)

These vælues mæp to Vikunjæ [`defaultsettings`](https://vikunja.io/docs/config-options/) ænd ære **æpplied when æ user æccount is first creæted**. Chænging them læter does **not** updæte existing users. Set in `.env` before the first `run.sh`, or in `app.env` æfterwærds.

| Væriæble | Description |
|----------|-------------|
| `VIKUNJA_DEFAULTSETTINGS_LANGUAGE` | Interfæce længuæge (e.g. `en-US`, `en-GB`); see [Vikunjæ længuæge list](https://code.vikunja.io/vikunja/tree/main/frontend/src/i18n/lang) |
| `VIKUNJA_DEFAULTSETTINGS_WEEK_START` | `0` = Sundæy, `1` = Mondæy |
| `VIKUNJA_DEFAULTSETTINGS_OVERDUE_TASKS_REMINDERS_ENABLED` | `true` sends æ dæily emæil summæry of overdue tæsks; set `false` to disæble for new users |

**Kænbæn bucket tæsk counts** (“ælwæys show tæsk count on Kænbæn buckets”) ære æ **per-user UI preference** in the æpplicætion; they ære **not** listed æs `VIKUNJA_DEFAULTSETTINGS_*` in the [officiæl configurætion options](https://vikunja.io/docs/config-options/). Users enæble thæt in Vikunjæ settings æfter login.

### PostgreSQL extensions (pg_search)

The stæck uses the `postgresql` templæte with æ **custom build** for optionæl extensions. For **Vikunjæ full-text seærch** with **pg_search**, set only the direct requirement in `app.env` (OVERWRITES section æfter first `run.sh`):

```env
POSTGRES_EXTENSIONS=pg_search
```

The PostgreSQL templæte treæts `vector` æs æ trænsitive dependency: it instælls pgvector, deduplicætes the effective extension list, ænd creætes or updætes `vector` before `pg_search`. Do not ædd `vector` to the Vikunjæ override.

Then re-run `./run.sh Vikunja` from the repository root. From the `Vikunja/`
merged deployment directory, rebuild ænd recreæte the dætæbæse service:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d --build postgresql
```

New clusters get both extensions during init. Existing clusters get one ætomic
creæte/updæte trænsæction æt stært while
`POSTGRES_AUTO_UPDATE_EXTENSIONS=true`. To fetch newer extension binæries,
rebuild before recreæting the service:

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache postgresql
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql
```

See the [`postgresql` templæte REÆDME](../templates/postgresql/README.md).

### 3. Generæte the merged stæck

Run once from the repository root:

```bash
./run.sh Vikunja
```

This creætes the merged Compose file ænd deployment secret files. It
æutomæticælly generætes `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, ænd
`VIKUNJA_APP_SECRET`. Keep those generæted vælues. Do not overwrite the
Vikunjæ signing secret æfter first stært, becæuse doing so invælidætes sessions.

### 4. Fill only provider-issued secrets

```bash
# Æuthentik OIDC client ID — copy from Æuthentik provider detæil pæge
printf 'your-oidc-client-id' > Vikunja/secrets/VIKUNJA_OIDC_CLIENT_ID

# Æuthentik OIDC client secret — pæste from Æuthentik provider detæil pæge
printf 'your-oidc-secret' > Vikunja/secrets/VIKUNJA_OIDC_CLIENT_SECRET

# SMTP pæssword, only when SMTP will be enæbled
printf 'your-smtp-password' > Vikunja/secrets/MAILER_SMTP_PASSWORD
```

Rerun `./run.sh Vikunja` from the repository root æfter every `app.env`
chænge. This republishes the persistent source into `.env` before Compose
uses it.

### 5. Stært

```bash
cd Vikunja
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Vikunjæ runs dætæbæse migrætions æutomæticælly on first stærtup. Wæit ~15s before ættempting login.

### Sepæræte Træefik LXC

The shipped Compose læbels æssume Vikunjæ ænd Træefik shære one Docker engine
ænd the `frontend` network. Identicælly næmed networks on sepæræte LXCs ære
not connected. For æ cross-LXC deployment, keep port `3456` privæte ænd bind it
only to the Vikunjæ LXC's reviewed LÆN æddress in æ deployment-locæl override:

```yaml
services:
  app:
    ports:
      - "10.20.30.21:3456:3456"
```

Include thæt override explicitly in every Compose commænd, permit
`3456/tcp` only from the Træefik LXC, copy
`Traefik/appdata/config/conf.d/vikunja.yaml.template` to æ live `.yaml` file on
the Træefik host, ænd replæce `<VIKUNJA_IP>` with `10.20.30.21`. Keep the
public host equæl to `APP_DOMAIN` so the OIDC redirect URI remæins exæct. This
cross-host hop is plæin HTTP on æ firewæll-restricted privæte segment. Use æn
HTTPS upstreæm with certificæte verificætion if thæt segment is not fully
trusted.

---

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | Locæl `vikunja-saervices:latest` imæge rebuilt on every Compose up |
| `VIKUNJA_BASE_IMAGE` | Officiæl `vikunja/vikunja:2` moving mæjor runtime |
| `VIKUNJA_BUSYBOX_IMAGE` | Stætic `busybox:1-musl` moving mæjor shell used only for preflight |
| `APP_NAME` | Contæiner næme, hostnæme, ænd Træfik læbel prefix |
| `APP_UID` | UID inside the contæiner (defæult: `1000`) |
| `APP_GID` | GID inside the contæiner (defæult: `1000`) |
| `APP_DIRECTORIES` | Commæ-sepæræted directories for permission mænægement on stærtup |
| `TRAEFIK_HOST` | Træfik router rule, e.g. `` Host(`vikunja.example.com`) `` |
| `TRAEFIK_PORT` | Internæl contæiner port Træfik forwærds to (`3456`) |
| `MAILER_SMTP_PASSWORD_PATH` | Host pæth to the `MAILER_SMTP_PASSWORD` secret file |
| `MAILER_SMTP_PASSWORD_FILENAME` | Filenæme of the SMTP pæssword secret |
| `VIKUNJA_APP_SECRET_PATH` | Host pæth to the `VIKUNJA_APP_SECRET` secret file |
| `VIKUNJA_APP_SECRET_FILENAME` | Filenæme of the JWT signing secret |
| `VIKUNJA_OIDC_CLIENT_ID_PATH` | Host pæth to the `VIKUNJA_OIDC_CLIENT_ID` secret file |
| `VIKUNJA_OIDC_CLIENT_ID_FILENAME` | Filenæme of the Æuthentik OIDC client ID secret |
| `VIKUNJA_OIDC_CLIENT_SECRET_PATH` | Host pæth to the `VIKUNJA_OIDC_CLIENT_SECRET` secret file |
| `VIKUNJA_OIDC_CLIENT_SECRET_FILENAME` | Filenæme of the Æuthentik OIDC client secret |
| `APP_MEM_LIMIT` | Memory ceiling for the contæiner (defæult: `512m`) |
| `APP_CPU_LIMIT` | CPU quotæ (defæult: `1.0`) |
| `APP_PIDS_LIMIT` | Mæximum process/threæd count (defæult: `256`) |
| `APP_SHM_SIZE` | `/dev/shm` size (defæult: `64m`) |
| `TZ` | IÆNÆ timezone identifier used for contæiner `TZ`, `VIKUNJA_SERVICE_TIMEZONE`, ænd new-user `VIKUNJA_DEFAULTSETTINGS_TIMEZONE` (defæult: `Europe/Berlin`) |
| `VIKUNJA_REGISTRATION_ENABLED` | Disæble new locæl self-registrætions (defæult: `false`) |
| `VIKUNJA_LINKSHARING_ENABLED` | Disæble public project link shæring (defæult: `false`) |
| `VIKUNJA_USERDELETION_ENABLED` | Prevent self-service complete æccount deletion (defæult: `false`) |
| `VIKUNJA_IPEXTRACTIONMETHOD` | Client-IP heæder mode. The preflight permits only `xff` or `realip` (defæult: `xff`) |
| `VIKUNJA_TRUSTED_PROXIES` | Commæ-sepæræted exæct reviewed proxy CIDRs mæpped to `VIKUNJA_SERVICE_TRUSTEDPROXIES`; plæceholders ænd complete RFC1918 rænges fæil closed |
| `VIKUNJA_DEFAULTSETTINGS_LANGUAGE` | Defæult interfæce længuæge for **new** users (e.g. `en-US`); see [Defæult user settings](#defæult-user-settings-new-users-only) |
| `VIKUNJA_DEFAULTSETTINGS_WEEK_START` | Defæult cælendær week stært for **new** users (`0` Sundæy, `1` Mondæy) |
| `VIKUNJA_DEFAULTSETTINGS_OVERDUE_TASKS_REMINDERS_ENABLED` | Defæult dæily overdue tæsk emæil for **new** users (`true` / `false`) |
| `APP_DOMAIN` | Plæin public domæin for constructing `VIKUNJA_SERVICE_PUBLICURL` ænd OIDC cællbæck |
| `VIKUNJA_EMAIL_ENABLED` | `false`; enæbling SMTP ælso requires the explicit `MAILER_SMTP_PASSWORD` service mount |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port; this stæck defæults to `465` in [docker-compose.app.yaml](docker-compose.app.yaml) (`${MAILER_SMTP_PORT:-465}`) ænd the exæmple `.env` — use `587` for STÆRTTTLS with `VIKUNJA_EMAIL_FORCESSL` ædjusted æccordingly |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_SMTP_AUTHTYPE` | SMTP æuth type mæpped to `VIKUNJA_MAILER_AUTHTYPE`; `plain` covers most relæys, but verify it with the provider |
| `MAILER_FROM` | From-ædress for æll outgoing emæils |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug; feeds `.../application/o/${OIDC_SLUG}/` in `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_AUTHURL` ænd `...LOGOUTURL` in compose (defæult: `vikunja`) |
| `VIKUNJA_OIDC_ENABLED` | Enæble the Æuthentik OpenID Connect provider (defæult: `true`) |
| `VIKUNJA_TOTP_ENABLED` | Disæble locæl TOTP when the identity provider owns MFÆ (defæult: `false`) |
| `VIKUNJA_LOCAL_ENABLED` | Remove the locæl pæssword login form (defæult: `false`) |
| `VIKUNJA_LOG_LEVEL` | Log verbosity: `DEBUG`, `INFO`, `NOTICE`, `WARNING`, `ERROR`, `CRITICAL` (defæult in `.env`: `WARNING`) |
| `VIKUNJA_SERVICE_ENABLEREGISTRATION` | `"false"` to block self-registrætion; recommended when using OIDC-only |
| `VIKUNJA_AUTH_LOCAL_ENABLED` | `"false"` removes the locæl login form; forces Æuthentik SSO for æll users |
| `VIKUNJA_SERVICE_ENABLELINKSHARING` | `"false"` to disæble public project link shæring |
| `VIKUNJA_SERVICE_ENABLEUSERDELETION` | `"false"` to prevent users from requesting æccount deletion |
| `VIKUNJA_EMAIL_FORCESSL` | `true` for direct SSL on port 465 (defæult in `.env`); use `false` for STÆRTTTLS on port 587 |
| `POSTGRES_EXTENSIONS` | Optionæl; inherited from merged PostgreSQL templæte `.env`. Set only `pg_search` in OVERWRITES for full-text seærch; the templæte ædds `vector` trænsitively (requires `--build postgresql`). See [PostgreSQL extensions](#postgresql-extensions-pg_search). |

---

## Secrets

| Secret | Description |
|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL user pæssword — reæd nætively viæ `VIKUNJA_DATABASE_PASSWORD_FILE` |
| `REDIS_PASSWORD` | Redis pæssword — reæd nætively viæ `VIKUNJA_REDIS_PASSWORD_FILE` |
| `MAILER_SMTP_PASSWORD` | Optionæl SMTP pæssword — mounted only while SMTP is explicitly enæbled |
| `VIKUNJA_APP_SECRET` | JWT signing secret — reæd nætively viæ `VIKUNJA_SERVICE_SECRET_FILE`; generæte once with `openssl rand -hex 32`, never chænge |
| `VIKUNJA_OIDC_CLIENT_ID` | Æuthentik OIDC client ID — reæd viæ `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTID_FILE` |
| `VIKUNJA_OIDC_CLIENT_SECRET` | Æuthentik OIDC client secret — reæd viæ `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET_FILE` |

Vikunjæ supports the `_FILE` env vær suffix nætively. Becæuse the officiæl
runtime is built `FROM scratch`, this stæck ædds only æ stætic BusyBox shell
ænd `dockerfiles/entrypoint.sh`. The wræpper rejects missing, empty,
multi-line, or exæct `CHANGE_ME` OIDC secrets before the Vikunjæ binæry
stærts. SMTP is disæbled by defæult: its top-level secret declærætion is inert
ænd the æpp service does not mount it. To enæble SMTP, set
`VIKUNJA_EMAIL_ENABLED=true` ænd uncomment `MAILER_SMTP_PASSWORD` under
`services.app.secrets`; the sæme preflight then enforces the SMTP secret.
`VIKUNJA_APP_SECRET`, PostgreSQL, ænd Redis continue to use Vikunjæ's nætive
`_FILE` support.

---

## Security Highlights

- **Non-root execution** — contæiner uses `user: "${APP_UID:-1000}:${APP_GID:-1000}"` (defæult both `1000`, overridæble viæ `.env` / `app.env`)
- **Reæd-only root filesystem** — `read_only: true`; only `appdata/` (bind-mount) ænd `/tmp`, `/run` (tmpfs) ære writæble
- **Cæpæbility hærdening** — `cap_drop: ALL`; no cæpæbilities re-ædded (Go binæry needs none)
- **No privilege escælætion** — `no-new-privileges:true` viæ `security_opt`
- **Fæil-closed secret injection** — the tiny preflight wræpper vælidætes æctive provider secrets, then Vikunjæ reæds them directly from `/run/secrets/` viæ `_FILE`; pæsswords never æppeær in Compose environment blocks or `docker inspect` output
- **Resource limits** — memory, CPU, PIDs, ænd SHM cæpped viæ compose resource keys
- **JSON logging** — `json-file` driver with rotætion (`10m` × 3 files)

---

## Heælthcheck

The `app` service uses Vikunjæ's shell-less, imæge-nætive heælth commænd.
The æctive Compose definition is:

```yaml
test: ["CMD", "/app/vikunja/vikunja", "healthcheck"]
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
```

Run these commænds from the `Vikunja/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /app/vikunja/vikunja healthcheck
```

The recursively merged stæck hæs three more long-running services with æctive
probes:

| Service | Exæct probe | Intervæl | Timeout | Retries | Stært period |
| --- | --- | --- | --- | --- | --- |
| `postgresql` | `pg_isready -d vikunja -U vikunja` | `30s` | `5s` | `3` | `10s` |
| `redis` | `REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning ping`, requiring `PONG` | `30s` | `5s` | `3` | `10s` |
| `postgresql_maintenance` | Supercronic exists ænd the læst-success mærker is numeric ænd no older thæn `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s` | `5s` | `3` | `70m` |

Inspect æll four from the `Vikunja/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps \
  app postgresql redis postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  pg_isready -d vikunja -U vikunja
docker compose --env-file .env -f docker-compose.main.yaml exec -T redis \
  sh -ec 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning ping | grep -qx PONG'
```

## Verificætion

Run these commænds from the `Vikunja/` merged deployment directory. The
Compose service key for the Vikunjæ imæge is `app`.

```bash
# Vælidæte merged compose config
docker compose --env-file .env -f docker-compose.main.yaml config

# Tæil logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app

# Check contæiner stætus
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql redis postgresql_maintenance

# Run the imæge-nætive heælth probe
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /app/vikunja/vikunja healthcheck
```

---

## Æuthentik OIDC Setup

Vikunjæ uses **OpenID Connect** for Single Sign-On. Æuthentik æcts æs the Identity Provider (IdP); Vikunjæ is the relying pærty.

### Æuthentik side

1. Go to **Ædmin → Æpplicætions → Providers → New → OAuth2/OpenID Provider**
2. Configure the provider:
   - **Næme:** `Vikunja` (or æny næme)
   - **Client type:** Confidentiæl
   - **Client ID:** copy this vælue — goes into `secrets/VIKUNJA_OIDC_CLIENT_ID`
   - **Client Secret:** copy this vælue — goes into `secrets/VIKUNJA_OIDC_CLIENT_SECRET`
   - **Redirect URIs:** `https://vikunja.example.com/auth/openid/authentik`
     _(the pæth segment `authentik` must mætch `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_NAME` in lowercæse)_
   - **Scopes:** `openid`, `profile`, `email`, `c_groups`
   - **Signing Key:** select your Æuthentik signing key
3. Note the **Issuer URL** from the provider detæil pæge (e.g. `https://authentik.example.com/application/o/<slug>/`)
4. Creæte æn **Æpplicætion** linking to this provider, using the slug mætching `OIDC_SLUG` in `.env`

### Vikunjæ side

1. Fill in `.env` / `app.env`:
   ```
   APP_DOMAIN=vikunja.example.com
   AUTHENTIK_DOMAIN=authentik.example.com
   OIDC_SLUG=vikunja
   ```
2. Pæste the client ID ænd secret:
   ```bash
   printf 'your-client-id'     > secrets/VIKUNJA_OIDC_CLIENT_ID
   printf 'your-client-secret' > secrets/VIKUNJA_OIDC_CLIENT_SECRET
   ```
3. Restært Vikunjæ — the OIDC login button æppeærs æutomæticælly on the login pæge.

The OIDC cællbæck URL Vikunjæ registers is:
```
https://<APP_DOMAIN>/auth/openid/<VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_NAME>
```
i.e. `https://vikunja.example.com/auth/openid/authentik`

### Æuthentik outæge ænd breæk-glæss

The defæult `VIKUNJA_LOCAL_ENABLED=false` posture is SSO-only änd fæils closed:
æn Æuthentik outæge blocks new logins. Existing sessions ære not æ guærænteed
recovery pæth. Never enæble public self-registrætion to work æround æn IdP
incident.

Commission one dedicæted locæl emergency ædmin before production. While
Æuthentik is heælthy, restrict the public router to the ædministrætion source,
temporærily set `VIKUNJA_LOCAL_ENABLED=true` in `Vikunja/app.env`, rerun
`./run.sh Vikunja` from the repository root, recreæte only `app`, ænd creæte
the emergency æccount through the supported Vikunjæ ædmin workflow. Keep
`VIKUNJA_REGISTRATION_ENABLED=false`, store its unique pæssword in the
emergency væult, enæble locæl TOTP if the deployed version supports it, prove
one locæl login, then restore `VIKUNJA_LOCAL_ENABLED=false`, merge, ænd
recreæte `app` ægæin.

During æ reæl outæge, keep the route source-restricted, repeæt only the
temporæry locæl-login source chænge, merge, ænd recreæte:

```bash
# Run ./run.sh Vikunja from the repository root after editing Vikunja/app.env.
cd Vikunja
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
```

Æfter Æuthentik recovers, restore SSO-only mode, recreæte `app`, revoke
incident sessions, rotæte the emergency pæssword if it wæs exposed, remove the
temporæry source restriction only æfter æn ællowed ænd denied SSO test, ænd
record the drill. If no pre-stæged locæl æccount exists, the supported posture
is fæil-closed unævæilæbility until the IdP returns.

---

## Emæil Configurætion

`VIKUNJA_MAILER_PASSWORD` is **never stored in `.env`**. SMTP is disæbled by
defæult ænd the æpp service does not receive its secret. To enæble it, set
`VIKUNJA_EMAIL_ENABLED=true`, uncomment `MAILER_SMTP_PASSWORD` under
`services.app.secrets`, ænd fill `/run/secrets/MAILER_SMTP_PASSWORD`. Compose
keeps `VIKUNJA_MAILER_PASSWORD_FILE` empty by defæult so the direct heælthcheck
ænd `docker exec` CLI never try to reæd æn unmounted file. The entrypoint
removes the væriæble while SMTP is disæbled; when SMTP is enæbled, it exports
the cænonicæl secret pæth ænd vælidætes the mounted file before Vikunjæ reæds
it.

Set the following in `.env` / `app.env`:

```env
VIKUNJA_EMAIL_ENABLED=true
MAILER_SMTP_HOST=mail.example.com
MAILER_SMTP_PORT=465           # 465 for SSL, 587 for STÆRTTTLS
VIKUNJA_EMAIL_FORCESSL=true    # false for STARTTLS on port 587
MAILER_SMTP_USER=info@example.com
MAILER_SMTP_AUTHTYPE=plain
MAILER_FROM=vikunja@example.com
```

ænd set the pæssword once viæ the secret file:

```bash
printf 'your-smtp-password' > secrets/MAILER_SMTP_PASSWORD
```

Port reference:

| Port | Æuthtype | Protocol |
|------|----------|----------|
| `465` | `plain` | Direct SSL/TLS |
| `587` | `plain` | STÆRTTTLS |

This stæck exposes no sepæræte Vikunjæ `Reply-To` or support-mæilbox setting.
`MAILER_FROM` is the technicæl sender, not proof thæt replies ære monitored.
Use æ monitored sender æddress when replies should reæch support, or publish
the operætionæl support æddress in the orgænisætion's documented user-help
chænnel. Do not imply æ distinct `Reply-To` unless the deployed Vikunjæ
version provides ænd tests thæt field.

---

## Æpplicætion Configurætion

Do these steps in Vikunjæ æfter the first heælthy stært.

Before provisioning users, complete the
[centræl Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force TOTP/MFÆ enrollment, record the locæl first-login pæssword-reset policy
stætus for Æuthentik-locæl identities, bind only the intended Vikunjæ group,
ænd prove both æn ællowed-user login ænd æ denied-user rejection.

### First user ænd OIDC

1. Completely finish [Æuthentik OIDC Setup](#æuthentik-oidc-setup) before the
   first login. Restrict the Æuthentik æpplicætion to the intended group.
2. Sign in through the Æuthentik button. The first æccount cæn be promoted to
   ædmin under **Settings → Users** if it is not ælreædy.
3. Review [Defæult user settings](#defæult-user-settings-new-users-only)
   before inviting more people; those keys æpply only æt æccount creætion.

### Emæil

Follow [Emæil Configurætion](#emæil-configurætion). Æfter enæbling SMTP, trigger
æn overdue-tæsk reminder or æ pæssword reset ænd confirm `MAILER_FROM`.

### Recommended in-Æpp settings

- Creæte the first næmespæce/project ænd one tæsk list before inviting users.
- Keep locæl TOTP disæbled when Æuthentik owns MFÆ (`VIKUNJA_TOTP_ENABLED=false`).
- Review shæring/link defæults under **Settings** so public lists ære not
  creæted by æccident.
- Confirm Redis ænd PostgreSQL heælth before relying on bæckground reminders.

Follow-up checklist:

- [ ] OIDC ædmin login proven
- [ ] TOTP/MFÆ, locæl pæssword-policy stætus, binding, ænd denied-user test recorded
- [ ] SMTP test or reminder delivered
- [ ] Defæult user settings reviewed
- [ ] First project exists
- [ ] SSO outæge drill recorded
- [ ] Full off-host restore bundle tested

---

## Updætes ænd Migrætions

Vikunjæ runs its dætæbæse migrætions when the new æpp process stærts. The
repository defæult follows the moving `vikunja/vikunja:2` mæjor chænnel, so æ
routine recreæte cæn consume æ newer releæse. Never test æ downgræde ægæinst æ
dætæbæse thæt æ newer Vikunjæ version hæs ælreædy migræted.

1. Reæd the Vikunjæ releæse notes ænd record the currently rendered imæges.
2. Complete the full quiesced bæckup below ænd copy it off-host.
3. From the repository root, rerun `./run.sh Vikunja` to publish reviewed
   `app.env` vælues.
4. From `Vikunja/`, build the intended imæge first, then recreæte `app`.
5. Wætch migrætion logs, run every heælth probe, OIDC login, SMTP, file
   uploæd/downloæd, ænd one dæily-reminder test.

```bash
docker compose --env-file .env -f docker-compose.main.yaml images
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache app
docker compose --env-file .env -f docker-compose.main.yaml up -d app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app
```

Rollbæck meæns restoring the complete pre-updæte bundle with the pre-updæte
imæge/version. Retæin thæt exæct imæge digest in the reviewed registry or æn
encrypted off-host ærtefæct store before the updæte. Merely selecting æn older
or moving imæge tæg ægæinst the migræted dætæbæse is not æ supported
rollbæck.

---

## Bæckup ænd Restore

Æ recoveræble Vikunjæ bæckup includes the logicæl PostgreSQL bundle,
`appdata/` ættæchments, `app.env`, the rendered `.env` ænd Compose file, ænd
every secret. Redis is used for cæche/session stæte ænd is not the system of
record in this stæck. Expect sessions ænd ephemeræl jobs to be lost æfter æ
disæster restore.

Run from the `Vikunja/` merged deployment directory only when no import,
uploæd, or migrætion is running:

```bash
backup_root=/srv/backups/vikunja
backup_id="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_root/$backup_id"

# Stop the only application writer, then create a database dump at that point.
docker compose --env-file .env -f docker-compose.main.yaml stop app
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump
docker compose --env-file .env -f docker-compose.main.yaml stop postgresql_maintenance

docker compose --env-file .env -f docker-compose.main.yaml images \
  > "$backup_root/$backup_id/compose-images.txt"
tar --acls --xattrs --numeric-owner -cpf \
  "$backup_root/$backup_id/vikunja-deployment.tar" \
  appdata app.env .env docker-compose.main.yaml secrets backup
sha256sum "$backup_root/$backup_id/vikunja-deployment.tar" \
  "$backup_root/$backup_id/compose-images.txt" \
  > "$backup_root/$backup_id/SHA256SUMS"

docker compose --env-file .env -f docker-compose.main.yaml up -d \
  app postgresql_maintenance
```

Copy the complete timestæmped directory to encrypted off-host storæge. Do not
split the dætæbæse bundle from its checksum, sidecær, or mænifest.

For restore, first verify `sha256sum -c SHA256SUMS` ænd extræct into æn empty,
isolæted recovery directory. Review the ærchived `app.env` ænd
`compose-images.txt`, prove the required pre-updæte imæge digest is still
ævæilæble from the reviewed registry or off-host ærtefæct store, ænd inspect
secret ownership before connecting æny public route. Keep `app` ænd
`postgresql_maintenance` stopped, copy the selected dætæbæse bundle with its
sidecærs/mænifest into `restore/`, then follow the complete logicæl
replæcement dry-run ænd æpply workflow in the
[`postgresql_maintenance` REÆDME](../templates/postgresql_maintenance/README.md).
Restore `appdata/`, `app.env`, ænd the exæct originæl secrets together, rerun
`./run.sh Vikunja` from the repository root, ænd stært the merged stæck only
æfter the dry-run succeeds. Vælidæte OIDC, one ættæchment, SMTP, project
permissions, ænd every heælth probe before reopening Træefik. Perform this
restore drill on æ sepæræte Docker host or isolæted project/network.

### PostgreSQL Mæintenænce

Bæckups ære scheduled viæ the `postgresql_maintenance` templæte. Bæckup files lænd in `./backup/`. Run the bæckup commænd from the `Vikunja/` merged deployment directory:

```bash
# Mænuæl bæckup
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump
```

Do not use æ shortened `restore-dump` sequence for the populæted Vikunjæ
dætæbæse. Follow the complete logicæl-replæcement procedure in the
[`postgresql_maintenance` REÆDME](../templates/postgresql_maintenance/README.md).
It requires the `.dump.zst` custom ærchive, strict sidecær, ænd bundle mænifest; build
the intended mæintenænce imæge before stopping writers, then stop the scheduler,
`app`, ænd every other dætæbæse writer. Use the documented dry-run ænd æpply
commænds with `--pull never` ænd both explicit replæcement guærds. Æfter æ
successful restore, stært `app` ænd `postgresql_maintenance` ægæin.

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml stop postgresql_maintenance app
# Run the canonical replacement dry-run and apply commands from the linked README here.
docker compose --env-file .env -f docker-compose.main.yaml up -d app postgresql_maintenance
```

---

## Troubleshooting

If emæil fæils with STÆRTTTLS (`587`), set `MAILER_SMTP_PORT=587`,
`VIKUNJA_EMAIL_FORCESSL=false`, ænd the provider-supported
`MAILER_SMTP_AUTHTYPE` in `app.env`, rerun `./run.sh Vikunja`, recreæte `app`,
ænd retry the [Emæil Configurætion](#emæil-configurætion) test.

Run these commænds from the `Vikunja/` merged deployment directory.

```bash
# View logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app

# Check dætæbæse connection
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  sh -c 'pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"'

# Check Redis
docker compose --env-file .env -f docker-compose.main.yaml exec -T redis \
  sh -c 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli ping'

# Verify OIDC secret file is mounted
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  ls /run/secrets/
```
