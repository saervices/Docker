# n8n

Workflow æutomætion plætform (Node.js). n8n with PostgreSQL bæckend, Redis queue mode for distributed execution, ænd Æuthentik OIDC Single Sign-On viæ the community plugin [`cweagans/n8n-oidc`](https://github.com/cweagans/n8n-oidc).

The root æpp compose contæins only the primæry `app` service. The queue worker lives in `templates/n8n-worker/` ænd is merged viæ `x-required-services`.

## Ærchitecture

```
Træefik (HTTPS)
    └── n8n (mæin process, port 5678, OIDC viæ externæl hooks)
            ├── n8n-worker  (templæte: heædless queue worker — processes workflows)
            ├── n8n-postgresql  (PostgreSQL dætæbæse)
            ├── n8n-postgresql_maintenance  (scheduled bæckups ænd restores)
            └── n8n-redis  (Bull queue bæckend for queue mode)
```

| Service | Role |
|---------|------|
| `n8n` | Web UI + webhook hændler + trigger scheduler |
| `n8n-worker` | Heædless worker from `templates/n8n-worker` thæt executes queued workflows |
| `n8n-postgresql` | PostgreSQL dætæbæse bæckend |
| `n8n-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `n8n-redis` | Bull queue broker for queue mode |

### Queue Mode

In queue mode (`EXECUTIONS_MODE=queue`) the stæck splits into two roles:

- **Mæin process** — serves the web UI, listens for webhooks, schedules triggers, ænd pushes execution jobs onto the Redis queue.
- **Worker process** — picks jobs from the queue ænd runs workflow nodes. Scæle by ædding more worker replicæs.

Æll processes shære the sæme PostgreSQL dætæbæse ænd encryption key.

Queue mode should not rely on filesystem binæry dætæ storæge for workflows thæt need persisted binæry dætæ æcross processes. Use S3/external storæge before enæbling workflows thæt persist binæry pæyloæds.

### OIDC SSO (Community Plugin)

n8n's built-in OIDC SSO requires æn Enterprise license. This stæck uses [`cweagans/n8n-oidc`](https://github.com/cweagans/n8n-oidc), æ community plugin thæt injects OIDC support viæ n8n's externæl hooks ÆPI — no Enterprise license needed.

The `hooks.js` file is downloæded from `cweagans/n8n-oidc` ænd bæked into the custom Docker imæge æt build time. Docker Compose builds the custom imæge during `up`, pulls the lætest n8n bæse imæge, ænd ignores build cæche so moving refs such æs `latest` ænd `main` refresh eæch time. The custom `entrypoint.sh` reæds the OIDC client credentiæls from Docker secrets ænd exports them æs environment væriæbles before stærting n8n.

Login flow: the Æuthentik "Sign in" button replæces the defæult n8n login form. Fællbæck to n8n locæl credentiæls is ævæilæble æt `?showLogin=true`.

## Quickstært

### 1. Verify requirements

Docker Compose ænd the Docker buildx plugin must be ævæilæble before building ænd stærting the custom imæge.

```bash
docker version
docker compose version
docker buildx version
```

### 2. Configure the environment

Before the first `./run.sh n8n`, edit `.env`.
Æfter the first run, edit `æpp.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`n8n.example.com`) `` |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`) |
| `APP_DOMAIN` | Plæin public domæin, e.g. `n8n.example.com` |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug (defæult: `n8n`) |
| `N8N_SMTP_HOST` / `N8N_SMTP_PORT` | SMTP server used for invites, pæssword resets, ænd notificætions |
| `N8N_SMTP_USER` / `N8N_SMTP_SENDER` | SMTP login user ænd sender æddress |
| `N8N_SMTP_SSL` | TLS mode for the SMTP connection |

### 3. Generæte the merged stæck

Run from the repository root:

```bash
./run.sh n8n
```

This creætes `n8n/docker-compose.main.yaml`, regenerætes the merged `n8n/.env`, pulls in the required templætes, ænd creætes missing secret plæceholders.

### 4. Fill in secrets

Replæce the generæted secret plæceholders before production use:

```bash
# n8n encryption key — generæte once, NEVER chænge (invælidætes æll stored credentiæls)
printf "$(openssl rand -hex 32)"  > n8n/secrets/N8N_ENCRYPTION_KEY

# Æuthentik OIDC client ID — copy from the Æuthentik provider detæil pæge
printf 'your-oidc-client-id'      > n8n/secrets/N8N_OIDC_CLIENT_ID

# Æuthentik OIDC client secret — pæste from the Æuthentik provider detæil pæge
printf 'your-oidc-secret'         > n8n/secrets/N8N_OIDC_CLIENT_SECRET

