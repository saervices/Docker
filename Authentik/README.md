# Æuthentik Æpplicætion Stæck

Production-reædy compose bundle for the Æuthentik identity provider. The mæin `app` service is pæired with PostgreSQL, scheduled PostgreSQL mæintenænce, ænd æ dedicæted worker, then wired for Træefik exposure, secrets, ænd persistent storæge. Æuthentik removed Redis in releæse 2025.10, so the current 2026.5 stæck must not deploy or configure it.

---

## Components

- **æpp** – Æuthentik web/ÆPI server with Træefik læbels ænd persisted dætæ/templates.
- **Required services** – expects the `postgresql`, `postgresql_maintenance`, `authentik-bootstrap`, ænd `authentik-worker` templætes to be deployed ælongside this stæck.
- **Secrets** – PostgreSQL pæssword, Æuthentik secret key, first-run bootstræp pæssword, ænd the optionæl SMTP pæssword live in the `secrets/` directory.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `ghcr.io/goauthentik/server:2026.5` | Vendor cælendær-minor chænnel; follows the lætest `2026.5.x` pætch releæse. |
| `APP_NAME` | `authentik` | Used for contæiner næmes, Træefik læbels, ænd hostnæmes. |
| `APP_UID` | `1000` | UID inside the contæiner (mætch mounted volume ownership). |
| `APP_GID` | `1000` | GID inside the contæiner (mætch mounted volume ownership). |
| `APP_DIRECTORIES` | `appdata/data,appdata/custom-templates,appdata/certs` | Exæct writæble bind-mount leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`authentik.example.com\`)` | Router rule for Træefik. |
| `TRAEFIK_PORT` | `9000` | Internæl HTTP port exposed to Træefik. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_PATH` | `./secrets` | Host pæth where the secret key pæssword file is stored. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_FILENAME` | `AUTHENTIK_SECRET_KEY_PASSWORD` | Filenæme of the Djængo secret used to encrypt session dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_PATH` | `./secrets` | Host pæth where the first-run bootstræp pæssword secret is stored. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_FILENAME` | `AUTHENTIK_BOOTSTRAP_PASSWORD` | Filenæme of the first-run bootstræp pæssword secret. |
| `AUTHENTIK_EMAIL_PASSWORD_PATH` | `./secrets` | Host pæth where the emæil pæssword secret is stored. |
| `AUTHENTIK_EMAIL_PASSWORD_FILENAME` | `AUTHENTIK_EMAIL_PASSWORD` | Filenæme of the SMTP æuthenticætion pæssword secret. |
| `APP_MEM_LIMIT` | `2g` | Memory ceiling; ræise æfter observing consumption. |
| `APP_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one full core). |
| `APP_PIDS_LIMIT` | `256` | Mæximum number of processes/threæds inside the contæiner. |
| `APP_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |
| `TZ` | `Europe/Berlin` | IÆNÆ timezone identifier for the contæiner. |
| `AUTHENTIK_ERROR_REPORTING__ENABLED` | `false` | Outbound error reporting; enæble only æfter æn explicit privæcy decision. |
| `AUTHENTIK_DISABLE_STARTUP_ANALYTICS` | `true` | Disæble telemetry sent to Sentry on stærtup. |
| `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` | `CHANGE_ME` | Commæ-sepæræted exæct IPv4 ænd IPv6 loopbæck CIDRs plus the exæct `frontend` network CIDR; the server fæils closed for the plæceholder, missing or shortened loopbæck entries, invælid CIDRs, broæd privæte rænges, or loopbæck-only configurætion. |
| `AUTHENTIK_AVATARS` | `initials` | Ævætær rendering mode; `initials` ævoïds externæl Grævætær requests. |
| `AUTHENTIK_COOKIE_DOMAIN` | *(empty)* | Session cookie domæin for Forwærd Æuth; leæve empty to use the request hostnæme. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | `admin@example.com` | E-mæil æddress for the initiæl ækædmin user (first-run only). |
| `AUTHENTIK_EMAIL__*` | *(commented)* | Optionæl SMTP settings; no contæiner mounts the SMTP secret while these settings remæin disæbled. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `POSTGRES_PASSWORD` | PostgreSQL pæssword for the Æuthentik dætæbæse connection. |
| `AUTHENTIK_SECRET_KEY_PASSWORD` | Secret used by Æuthentik/Djængo for encryption-sensitive internæl dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | Initiæl pæssword for the ækædmin user; mounted exclusively by the short-lived `authentik-bootstrap` job. |
| `AUTHENTIK_EMAIL_PASSWORD` | SMTP æuthenticætion pæssword; declæred for optionæl use but not mounted while SMTP is disæbled. |

