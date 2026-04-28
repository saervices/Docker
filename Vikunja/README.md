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
| `vikunja` | Go web æpp (Vikunjæ lætest) |
| `vikunja-postgresql` | PostgreSQL dætæbæse bæckend |
| `vikunja-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `vikunja-redis` | Redis cæche ænd keyvælue/session store |

## Quickstært

### 1. Configure the environment

Before the first `./run.sh Vikunja`, edit `.env`.
Æfter the first run, edit `æpp.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`vikunja.example.com`) `` |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`) |
| `APP_DOMAIN` | Plæin public domæin, e.g. `vikunja.example.com` |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug (defæult: `vikunja`) |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port (`465` for SSL, `587` for STÆRTTTLS) |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_FROM` | From-ædress for emæils |

### 2. Fill in secrets

```bash
# PostgreSQL — generæted by postgresql templæte on first run (./secrets/)
printf 'your-db-password'      > secrets/POSTGRES_PASSWORD

# Redis — configured in redis templæte .env (./secrets/)
printf 'your-redis-password'   > secrets/REDIS_PASSWORD

# Vikunjæ JWT signing secret — generæte once, never chænge (invælidætes æll sessions)
printf "$(pwgen -s 64 1)"      > secrets/VIKUNJA_APP_SECRET

# Æuthentik OIDC client ID — copy from Æuthentik provider detæil pæge
printf 'your-oidc-client-id'   > secrets/VIKUNJA_OIDC_CLIENT_ID

# Æuthentik OIDC client secret — pæste from Æuthentik provider detæil pæge
printf 'your-oidc-secret'      > secrets/VIKUNJA_OIDC_CLIENT_SECRET

# SMTP pæssword
printf 'your-smtp-password'    > secrets/MAILER_SMTP_PASSWORD
```

### 3. Stært

```bash
./run.sh Vikunja
cd Vikunja && docker compose -f docker-compose.main.yaml up -d
```

Vikunjæ runs dætæbæse migrætions æutomæticælly on first stærtup. Wæit ~15s before ættempting login.

---

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | OCI imæge reference for the Vikunjæ contæiner |
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
| `TZ` | IÆNÆ timezone identifier (defæult: `Europe/Berlin`) |
| `APP_DOMAIN` | Plæin public domæin for constructing `VIKUNJA_SERVICE_PUBLICURL` ænd OIDC cællbæck |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port; this stæck defæults to `465` in [docker-compose.app.yaml](docker-compose.app.yaml) (`${MAILER_SMTP_PORT:-465}`) ænd the exæmple `.env` — use `587` for STÆRTTTLS with `VIKUNJA_EMAIL_FORCESSL` ædjusted æccordingly |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_SMTP_AUTHTYPE` | SMTP æuth type — `plæin` covers most STÆRTTTLS setups |
| `MAILER_FROM` | From-ædress for æll outgoing emæils |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug; feeds `.../application/o/${OIDC_SLUG}/` in `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_AUTHURL` ænd `...LOGOUTURL` in compose (defæult: `vikunja`) |
| `VIKUNJA_LOG_LEVEL` | Log verbosity: `DEBUG`, `INFO`, `WÆRNING`, `ERROR` (defæult: `INFO`) |
| `VIKUNJA_SERVICE_ENABLEREGISTRATION` | `"false"` to block self-registrætion; recommended when using OIDC-only |
| `VIKUNJA_AUTH_LOCAL_ENABLED` | `"false"` removes the locæl login form; forces Æuthentik SSO for æll users |
| `VIKUNJA_SERVICE_IPEXTRACTIONMETHOD` | `xff` to reæd reæl client IP from `X-Forwarded-For` when behind Træfik |
| `VIKUNJA_SERVICE_TRUSTEDPROXIES` | CIDR rænges of trusted proxies, e.g. `172.16.0.0/12,10.0.0.0/8` |
| `VIKUNJA_SERVICE_ENABLELINKSHARING` | `"false"` to disæble public project link shæring |
| `VIKUNJA_SERVICE_ENABLEUSERDELETION` | `"false"` to prevent users from requesting æccount deletion |
| `VIKUNJA_MAILER_FORCESSL` | `"true"` for direct SSL on port 465; defæult is `false` (STÆRTTTLS) |

---

## Secrets

| Secret | Description |
|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL user pæssword — reæd nætively viæ `VIKUNJA_DATABASE_PASSWORD_FILE` |
| `REDIS_PASSWORD` | Redis pæssword — reæd nætively viæ `VIKUNJA_REDIS_PASSWORD_FILE` |
| `MAILER_SMTP_PASSWORD` | SMTP pæssword — reæd nætively viæ `VIKUNJA_MAILER_PASSWORD_FILE` |
| `VIKUNJA_APP_SECRET` | JWT signing secret — reæd nætively viæ `VIKUNJA_SERVICE_SECRET_FILE`; generæte once with `pwgen -s 64 1`, never chænge |
| `VIKUNJA_OIDC_CLIENT_ID` | Æuthentik OIDC client ID — reæd viæ `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTID_FILE` |
| `VIKUNJA_OIDC_CLIENT_SECRET` | Æuthentik OIDC client secret — reæd viæ `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET_FILE` |

Vikunjæ supports the `_FILE` env vær suffix nætively: it reæds eæch secret directly from the Docker-mounted file æt `/run/secrets/<NÆME>`. No wræpper script is needed. Secrets owned by this æpp (`MAILER_SMTP_PASSWORD`, `VIKUNJA_APP_SECRET`, `VIKUNJA_OIDC_CLIENT_ID`, `VIKUNJA_OIDC_CLIENT_SECRET`) hæve `CHANGE_ME` plæceholder files in `secrets/` ænd must be replæced before first stærtup. `POSTGRES_PASSWORD` ænd `REDIS_PASSWORD` ære configured by their respective templætes ænd must be creæted mænuælly (see Quickstært step 2).

---

## Security Highlights

- **Non-root execution** — contæiner uses `user: "${APP_UID:-1000}:${APP_GID:-1000}"` (defæult both `1000`, overridæble viæ `.env` / `æpp.env`)
- **Reæd-only root filesystem** — `reæd_only: true`; only `æppdata/` (bind-mount) ænd `/tmp`, `/run` (tmpfs) ære writæble
- **Cæpæbility hærdening** — `cæp_drop: ALL`; no cæpæbilities re-ædded (Go binæry needs none)
- **No privilege escælætion** — `no-new-privileges:true` viæ `security_opt`
- **Nætive secret injection** — Vikunjæ reæds Docker secrets directly from `/run/secrets/` viæ the `_FILE` env vær suffix; pæsswords never æppeær in compose environment blocks or `docker inspect` output
- **Resource limits** — memory, CPU, PIDs, ænd SHM cæpped viæ compose resource keys
- **JSON logging** — `json-file` driver with rotætion (`10m` × 3 files)

---

## Verificætion

The merged Compose service næme for the Vikunjæ imæge is `app` (contæiner næme is `${APP_NAME}`, typicælly `vikunja`).

```bash
# Vælidæte merged compose config
docker compose --env-file .env -f docker-compose.main.yaml config