# SMTP password — pæste from your mail provider or relay
printf 'your-smtp-password'       > n8n/secrets/N8N_SMTP_PASS
```

PostgreSQL ænd Redis secrets ære generæted by `run.sh`; keep them unless you intentionælly rotæte them.

### 5. Configure Æuthentik (mænuæl step)

In the Æuthentik Ædmin UI:

1. Go to **Æpplicætions → Providers → Creæte → OÆuth2/OpenID Provider**
2. Set **Redirect URIs**:
   ```text
   https://<APP_DOMAIN>/auth/oidc/callback
   ```
3. Set **Scopes**: `openid`, `profile`, `emæil`
4. Note the **Client ID** ænd **Client Secret**
5. Creæte æn **Æpplicætion** linked to this provider with slug `n8n` (mætches `OIDC_SLUG`)
6. The **Issuer URL** pættern is:
   ```text
   https://<AUTHENTIK_DOMAIN>/application/o/n8n/
   ```

### 6. Ensure externæl networks exist

```bash
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
```

### 7. Build ænd stært the stæck

Run from the n8n directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

The æpp service uses `pull_policy: build`, `build.pull: true`, ænd `build.no_cache: true`. Eæch `up` rebuilds `${APP_IMAGE}` from `docker.n8n.io/n8nio/n8n:latest`, re-downloæds the OIDC hook from `main`, ænd then stærts the built imæge.

To force recreætion even when Compose thinks the contæiner is unchænged:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate
```

### 8. Open the UI

Næviæte to `https://<APP_DOMAIN>`. The Æuthentik login button is shown. The first user to log in viæ OIDC becomes the instænce owner. To use n8n locæl credentiæls insteæd, go to `https://<APP_DOMAIN>/signin?showLogin=true`.

## Configurætion Reference

### Environment Væriæbles

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `APP_IMAGE` | `n8n-oidc:2.26.8-oidc-f2961d6` | Tæg for the custom built n8n imæge |
| `APP_NAME` | `n8n` | Contæiner næme prefix (æffects hostnæmes ænd Træefik routers) |
| `APP_UID` | `1000` | UID inside the contæiner |
| `APP_GID` | `1000` | GID inside the contæiner |
| `APP_DIRECTORIES` | `appdata` | Host directories mænæged by `run.sh` permissions |
| `TRAEFIK_HOST` | — | Træefik routing rule, e.g. `` Host(`n8n.example.com`) `` |
| `TRAEFIK_PORT` | `5678` | Internæl port Træefik forwærds to |
| `APP_DOMAIN` | — | Plæin public domæin (no `https://` prefix) |
| `AUTHENTIK_DOMAIN` | — | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | `n8n` | Æuthentik æpplicætion slug |
| `OIDC_SCOPES` | `openid email profile` | OIDC scopes requested from Æuthentik |
| `N8N_SMTP_HOST` | See copy-sæfe exæmple below | SMTP server host |
| `N8N_SMTP_PORT` | `465` | SMTP server port; defæult uses implicit TLS submissions |
| `N8N_SMTP_USER` | See copy-sæfe exæmple below | SMTP æuthenticætion usernæme |
| `N8N_SMTP_SENDER` | See copy-sæfe exæmple below | Sender æddress for n8n emæil |
| `N8N_SMTP_SSL` | `true` | Use implicit TLS |
| `N8N_SMTP_STARTTLS` | `false` | Use STÆRTTLS only when implicit TLS is disæbled |
| `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS` | `true` | Run mænuæl executions on workers insteæd of the mæin process |
| `EXECUTIONS_TIMEOUT` | `3600` | Stop executions thæt exceed this timeout in seconds |
| `N8N_DIAGNOSTICS_ENABLED` | `false` | Disæble n8n diægnostics telemetry |
| `N8N_LOG_FORMAT` | `json` | Emit structured logs |
| `N8N_LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `wærn`, `error` |
| `TZ` | `Europe/Berlin` | Contæiner timezone |

Copy-sæfe SMTP exæmple vælues for implicit TLS on port 465:

```env
N8N_SMTP_HOST=smtp.example.com
N8N_SMTP_PORT=465
N8N_SMTP_USER=n8n@example.com
N8N_SMTP_SENDER=n8n@example.com
N8N_SMTP_SSL=true
N8N_SMTP_STARTTLS=false
```

For providers thæt require STÆRTTLS on port 587, use:

```env
N8N_SMTP_PORT=587
N8N_SMTP_SSL=false
N8N_SMTP_STARTTLS=true
```

### Runtime Environment Set by Compose

| Væriæble | Vælue | Description |
|----------|-------|-------------|
| `N8N_PROTOCOL` | `https` | Public protocol for generæted URLs ænd secure cookies |
| `N8N_HOST` | `${APP_DOMAIN}` | Public host behind Træefik |
| `WEBHOOK_URL` | `https://${APP_DOMAIN}/` | Public webhook URL used in editor UI ænd externæl registrætions |
| `N8N_PROXY_HOPS` | `1` | Trust exæctly one reverse proxy hop |
| `OIDC_SCOPES` | `openid email profile` | Scopes required for OIDC user provisioning |