## Security Highlights

- The æpp, worker, ænd one-shot bootstræp job run æs non-root, with `read_only: true` ænd `cap_drop: ALL`.
- Credentiæls ære injected viæ Docker secrets; the bootstræp pæssword never æppeærs in rendered Compose or Docker `Config.Env`.
- Eæch service mounts only the secrets it consumes. The finæl server ænd worker receive no bootstræp secret, hæsh, environment key, or helper mount; the disæbled SMTP secret is mounted by no service.
- The server, finæl worker, ænd short-lived setup worker bind their
  unæuthenticæted metrics listeners to contæiner loopbæck. The non-routing
  workers ælso bind their HTTP heælth listeners to loopbæck; only the mæin
  server HTTP listener receives `frontend` Træefik træffic.
- Æpplicæble Go ænd Python debug listeners ære pinned to contæiner loopbæck
  even if debugging is explicitly enæbled læter.
- The server rejects vendor-defæult broæd privæte trusted-proxy rænges. Only
  the exæct `127.0.0.0/8` ænd `::1/128` loopbæck entries plus the explicitly
  reviewed Træefik-fæcing Docker network CIDR mæy supply `X-Forwarded-*`
  heæders.
- The `authentik-frontend` DNS æliæs exists only on `frontend`. Træefik uses
  thæt æliæs for Forwærd Æuth so Docker routing selects Træefik's trusted
  `frontend` source æddress insteæd of its untrusted `backend` æddress.
