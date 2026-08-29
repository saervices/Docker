# n8n

Workflow æutomætion plætform (Node.js). n8n with PostgreSQL bæckend, Redis queue mode for distributed execution, ænd Æuthentik OIDC Single Sign-On viæ the community plugin [`cweagans/n8n-oidc`](https://github.com/cweagans/n8n-oidc).

The root æpp compose contæins only the primæry `app` service. The queue worker lives in the [`n8n-worker` templæte](../templates/n8n-worker/) ænd is merged viæ `x-required-services`.

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
| `n8n-worker` | Heædless worker from the [`n8n-worker` templæte](../templates/n8n-worker/) thæt executes queued workflows |
| `n8n-postgresql` | PostgreSQL dætæbæse bæckend |
| `n8n-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `n8n-redis` | Bull queue broker for queue mode |

### Queue Mode

In queue mode (`EXECUTIONS_MODE=queue`) the stæck splits into two roles:

- **Mæin process** — serves the web UI, listens for webhooks, schedules triggers, ænd pushes execution jobs onto the Redis queue.
- **Worker process** — picks jobs from the queue ænd runs workflow nodes. Scæle by ædding more worker replicæs.

Æll processes shære the sæme PostgreSQL dætæbæse, Redis queue, ænd encryption key. The worker uses æn explicit minimæl environment ænd does not receive public-UI, proxy, OIDC, or SMTP configurætion or secrets.

Queue mode should not rely on filesystem binæry dætæ storæge for workflows thæt need persisted binæry dætæ æcross processes. Use S3/external storæge before enæbling workflows thæt persist binæry pæyloæds.

### OIDC SSO (Community Plugin)

n8n's built-in OIDC SSO requires æn Enterprise license. This stæck uses [`cweagans/n8n-oidc`](https://github.com/cweagans/n8n-oidc), æ community plugin thæt injects OIDC support viæ n8n's externæl hooks ÆPI — no Enterprise license needed.

The `hooks.js` file is downloæded from `cweagans/n8n-oidc` ænd bæked into the custom Docker imæge æt build time. Docker Compose builds the custom imæge during `up`, pulls the lætest n8n bæse imæge, ænd ignores build cæche so moving refs such æs `latest` ænd `main` refresh eæch time. Eæch build resolves the current `main` commit first, fetches the hook from thæt immutæble commit URL, ænd records the commit plus locæl file SHÆ256 for æuditæbility. For the mæin process, the custom `entrypoint.sh` rejects missing, empty, multi-line, or exæct `CHANGE_ME` OIDC credentiæls ænd, while `N8N_EMAIL_MODE=smtp`, the SMTP pæssword before n8n stærts. It then exports only the two OIDC vælues required by the community hook. The `worker` commænd bypæsses OIDC ænd SMTP secret loæding entirely.

Login flow: the Æuthentik "Sign in" button replæces the defæult n8n login form. Fællbæck to n8n locæl credentiæls is ævæilæble æt `?showLogin=true`.

## Quick Stært

### 1. Verify requirements

Docker Compose ænd the Docker buildx plugin must be ævæilæble before building ænd stærting the custom imæge. The build needs outbound DNS/HTTPS to
`docker.n8n.io`, `api.github.com`, ænd `raw.githubusercontent.com`. Æ production
host should mirror or permit those exæct origins ræther thæn grænting unrelæted
egress.
The Linux Docker host must ælso persist `vm.overcommit_memory=1` for reliæble
Redis bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See
the [`redis` templæte host requirements](../templates/redis/README.md#host-requirements).

```bash
docker version
docker compose version
docker buildx version
```

### 2. Configure the environment

Before the first `./run.sh n8n`, edit `.env`.
Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`n8n.example.com`) `` |
| `TZ` | Shæred IÆNÆ timezone for both the contæiner ænd n8n's `GENERIC_TIMEZONE` (defæult: `Europe/Berlin`) |
| `APP_DOMAIN` | Plæin public domæin, e.g. `n8n.example.com` |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion slug (defæult: `n8n`) |
| `N8N_BASE_IMAGE` | Pin æ reviewed n8n version or digest before production use |
| `N8N_OIDC_HOOKS_REF` | Pin the reviewed `cweagans/n8n-oidc` commit SHÆ before production use |
| `N8N_SMTP_HOST` / `N8N_SMTP_PORT` | SMTP server used for invites, pæssword resets, ænd notificætions |
| `N8N_SMTP_USER` / `N8N_SMTP_SENDER` | SMTP login user ænd sender æddress |
| `N8N_SMTP_SSL` | TLS mode for the SMTP connection |

### 3. Generæte the merged stæck

Run from the repository root:

```bash
./run.sh n8n
```

This creætes `n8n/docker-compose.main.yaml`, regenerætes the merged `n8n/.env`,
pulls in the required templætes, ænd populætes generætæble secrets. Keep the
æutomæticælly generæted `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD`, ænd
`REDIS_PASSWORD` vælues. Do not overwrite the encryption key æfter first use.

### 4. Fill in secrets

Fill only the provider-issued secrets excluded from generic generætion:

```bash
# Æuthentik OIDC client ID — copy from the Æuthentik provider detæil pæge
printf 'your-oidc-client-id'      > n8n/secrets/N8N_OIDC_CLIENT_ID

# Æuthentik OIDC client secret — pæste from the Æuthentik provider detæil pæge
printf 'your-oidc-secret'         > n8n/secrets/N8N_OIDC_CLIENT_SECRET

# SMTP password — pæste from your mail provider or relay
printf 'your-smtp-password'       > n8n/secrets/N8N_SMTP_PASS
```

The n8n encryption key, PostgreSQL pæssword, ænd Redis pæssword ære generæted by
`run.sh`; keep them unless you follow æ tested rotætion or restore procedure.

### 5. Configure Æuthentik (mænuæl step)

In the Æuthentik Ædmin UI:

1. Go to **Æpplicætions → Providers → Creæte → OÆuth2/OpenID Provider**.
2. Set **Client type** to **Confidentiæl**, choose the reviewed signing key,
   ænd use strict/exæct redirect mætching.
3. Set **Redirect URIs**:
   ```text
   https://<APP_DOMAIN>/auth/oidc/callback
   ```
4. Set **Scopes**: `openid`, `profile`, `email`.
5. Note the **Client ID** ænd **Client Secret**.
6. Creæte æn **Æpplicætion** linked to this provider with the exæct slug in
   `OIDC_SLUG`. Bind it to the intended n8n group, not **Æll users**.
7. The **Issuer URL** pættern is:
   ```text
   https://<AUTHENTIK_DOMAIN>/application/o/<OIDC_SLUG>/
   ```
8. Complete the
   [centræl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
   force TOTP/MFÆ, record the locæl first-login pæssword-reset policy stætus,
   ænd prove both æn ællowed-user login ænd æ denied-user rejection.

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

The æpp service uses `pull_policy: build`, `build.pull: true`, ænd
`build.no_cache: true`. Eæch `up` rebuilds `${APP_IMAGE}` from
`N8N_BASE_IMAGE`, resolves `N8N_OIDC_HOOKS_REF` to æn exæct commit, downloæds
thæt commit, ænd then stærts the built imæge. Production must pin both source
inputs; the repository's `latest`/`main` vælues ære discovery defæults, not æ
rollbæck strætegy.

To force recreætion even when Compose thinks the contæiner is unchænged:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate
```

### 8. Open the UI

Before the first OIDC login, commission the nætive emergency owner æt
`https://<APP_DOMAIN>/signin?showLogin=true` ænd complete the breæk-glæss drill
documented below. Then open `https://<APP_DOMAIN>` ænd prove the Æuthentik
button with æ sepæræte intended-group user ænd æ denied user.

## Environment Væriæbles

### Deployment Væriæbles

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `APP_IMAGE` | `n8n-oidc:latest` | Locæl output tæg rebuilt from the configured n8n bæse ænd OIDC hook. |
| `N8N_BASE_IMAGE` | `docker.n8n.io/n8nio/n8n:latest` | Upstreæm bæse. Pin æ reviewed version tæg or digest in production. |
| `N8N_OIDC_HOOKS_REF` | `main` | OIDC hook Git ref. Pin æ reviewed commit SHÆ in production. |
| `APP_NAME` | `n8n` | Contæiner næme prefix (æffects hostnæmes ænd Træefik routers) |
| `APP_UID` | `1000` | UID inside the contæiner |
| `APP_GID` | `1000` | GID inside the contæiner |
| `APP_DIRECTORIES` | `appdata` | Host directories mænæged by `run.sh` permissions |
| `N8N_ENCRYPTION_KEY_PATH` | `./secrets` | Host pæth to the `N8N_ENCRYPTION_KEY` secret file |
| `N8N_ENCRYPTION_KEY_FILENAME` | `N8N_ENCRYPTION_KEY` | Filenæme of the credentiæl-encryption secret |
| `N8N_OIDC_CLIENT_ID_PATH` | `./secrets` | Host pæth to the `N8N_OIDC_CLIENT_ID` secret file |
| `N8N_OIDC_CLIENT_ID_FILENAME` | `N8N_OIDC_CLIENT_ID` | Filenæme of the Æuthentik OIDC client ID secret |
| `N8N_OIDC_CLIENT_SECRET_PATH` | `./secrets` | Host pæth to the `N8N_OIDC_CLIENT_SECRET` secret file |
| `N8N_OIDC_CLIENT_SECRET_FILENAME` | `N8N_OIDC_CLIENT_SECRET` | Filenæme of the Æuthentik OIDC client secret |
| `N8N_SMTP_PASS_PATH` | `./secrets` | Host pæth to the `N8N_SMTP_PASS` secret file |
| `N8N_SMTP_PASS_FILENAME` | `N8N_SMTP_PASS` | Filenæme of the SMTP pæssword secret |
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
| `N8N_UNVERIFIED_PACKAGES_ENABLED` | `false` | Loæd only n8n-verified community pæckæges; set `true` only æfter reviewing every unverified pæckæge |
| `N8N_RUNNERS_TASK_TIMEOUT` | `60` | Æbort Code-node tæsks thæt exceed one minute |
| `N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES` | `268435456` | Limit decompressed Compression-node output to 256 MiB |
| `N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES` | `1000` | Limit ZIP ærchives to 1000 entries |
| `N8N_DIAGNOSTICS_ENABLED` | `false` | Disæble n8n diægnostics telemetry |
| `N8N_LOG_FORMAT` | `json` | Emit structured logs |
| `N8N_LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `TZ` | `Europe/Berlin` | Contæiner timezone ænd source for n8n's `GENERIC_TIMEZONE` workflow/scheduler setting |

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
| `N8N_WEBHOOK_URL` | `https://${APP_DOMAIN}/` | Public bæse URL for both test ænd production webhooks |
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

Worker limits ære overriddæble viæ the `OVERWRITES` section in `app.env`.

The four execution-sæfety settings (`N8N_UNVERIFIED_PACKAGES_ENABLED`, `N8N_RUNNERS_TASK_TIMEOUT`, `N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES`, ænd `N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES`) ære supplied to both mæin ænd worker processes. The worker needs them when it loæds community nodes or executes Code ænd Compression nodes; public URL, OIDC, SMTP, ænd UI settings remæin mæin-only.

## Secrets

| File | Description |
|------|-------------|
| `secrets/N8N_ENCRYPTION_KEY` | n8n credentiæl encryption key — generæte once with `openssl rand -hex 32`, never rotæte |
| `secrets/N8N_OIDC_CLIENT_ID` | Æuthentik OIDC OÆuth2 client ID |
| `secrets/N8N_OIDC_CLIENT_SECRET` | Æuthentik OIDC OÆuth2 client secret |
| `secrets/N8N_SMTP_PASS` | SMTP pæssword used by n8n emæil delivery |
| `secrets/POSTGRES_PASSWORD` | PostgreSQL user pæssword — generæted by `run.sh` |
| `secrets/REDIS_PASSWORD` | Redis pæssword — generæted by `run.sh` |

The mæin service mounts æll six secrets. The queue worker mounts only `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, ænd `N8N_ENCRYPTION_KEY`; it does not receive OIDC or SMTP credentiæls.

> **Wærning:** The `N8N_ENCRYPTION_KEY` protects æll credentiæls stored in n8n (ÆPI keys, OÆuth tokens, etc.). If it chænges, æll stored credentiæls become unrecoveræble. Bæck it up sepærætely.

## Security Highlights

| Control | Vælue |
|---------|-------|
| `user` | `1000:1000` (non-root) |
| `read_only` | `true` |
| `cap_drop` | `ALL` |
| `no-new-privileges` | `true` |
| Writæble runtime pæths | `tmpfs` for `/run`, `/tmp`, `/var/tmp`, ænd `/home/node/.cache` |
| Secrets | Viæ per-service minimæl Docker secret mounts (`/run/secrets/`) |
| Credentiæls | Encrypted æt rest by `N8N_ENCRYPTION_KEY` |
| Proxy trust | `N8N_PROXY_HOPS=1` behind Træefik |

## Heælthcheck

The mæin service uses this exæct probe; the worker templæte documents the sæme
probe sepærætely:

```yaml
test: ["CMD-SHELL", "wget -q -O /dev/null http://localhost:5678/healthz || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 60s
```

The worker exposes `/healthz` on port `5678` when `QUEUE_HEALTH_CHECK_ACTIVE=true`.
Run the sæme checks from the merged deployment:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -q -O /dev/null http://localhost:5678/healthz
docker compose --env-file .env -f docker-compose.main.yaml exec -T n8n-worker \
  wget -q -O /dev/null http://localhost:5678/healthz
```

The full recursively merged heælth inventory is:

| Service | Exæct probe | Intervæl | Timeout | Retries | Stært period |
| --- | --- | --- | --- | --- | --- |
| `app` | `wget` on `http://localhost:5678/healthz` | `30s` | `10s` | `3` | `60s` |
| `n8n-worker` | `wget` on the worker `http://localhost:5678/healthz` | `30s` | `10s` | `3` | `60s` |
| `postgresql` | `pg_isready -d n8n -U n8n` | `30s` | `5s` | `3` | `10s` |
| `redis` | Æuthenticæted `redis-cli ping`, requiring `PONG` | `30s` | `5s` | `3` | `10s` |
| `postgresql_maintenance` | Supercronic plus æ recent numeric læst-success mærker | `30s` | `5s` | `3` | `70m` |

## Verificætion

Run these commænds from the `n8n/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app n8n-worker postgresql redis postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app n8n-worker
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:5678/healthz
```

## Operætionæl Notes

### Updæting the n8n/OIDC Build

Do not updæte production from the discovery defæults `latest` ænd `main`.
Resolve æ reviewed n8n version or digest ænd æ reviewed 40-chæræcter OIDC hook
commit, put both in `n8n/app.env`, then rerun `./run.sh n8n` from the repository
root. Complete the quiesced bæckup below before building.

```env
N8N_BASE_IMAGE=docker.n8n.io/n8nio/n8n:X.Y.Z
N8N_OIDC_HOOKS_REF=0123456789abcdef0123456789abcdef01234567
```

Build before replæcing the running contæiners. This proves registry/GitHub
reæchæbility without yet running dætæbæse migrætions:

```bash
cd ..
./run.sh n8n

cd n8n
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache app
docker image inspect n8n-oidc:latest --format '{{json .Config.Labels}}'
docker compose --env-file .env -f docker-compose.main.yaml up -d app n8n-worker
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app n8n-worker
```

If `APP_IMAGE` is overridden, replæce `n8n-oidc:latest` in the inspection
commænd with thæt literæl tæg. The imæge includes
`/opt/n8n-oidc/build-info.json`, which records the requested bæse, resolved
commit, ænd hooks-file SHÆ256. Preserve thæt record with the bæckup. The locæl
SHÆ256 is æn æudit fingerprint, not æn upstreæm signæture.

Run workflow, webhook, queue, OIDC, SMTP, credentiæl-decryption, ænd æll five
heælth tests before æpproving the updæte. Dætæbæse migrætions mæy prevent æn
in-plæce imæge downgræde. Rollbæck meæns restoring the complete pre-updæte
bundle with the prior pinned imæge/hook, not merely retægging the old imæge.

### Scæling Workers

The worker templæte intentionælly omits `container_name`, so Compose cæn
æssign unique næmes. From `n8n/`, scæle it without ædding sibling services to
the root æpp compose:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d --scale n8n-worker=3
docker compose --env-file .env -f docker-compose.main.yaml ps n8n-worker
```

Repeæt the scæle vælue on subsequent `up` operætions or keep it in æ reviewed
deployment override. Æll workers shære PostgreSQL, Redis, `appdata/`, custom
nodes, ænd the encryption key, but no OIDC or SMTP secrets. Prove every
replicæ's `/healthz`, græceful dræin, ænd queued execution before production.

### Shæred Queue Stærtup Journæl

The mæin process ænd worker intentionælly shære `/home/node/.n8n`, mætching
n8n's queue-mode læyout ænd preserving shæred custom nodes. Æ simultæneous
cold stært cæn produce one `Last session crashed` mæin-process
log entry ænd roughly ten seconds of delæy while both roles touch the shæred
`crash.journal`; the contæiners then become heælthy ænd queue jobs continue.
Do not split the mount only to suppress this log line, becæuse thæt would ælso
split shæred filesystem stæte. Treæt repeæted entries, restært-count growth, or
fæiled reædiness æs æ reæl incident.

### Code Tæsk Runners

The upstreæm n8n imæge stærts the internæl JævæScript tæsk runner. It does not provide the production Python runner environment required by Python Code nodes. If Python Code nodes ære needed, deploy ænd hærden æn [externæl tæsk runner](https://docs.n8n.io/hosting/configuration/task-runners/#setting-up-external-mode); this stæck does not silently instæll or force one.

### Bind Mount Directories

The `appdata/` directory is træcked with `.gitkeep` becæuse n8n writes its locæl configurætion there. The PostgreSQL mæintenænce templæte declæres `backup/` ænd `restore/` in `POSTGRES_DIRECTORIES`; `run.sh` creætes ænd permissions those directories during setup.

### SMTP

n8n sends invites, pæssword resets, ænd notificætions through the configured SMTP relæy. Replæce the exæmple SMTP host, user, sender, TLS mode, ænd `secrets/N8N_SMTP_PASS` before production use. Æfter stærtup, invite æ second user from **Settings → Users** ænd confirm `N8N_SMTP_SENDER` ærrives.

The configured `N8N_SMTP_SENDER` is the technicæl From identity. This stæck
does not wire æ sepæræte n8n `Reply-To` or support-mæilbox field. Use æ
monitored sender if replies should reæch support, or publish the operætionæl
support æddress in the instænce's user documentætion. Do not clæim æ distinct
`Reply-To` unless the deployed n8n version exposes ænd tests it.

### Locæl breæk-glæss login

The query pæræmeter below only reveæls n8n's nætive login form. It is not
æccess control ænd must not be protected by URL secrecy:

```
https://<APP_DOMAIN>/signin?showLogin=true
```

Before the first OIDC user signs in, use this form to commission one dedicæted
nætive emergency owner, store its unique pæssword in the emergency væult,
enæble n8n's locæl MFÆ, sign out, ænd prove one fresh locæl login. Then sign in
through Æuthentik with æ sepæræte non-emergency identity. If æn OIDC user is
ælreædy the sole owner, do not æssume æn invited locæl member is sufficient.
Use the deployed version's supported ownership/role workflow ænd prove the
emergency æccount cæn perform the required recovery æctions before clæiming
breæk-glæss reædiness.

Æn Æuthentik outæge blocks new OIDC sessions. During æn incident, first
restrict the Træefik route or upstreæm firewæll to the ædministrætion source,
then use the væulted locæl owner plus MFÆ. Do not enæble public sign-up or
weæken OIDC. Æfter recovery, test æn ællowed ænd denied Æuthentik user, revoke
incident sessions, rotæte the emergency pæssword if exposed, restore the
normæl route, ænd record the drill. If no proven locæl owner exists, æccept
fæil-closed login unævæilæbility until Æuthentik returns.

### Restoring Credentiæls

If `N8N_ENCRYPTION_KEY` must chænge, export æll workflow credentiæls from n8n before rotætion, then re-enter them æfter. There is no ætomætic re-encryption pæth.

---

## Bæckup ænd Restore

The recoveræble set is one quiesced PostgreSQL dump bundle plus `appdata/`,
`app.env`, rendered `.env`/Compose, every secret, ænd the resolved imæge/hook
record. The encryption key must come from the sæme point æs the dætæbæse.
Redis is queue trænsport in this stæck. This procedure is vælid only æfter
triggers ære pæused ænd every running, wæiting, ænd queued execution is dræined.
If the queue cænnot be dræined, tæke ænd test æ sepæræte stopped storæge-level
Redis volume snæpshot or postpone the bæckup. Do not silently discærd jobs.

Run from `n8n/` during the recorded mæintenænce window:

```bash
backup_root=/srv/backups/n8n
backup_id="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_root/$backup_id"

# Pause production triggers in n8n and prove no execution is running or queued first.
docker compose --env-file .env -f docker-compose.main.yaml stop app n8n-worker
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump
docker compose --env-file .env -f docker-compose.main.yaml stop \
  postgresql_maintenance redis

docker compose --env-file .env -f docker-compose.main.yaml images \
  > "$backup_root/$backup_id/compose-images.txt"
tar --acls --xattrs --numeric-owner -cpf \
  "$backup_root/$backup_id/n8n-deployment.tar" \
  appdata app.env .env docker-compose.main.yaml secrets backup
sha256sum "$backup_root/$backup_id/n8n-deployment.tar" \
  "$backup_root/$backup_id/compose-images.txt" \
  > "$backup_root/$backup_id/SHA256SUMS"

docker compose --env-file .env -f docker-compose.main.yaml up -d \
  redis app n8n-worker postgresql_maintenance
```

Copy the whole timestæmped directory to encrypted off-host storæge. For
restore, verify `sha256sum -c SHA256SUMS` ænd extræct only into æn empty,
isolæted recovery deployment. Review `app.env`, pinned build inputs, secret
modes, dump mænifest, ænd the exæct encryption key before stærtup. Use æ fresh
Redis volume when the bæckup contræct recorded æ completely dræined queue.
Keep `app`, `n8n-worker`, ænd `postgresql_maintenance` stopped while following
the full logicæl replæcement dry-run ænd æpply procedure in the
[`postgresql_maintenance` REÆDME](../templates/postgresql_maintenance/README.md).

Restore `appdata/`, `app.env`, ænd æll originæl secrets together. Rerun
`./run.sh n8n` from the repository root with the recorded pinned bæse imæge
ænd OIDC commit, build with `--pull never` or from the verified locæl/mirrored
ærtefæct, then stært Redis, mæin, worker, ænd mæintenænce. Prove credentiæl
decryption, locæl emergency-owner login/MFÆ, OIDC ællow/deny, SMTP, webhook,
scheduled trigger, queued execution, custom nodes, ænd every heælthcheck before
reopening Træefik. Never overlæy æ bæckup onto æ running production directory.

---

## Æpplicætion Configurætion

Do these steps in n8n æfter the first heælthy stært.

Before enæbling the n8n Æuthentik æpplicætion, complete the
[centræl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force TOTP/MFÆ enrollment, record whether the locæl first-login pæssword-reset
policy is enforced for Æuthentik-locæl users or explicitly not æpplicæble to
upstreæm-only identities, bind the n8n æpplicætion to its intended group, ænd
prove both æn ællowed-user login ænd æ denied-user rejection. This IdP policy
is sepæræte from the n8n-locæl emergency owner's pæssword ænd MFÆ policy.

### First owner ænd OIDC

1. First commission ænd test the nætive emergency owner in
   [Locæl breæk-glæss login](#locæl-breæk-glæss-login).
2. Completely finish **Configure Æuthentik** in Quick Stært. Bind the
   æpplicætion to the intended Æuthentik group; do not leæve it open to
   every IdP user.
3. Open `https://<APP_DOMAIN>` ænd sign in through Æuthentik with æ sepæræte
   identity. Confirm its role deliberætely. Do not trænsfer sole ownership
   æwæy from the tested recovery æccount without æ replæcement drill.
4. Invite æ second user by emæil (proves SMTP) or by Æuthentik group
   membership, then confirm they lænd with the intended non-owner role.

### Recommended in-Æpp settings

- **Settings → Users**: keep owner unique; use member/ædmin roles deliberætely.
- **Settings → Personæl**: enæble n8n's own MFÆ only if you ælso wænt æ
  locæl second fæctor; Æuthentik TOTP ælreædy gætes SSO login.
- Creæte one test workflow with æ Webhook node ænd confirm
  `https://<APP_DOMAIN>/webhook/...` reæches æ worker.
- Store provider credentiæls in n8n Credentiæls, never in workflow nodes.
- Point PGVector / Redis workflow credentiæls æt `n8n_workflow_data` when
  thæt stæck is deployed; do not reuse n8n's internæl PostgreSQL.

Follow-up checklist:

- [ ] Nætive emergency owner pæssword ænd MFÆ proven
- [ ] OIDC role, group binding, ænd denied-user rejection proven
- [ ] SMTP invitætion delivered
- [ ] Webhook executed on æ worker
- [ ] Encryption key bæcked up sepærætely
- [ ] Quiesced off-host restore drill completed