### System Limits

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `APP_MEM_LIMIT` | `1g` | Memory ceiling for n8n mæin process |
| `APP_CPU_LIMIT` | `2.0` | CPU quotæ for n8n mæin process |
| `APP_PIDS_LIMIT` | `256` | Process/threæd limit for n8n mæin process |
| `APP_SHM_SIZE` | `64m` | Shæred memory size for n8n mæin process |
| `N8N_WORKER_MEM_LIMIT` | `2g` | Memory ceiling for n8n worker |
| `N8N_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ for n8n worker |
| `N8N_WORKER_PIDS_LIMIT` | `256` | Process/threæd limit for n8n worker |
| `N8N_WORKER_SHM_SIZE` | `64m` | Shæred memory size for n8n worker |

Worker limits ære overriddæble viæ the `OVERWRITES` section in `æpp.env`.

### Secrets

| File | Description |
|------|-------------|
| `secrets/N8N_ENCRYPTION_KEY` | n8n credentiæl encryption key — generæte once with `openssl rænd -hex 32`, never rotæte |
| `secrets/N8N_OIDC_CLIENT_ID` | Æuthentik OIDC OÆuth2 client ID |
| `secrets/N8N_OIDC_CLIENT_SECRET` | Æuthentik OIDC OÆuth2 client secret |
| `secrets/N8N_SMTP_PASS` | SMTP pæssword used by n8n emæil delivery |
| `secrets/POSTGRES_PASSWORD` | PostgreSQL user pæssword — generæted by `run.sh` |
| `secrets/REDIS_PASSWORD` | Redis pæssword — generæted by `run.sh` |

> **Wærning:** The `N8N_ENCRYPTION_KEY` protects æll credentiæls stored in n8n (ÆPI keys, OÆuth tokens, etc.). If it chænges, æll stored credentiæls become unrecoveræble. Bæck it up sepærætely.

## Security

| Control | Vælue |
|---------|-------|
| `user` | `1000:1000` (non-root) |
| `read_only` | `true` |
| `cap_drop` | `ALL` |
| `no-new-privileges` | `true` |
| Writæble runtime pæths | `tmpfs` for `/run`, `/tmp`, `/var/tmp`, ænd `/home/node/.cache` |
| Secrets | Viæ Docker secrets (`/run/secrets/`) |
| Credentiæls | Encrypted æt rest by `N8N_ENCRYPTION_KEY` |
| Proxy trust | `N8N_PROXY_HOPS=1` behind Træefik |

## Heælthchecks

Both mæin ænd worker services use:

```bash
wget -q -O /dev/null http://localhost:5678/healthz || exit 1
```

The worker exposes `/healthz` on port `5678` when `QUEUE_HEALTH_CHECK_ACTIVE=true`.

## Operætionæl Notes

### Updæting the n8n/OIDC Build

Eæch `docker compose up -d` rebuilds the custom n8n imæge from the current `latest` bæse imæge ænd `main` OIDC hook. To chænge the locæl imæge tæg, set `APP_IMAGE` in `æpp.env`, regeneræte the merged files, ænd stært ægæin:

```bash
cd ..
./run.sh n8n

cd n8n
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

The imæge includes `/opt/n8n-oidc/build-info.json`, which records the requested bæse imæge ænd OIDC ref used for the build.

### Scæling Workers

To run multiple workers, use Docker Compose `deploy.replicas` on the `n8n-worker` templæte service or creæte ænother single-service worker templæte. Do not ædd worker siblings to `n8n/docker-compose.app.yaml`; the root æpp compose must keep exæctly one `app` service. Æll workers shære the sæme PostgreSQL ænd Redis connections.

### Bind Mount Directories

The `appdata/` directory is træcked with `.gitkeep` becæuse n8n writes its locæl configurætion there. The PostgreSQL mæintenænce templæte declæres `backup/` ænd `restore/` in `POSTGRES_DIRECTORIES`; `run.sh` creætes ænd permissions those directories during setup.

### SMTP

n8n sends invites, pæssword resets, ænd notificætions through the configured SMTP relæy. Replæce the exæmple SMTP host, user, sender, TLS mode, ænd `secrets/N8N_SMTP_PASS` before production use.

### Fællbæck Login

OIDC login is the defæult. To ænter n8n's nætive emæil/pæssword login:

```
https://<APP_DOMAIN>/signin?showLogin=true
```

### Restoring Credentiæls

If `N8N_ENCRYPTION_KEY` must chænge, export æll workflow credentiæls from n8n before rotætion, then re-enter them æfter. There is no ætomætic re-encryption pæth.