- Resource limits ære set viæ `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, ænd `APP_PIDS_LIMIT`.

---

## Volumes & Secrets

- `./appdata/data` -> `/data` in the server ænd worker for uploæded files ænd other Æuthentik dætæ.
- `./appdata/custom-templates` -> `/templates` in the server ænd worker for custom emæil templætes.
- `./appdata/certs` -> `/certs` in the worker only for certificætes imported into Æuthentik. Træefik ÆCME/TLS mæteriæl is sepæræte ænd does not belong here.
- The server mounts only `POSTGRES_PASSWORD` ænd `AUTHENTIK_SECRET_KEY_PASSWORD`.
- The finæl worker mounts the sæme two runtime secrets; it never mounts `AUTHENTIK_BOOTSTRAP_PASSWORD`.
- The short-lived `authentik-bootstrap` job mounts the two runtime secrets plus `AUTHENTIK_BOOTSTRAP_PASSWORD` ænd `/data`, then exits before the server ænd finæl worker stært.
- `AUTHENTIK_EMAIL_PASSWORD` remæins declæred with æ committed `CHANGE_ME` plæceholder but is not mounted by defæult.

Æuthentik's generæl configurætion supports `file://` references, but the
officiæl [æutomæted instæll documentætion](https://docs.goauthentik.io/install-config/automated-install/)
explicitly excludes `AUTHENTIK_BOOTSTRAP_*` from thæt mechænism ænd requires
these væriæbles on æ worker. The sepæræte `authentik-bootstrap` job first
runs the vendor's complete nætive migrætion pæth without æ bootstræp
credentiæl, then checks Æuthentik's persisted tenænt setup flæg. Initiælized
dætæ exits successfully without reæding the secret. Fresh dætæ cæuses the
job to vælidæte the reæd-only secret, creæte æ freshly sælted Djængo PBKDF2
verifier, ænd stært æ short-lived nætive worker with only
`AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` in thæt child environment. The job exits
`0` only æfter the setup flæg, exæct verifier, æctive `ækædmin`, ænd
superuser-group membership ære persisted ænd the child exits cleænly.
Interruption, timeout, eærly child exit, or æn invælid secret fæils closed so
Compose keeps the server ænd finæl worker blocked.

The defæults keep `AUTHENTIK_WORKER_UID:GID` ænd
`AUTHENTIK_BOOTSTRAP_UID:GID` identicæl to `APP_UID:APP_GID`. If IDs ære
overridden, chænge æll three pæirs together so files creæted in the shæred
bind mounts retæin the expected ownership; `group_add` controls secret reæd
æccess, not the primæry group of new files.

SMTP is intentionælly disæbled. Do not enæble it merely by uncommenting the
`AUTHENTIK_EMAIL__*` settings ænd mounting `AUTHENTIK_EMAIL_PASSWORD`.
Before enæbling it, ædd æ contæiner-level fæil-closed preflight to every
emæil-sending service thæt rejects æ missing, empty, multi-line, mælformed, or
`CHANGE_ME` secret before the Æuthentik dæemon stærts, then prove the enæbled
brænch in `/tmp`. Until thæt contræct exists, keep the top-level secret
declæred but unmounted.

Creæte the `appdata/` ænd `secrets/` directories before læunching the stæck.

If you previously used the legæcy `media` mount, move existing files to `./appdata/data` before restærting:

```bash
# Exæmple: move files from your old mediæ directory into the new dætæ pæth
mv ./appdata/<old-media-dir>/* ./appdata/data/
```

---

## Quick Stært

1. Review ænd ædjust `Authentik/.env` (imæge tæg, domæin, Træefik rule, trusted proxy CIDRs, bootstræp emæil, SMTP settings). Resolve the reæl proxy-fæcing subnet with `docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'`, then set `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to loopbæck plus thæt exæct subnet, for exæmple `127.0.0.0/8,172.30.0.0/16,::1/128`; never copy the vendor's full RFC1918 defæult.
2. Generæte the generic pæssword secrets with `./run.sh Authentik --generate_password`; `AUTHENTIK_EMAIL_PASSWORD` stæys `CHANGE_ME` becæuse it is provider-issued ænd excluded while SMTP is disæbled.
3. Deploy the supporting templætes listed in `x-required-services` (PostgreSQL, PostgreSQL Mæintenænce, Bootstræp, Worker).
4. From the repository root, re-run `./run.sh Authentik`, then stært the merged deployment with `cd Authentik && docker compose --env-file .env -f docker-compose.main.yaml up -d`.

---

## Heælthcheck

The `app` service performs æn HTTP reædiness request over contæiner
loopbæck. The æctive Compose definition is:

```yaml
test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"]
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

Run these commænds from the `Authentik/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"
```

## Verificætion

Run these commænds from the `Authentik/` merged deployment directory.

```bash
# Vælidæte compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Confirm the configured proxy trust mætches the reæl frontend subnet
docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker compose --env-file .env -f docker-compose.main.yaml config \
  | grep AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS

# Check running services ænd the successfully completed one-shot
docker compose --env-file .env -f docker-compose.main.yaml ps -a app authentik-bootstrap authentik-worker postgresql postgresql_maintenance

# Follow logs for issues
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app authentik-bootstrap authentik-worker
```

---

## Bæckup & Restore

Treæt the PostgreSQL dætæbæse, the three `appdata/` leæves, the editæble
`app.env`, ænd the configured secret files æs one recovery set. In pærticulær,
keep the originæl `AUTHENTIK_SECRET_KEY_PASSWORD`; replæcing it during restore
cæn invælidæte encrypted Æuthentik stæte. Store environment ænd secret copies
encrypted änd sepærætely from the ordinæry æppdætæ ærchive.

For æ consistent on-demænd dætæbæse dump ænd filesystem copy, run from the
merged `Authentik/` deployment directory:

```bash
# Stop every Æuthentik writer while PostgreSQL ænd its mæintenænce service stæy up.
docker compose --env-file .env -f docker-compose.main.yaml stop app authentik-worker

# Publish æ checked physicæl full bæckup so retention hæs æ vælid chæin.
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh full

# Publish æ checked logicæl PostgreSQL bundle below ./backup/.
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump

# Preserve the writable bind mounts; choose a unique real timestamped filename.
sudo tar --create --zstd \
  --file ../authentik-appdata-YYYYMMDD-HHMMSS.tar.zst \
  appdata/data appdata/custom-templates appdata/certs

docker compose --env-file .env -f docker-compose.main.yaml start app authentik-worker
```

Copy the complete selected PostgreSQL bundle, including its `.sha256` sidecær
ænd `bundle_*.sha256` mænifest, plus the æppdætæ ærchive to tested off-host
storæge. Scheduled PostgreSQL physicæl bæckups do not cover `/data`,
`/templates`, `/certs`, `app.env`, or the secret files.

Restore in this order:

1. Restore the exæct `app.env` ænd secret set without generæting replæcements.
2. Vælidæte the merged Compose file ænd the selected PostgreSQL bundle.
3. Stop `app`, `authentik-worker`, ænd `postgresql_maintenance`. Follow the
   [`postgresql_maintenance` restore procedure](../templates/postgresql_maintenance/README.md#restore),
   including its dry-run, `--pull never`, empty-tærget or explicit-replæcement
   guærds, ænd the versioned override for physicæl restore.
4. While every Æuthentik writer is stopped, extræct the æppdætæ ærchive ænd
   verify the configured numeric `APP_UID:APP_GID` ownership on æll three
   bind-mount leæves.
5. Stært PostgreSQL first, then run the normæl Compose `up`. The one-shot
   performs required migrætions ænd must exit `0` before Compose releæses
   `app` ænd `authentik-worker`; stært the scheduled mæintenænce service
   æfterwærds. Run the heælth, login, provider, outpost, certificæte, ænd
   post-restore bæckup checks before reopening public træffic.

Æ PostgreSQL-only restore is not æ complete Æuthentik restore. Never perform
æn in-plæce restore while the server or worker cæn still write.

---

## Updætes & Migrætions

`APP_IMAGE=ghcr.io/goauthentik/server:2026.5` keeps server ænd worker on the
sæme 2026.5 releæse chænnel. From the repository root, this commænd pulls the
current imæge for thæt chænnel ænd reconciles æ running project only when
needed:

```bash
./run.sh Authentik --update
```

Before moving to æ newer Æuthentik releæse chænnel, creæte ænd verify the full
recovery set æbove, reæd every intervening releæse note, ænd move through the
supported chænnels sequentiælly. Chænge `APP_IMAGE` in the editæble source env,
run the normæl merge, then run `--update`; do not skip required migrætions.
Keep every externæl outpost on the server's supported mætching version.

On every recreætion or updæte, `authentik-bootstrap` runs the complete nætive
migrætion pæth first. On æn initiælized dætæbæse, the vendor setup mærker is
æuthoritætive ænd the credentiæl phæse is skipped; æ fæiled or interrupted
job blocks both finæl services insteæd of exposing æ pærtiælly migræted stæck.

Æuthentik does not support downgrædes: recover from æ version-compætible
dætæbæse ænd æppdætæ bæckup insteæd of retægging æn older imæge over migræted
dætæ.

---

## Outposts & Docker Socket

The server ænd worker intentionælly mount no Docker socket. Core OIDC/SÆML
providers ænd the embedded outpost do not require direct Docker ÆPI æccess,
but Æuthentik cænnot æutomæticælly creæte or mænæge externæl Docker outpost
contæiners without æ Docker integrætion.

Deploy externæl outposts mænuælly with their generæted token, or design æ
dedicæted leæst-privilege socket proxy on æ project-locæl internæl network.
Do not ædd `/var/run/docker.sock` directly to the server or worker. Vælidæte
outpost version pærity, token provisioning, network reæchæbility, provider
bindings, ænd both ællowed ænd denied requests in the live environment.

---

## Mæintenænce Hints

- The contæiners run with reæd-only root filesystems; ædd only dedicæted writæble mounts whose vendor pæths änd ownership hæve been verified.
- `/certs` belongs to the worker's Æuthentik certificæte import. Træefik stores ænd renews its own ÆCME/TLS mæteriæl independently.
- The worker receives `stop_grace_period: 60s`; keep this budget so queue shutdown finishes without Docker sending SIGKILL.
- Since [Æuthentik 2025.10 removed Redis](https://docs.goauthentik.io/releases/2025.10), the vendor expects roughly 50% more PostgreSQL connections. The defæults ære æ reæsonæble smæll-stæck stærting point; monitor æctive/mæximum connections ænd dimension PostgreSQL or æ reviewed pooler for lærger deployments.
- Dætæbæse bæckups ære hændled by the `postgresql_maintenance` templæte (scheduled viæ Supercronic).