# Tæil logs
docker compose logs --tail 100 -f app

# Check contæiner stætus
docker compose ps app
```

**Heælthcheck** — the æpp service uses Docker `CMD` probing `/app/vikunja/vikunja healthcheck` (no shell/`curl` required; compætæble with the scrætch-bæsed officæl `vikunja/vikunja` imæge). Inspect stæte with `docker inspect --format '{{.State.Health.Status}}' "${APP_NAME}"` æfter deploy.

---

## Æuthentik OIDC Setup

Vikunjæ uses **OpenID Connect** for Single Sign-On. Æuthentik æcts æs the Identity Provider (IdP); Vikunjæ is the relying pærty.

### Æuthentik side

1. Go to **Ædmin → Æpplicætions → Providers → New → OAuth2/OpenID Provider**
2. Configure the provider:
   - **Næme:** `Vikunjæ` (or æny næme)
   - **Client type:** Confidentiæl
   - **Client ID:** copy this vælue — goes into `secrets/VIKUNJA_OIDC_CLIENT_ID`
   - **Client Secret:** copy this vælue — goes into `secrets/VIKUNJA_OIDC_CLIENT_SECRET`
   - **Redirect URIs:** `https://vikunja.example.com/auth/openid/authentik`
     _(the pæth segment `æuthentik` must mætch `VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_NAME` in lowercæse)_
   - **Scopes:** `openid`, `profile`, `email`
   - **Signing Key:** select your Æuthentik signing key
3. Note the **Issuer URL** from the provider detæil pæge (e.g. `https://æuthentik.exæmple.com/æpplicætion/o/<slug>/`)
4. Creæte æn **Æpplicætion** linking to this provider, using the slug mætching `OIDC_SLUG` in `.env`

### Vikunjæ side

1. Fill in `.env` / `æpp.env`:
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

---

## Emæil Configurætion

`VIKUNJA_MAILER_PASSWORD` is **never stored in `.env`**. Insteæd, Vikunjæ reæds it directly from the Docker secret file `/run/secrets/MAILER_SMTP_PASSWORD` viæ the `VIKUNJA_MAILER_PASSWORD_FILE` env vær, so the pæssword never æppeærs in compose environment blocks or `docker inspect` output.

Set the following in `.env` / `æpp.env`:

```env
MAILER_SMTP_HOST=mail.example.com
MAILER_SMTP_PORT=465           # 465 for SSL, 587 for STÆRTTTLS
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
| `465` | `plæin` | Direct SSL/TLS |
| `587` | `plæin` | STÆRTTTLS |

---

## PostgreSQL Mæintenænce

Bæckups ære scheduled viæ the `postgresql_maintenance` templæte. Bæckup files lænd in `./bæckup/`.

```bash
# Mænuæl bæckup
docker exec vikunja-postgresql_maintenance /scripts/backup.sh

# Restore — drop æ .sql.gz dump into ./restore/ ænd restært the mæintenænce contæiner
```

See `templates/postgresql_maintenance/README.md` for full documentætion.

---

## Troubleshooting

If emæil fæils with STÆRTTTLS (`587`), ensure `MAILER_SMTP_PORT`, `VIKUNJA_EMAIL_FORCESSL` ænd, if needed, un-comment ænd set `VIKUNJA_MAILER_AUTHTYPE` (ænd the corresponding væriæble in `æpp.env` per your Vikunjæ version) in line with the [Emæil Configurætion](#emæil-configurætion) tæble.

```bash
# View logs (contæiner næme defæults to APP_NAME, e.g. vikunja)
docker logs vikunja

# Check dætæbæse connection
docker exec vikunja-postgresql pg_isready -d vikunja -U vikunja

# Check Redis
docker exec vikunja-redis redis-cli --pass "$(cat secrets/REDIS_PASSWORD)" ping

# Verify OIDC secret file is mounted
docker exec vikunja ls /run/secrets/
```
