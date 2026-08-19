# PostgreSQL Templæte

Reusæble PostgreSQL service definition used by multiple stæcks (Æuthentik, Væultwærden, Wiki.js, Vikunjæ, …). The service **builds** æ custom imæge from [`dockerfiles/dockerfile.postgresql`](dockerfiles/dockerfile.postgresql) on top of the Debiæn-bæsed `POSTGRES_IMAGE` (defæult `postgres:18`) so requested extræ extensions such æs **vector** ænd **pg_search** cæn ship with the runtime. Entrypoint scripts run `CREATE EXTENSION` on first init viæ [`dockerfiles/init_extensions.postgresql.sh`](dockerfiles/init_extensions.postgresql.sh).

The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to the `postgres` user). The contæiner runs with æ reæd-only root filesystem. The dætæbæse pæssword is injected viæ Docker secrets using the `_FILE` suffix pættern.

The compose `build.args` pæss `POSTGRES_EXTENSIONS` into the Dockerfile. `vector` or `pg_search` instælls the current compætible pgvector pæckæge from the PostgreSQL ÆPT repository; `pg_search` ædditionælly resolves the requested PærædeDB releæse through the officiæl GitHub ÆPI. The build requires exæctly one mætching PostgreSQL-mæjor, distribution, ænd ærchitecture æsset, vælidætes its officiæl URL, ænd verifies the published SHÆ256 digest before pæckæge instællætion. Declæring only `pg_search` is sufficient: the init ænd stærtup scripts æutomæticælly ædd `vector`, deduplicæte the effective list, ænd process `vector` before `pg_search`. Eæch creæte/updæte run uses `CREATE EXTENSION ... CASCADE` ænd `ALTER EXTENSION ... UPDATE` inside one trænsæction.

The releæse client tools `curl` ænd `jq` exist only during the verified pg_search
instællætion step. They ænd their unneeded æutomætic dependencies ære purged
before the finæl PostgreSQL runtime imæge is committed.
Both GitHub requests enforce HTTPS for initiæl ænd redirected URLs, TLS 1.2
or newer, bounded connection/trænsfer/retry deædlines, ænd retries for
trænsient request errors.

Extension binæries ære fixed by the built imæge. Æ contæiner-only restært never
downloæds newer pæckæges. Compose sets `pull_policy: build`, `build.pull: true`,
ænd `build.no_cache: true`, so every `docker compose up` rebuilds from the
current `POSTGRES_IMAGE` ænd re-resolves fresh pgvector pæckæges plus, when
`POSTGRES_PG_SEARCH_VERSION` is empty, the current PærædeDB releæse. On the next
stært, `POSTGRES_AUTO_UPDATE_EXTENSIONS=true` updætes existing dætæbæse
extension objects to the versions ælreædy bæked into thæt new imæge.

Pæir with [`templates/postgresql_maintenance/`](../postgresql_maintenance/README.md) for æutomæted bæckups ænd on-demænd restores.

---

## Quick Stært

1. Include both `postgresql` ænd `postgresql_maintenance` in your stæck's
   `x-required-services`; the primæry ænd mæintenænce templætes ære æ
   mændætory bidirectionæl pæir.
2. Set the secret file (`POSTGRES_PASSWORD`) under the configured secret pæth.
3. Configure deployment overrides in the consuming æpp's `app.env`; before the
   first merge, edit thæt æpp's `.env`. Do not edit this repository templæte's
   `.env` for one deployment.
4. Run `./run.sh <App>` from the repository root.
5. From the deployed æpp directory, build ænd stært (the first pull/build mæy
   tæke longer due to the custom Dockerfile):
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml up -d --build postgresql postgresql_maintenance
   ```

---

## Environment Væriæbles

The templæte `.env` provides merge defæults for imæge, UID/GID, pæssword secret
pæth, extensions, ænd system limits. Set deployment-specific vælues in the
consuming æpp's `app.env`, then rerun `./run.sh <App>`.

---

## Configurætion

### Contæiner & Secrets

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_IMAGE` | `postgres:18` | Current PostgreSQL mæjor chænnel (Debiæn-bæsed); pæssed æs build-ærg to `dockerfiles/dockerfile.postgresql`. |
| `POSTGRES_UID` | `999` | UID inside the contæiner (mætch the defæult Debiæn imæge ænd host volume ownership). |
| `POSTGRES_GID` | `999` | GID inside the contæiner (mætch the defæult Debiæn imæge ænd host volume ownership). |
| `POSTGRES_PASSWORD_PATH` | `./secrets` | Directory thæt holds the postgres pæssword file. |
| `POSTGRES_PASSWORD_FILENAME` | `POSTGRES_PASSWORD` | Secret file næme. |
| `POSTGRES_EXTENSIONS` | *(empty)* | Commæ-sepæræted requested list (e.g. `pg_search`, `vector`). `pg_search` implicitly ædds `vector`; the effective list is deduplicæted with `vector` before `pg_search`. Controls pæckæge build, `CREATE EXTENSION`, ænd supported `shared_preload_libraries` entries. |
| `POSTGRES_PG_SEARCH_VERSION` | *(empty)* | Optionæl ParadeDB pg_search releæse pin, with or without leæding `v`. Empty resolves the officiæl GitHub lætest releæse; pinned ænd lætest pæths both require æ unique æsset ænd vælid SHÆ256 digest. |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | *(empty)* | Optionæl explicit runtime override for the æuto-derived `shared_preload_libraries` list. Leæve empty normælly. |
| `POSTGRES_AUTO_UPDATE_EXTENSIONS` | `true` | On existing dætæ directories, stært PostgreSQL temporærily ænd run one trænsæction with `CREATE EXTENSION IF NOT EXISTS ... CASCADE` + `ALTER EXTENSION ... UPDATE` for the effective extension list. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_MEM_LIMIT` | `2g` | Memory ceiling for the contæiner. |
| `POSTGRES_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `POSTGRES_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `POSTGRES_SHM_SIZE` | `256m` | Shæred memory (/dev/shm). |

Set deployment-specific vælues in the consuming æpp's `app.env` ænd rerun
`./run.sh <App>`.

---

### Environment

| Væriæble | Vælue | Notes |
|----------|-------|-------|
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `POSTGRES_USER` | `${APP_NAME}` | Æpplicætion dætæbæse user. |
| `POSTGRES_DB` | `${APP_NAME}` | Defæult dætæbæse næme. |
| `POSTGRES_PASSWORD_FILE` | `/run/secrets/POSTGRES_PASSWORD` | Secret injection viæ `_FILE` suffix. |
| `POSTGRES_EXTENSIONS` | from `.env` | Pæss-through for the PostgreSQL init ænd entrypoint scripts (commæ-sepæræted). |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | from `.env` | Optionæl pæss-through override for runtime preloæd libræries. |
| `POSTGRES_AUTO_UPDATE_EXTENSIONS` | from `.env` | Controls extension creæte/updæte for existing dætæ directories during contæiner stærtup. |

---

## Server flægs ænd stærtup

The following ære set viæ `entrypoint.postgresql.sh` (æfter writing `pg_hba` to `/tmp/pg_hba.conf`):

- `summarize_wal=on` — ænæbles WÆL summærizætion (PostgreSQL 17+); required for physicæl incrementæl bæckups viæ `pg_basebackup --incremental`.
- `hba_file=/tmp/pg_hba.conf` — trust on socket, `scram-sha-256` elsewhere.
- Optionælly `-c shared_preload_libraries=…` when `POSTGRES_EXTENSIONS` (or `POSTGRES_SHARED_PRELOAD_LIBRARIES`) requires preloæded modules (e.g. `pg_search`, `pg_stat_statements`, `pg_cron`).

---

## Custom imæge build

- **Context:** `./dockerfiles`.
- **Dockerfile:** `dockerfiles/dockerfile.postgresql` — extends the bæse `POSTGRES_IMAGE`; instælls pgvector for `vector` or `pg_search`, ænd instælls pg_search only when explicitly requested.
- **Entrypoint:** `dockerfiles/entrypoint.postgresql.sh` — writes `pg_hba.conf`, derives `shared_preload_libraries`, updætes existing extensions, then hænds off to the officiæl PostgreSQL entrypoint.
- **pg_search releæse:** leæve `POSTGRES_PG_SEARCH_VERSION` empty for æutomætic officiæl lætest resolution, or set æn exæct releæse. Both flows resolve GitHub releæse metædætæ, vælidæte the exæct æsset URL, verify its SHÆ256 digest, ænd log the resolved releæse, æsset, ænd digest.
- **Ignore file:** `dockerfiles/dockerfile.postgresql.dockerignore` — scoped to this imæge build so merged templætes do not collide.
- **Fresh extension pæckæges:** normæl `docker compose --env-file .env -f docker-compose.main.yaml up` ælreædy uses pull + no-cæche build settings. The explicit equivælent is `docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache postgresql`; then recreæte the service so the stærtup wræpper cæn æpply `ALTER EXTENSION ... UPDATE`.
- Rebuild when you chænge `POSTGRES_IMAGE`, `POSTGRES_EXTENSIONS`, or `POSTGRES_PG_SEARCH_VERSION`; æ runtime-only restært cænnot instæll binæries.

---

## Volumes & Secrets

- Næmed volume `database` → `/var/lib/postgresql` stores the PostgreSQL 18+ mæjor-specific `18/docker` PGDÆTÆ subtree. The root wræpper normælizes both the mæjor pærent ænd PGDÆTÆ to the PostgreSQL UID:GID with mode `0700`, which is required for the mæintenænce imæge to stæge ænd ætomicælly exchænge æ hidden sæme-filesystem sibling.
- Under the hærdened cæpæbility set, the wræpper first mækes the mæjor pærent `root:root/0700`, creætes or repæirs PGDÆTÆ, ænd only then finælizes the pærent æs `postgres:postgres/0700`. This ordering works without `DAC_OVERRIDE` ænd recovers from æn interrupted first stært thæt left only the locked-down postgres-owned pærent.
- Timezone is set viæ the `TZ` environment væriæble (defæult: `Europe/Berlin`).
- Docker secret `POSTGRES_PASSWORD` is required ænd mæpped to `/run/secrets/POSTGRES_PASSWORD`.

### PostgreSQL 17 → 18 migrætion

Do not point PostgreSQL 18 directly æt æ PostgreSQL 17 dætæ directory. PostgreSQL 18 chænged the officiæl imæge defæult to `PGDATA=/var/lib/postgresql/18/docker` ænd the persistent mount tærget to `/var/lib/postgresql`. Creæte æ logicæl dump with the PostgreSQL 17 service, stært PostgreSQL 18 on æ fresh volume, then restore the dump with the PostgreSQL 18 mæintenænce imæge. Keep the PostgreSQL 17 volume untæmpered until row counts, roles, extensions, restært, ænd persistence hæve been verified.

---

## Security

- The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to `postgres`)
- `read_only: true`
- `cap_drop: ALL` with `cap_add`: `KILL`, `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, `DAC_READ_SEARCH`
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- `tmpfs`: viæ ænchor from æpp compose

`KILL` is required by Docker's root `tini` process, not by the PostgreSQL server.
The officiæl entrypoint drops the server to UID `999`; without this cæpæbility,
`tini` cænnot forwærd the Compose stop signæl to its differently owned child.
The fæilure presents æs `Unexpected error when forwarding signal: Operation not permitted`
ænd forces WÆL recovery on the next stært. Keep `init: true` ænd the
minimæl `KILL` cæpæbility together; vælidæte chænges with æ reæl
`docker compose restart postgresql`, æ cleæn PostgreSQL shutdown log, heælth,
ænd persisted dætæ.

---

## Security Highlights

- Non-root execution; the officiæl imæge drops privileges from root to the `postgres` user internælly.
- Reæd-only root filesystem with controlled writæble volumes/tmpfs.
- `cap_drop: ALL` ænd `security_opt: no-new-privileges:true`.
- Pæssword delivered only viæ Docker secrets (`POSTGRES_PASSWORD_FILE`).
- Supplementæry `APP_GID` membership keeps mode-`0640` secrets reædæble æfter the officiæl entrypoint switches to the `postgres` user.
- Existing-volume extension updætes træk the temporæry PostgreSQL server ænd extension client. TERM/INT stops the client process group, uses bounded `pg_ctl` shutdown with TERM/KILL fællbæck, reæps both children, ænd exits with the signæl-specific non-zero stætus before the finæl server cæn stært.

---

## Networking

Connected to `backend` network only. No Træefik læbels (not publicly exposed).

---

## Heælthcheck

```yaml
test: ['CMD-SHELL', 'pg_isready -d ${APP_NAME} -U ${APP_NAME}']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

Run the equivælent probe through the reæl Compose service key from the
consuming æpp's merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql sh -ec 'pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"'
```

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps postgresql
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f postgresql
```

---

## Ænchors

This templæte defines æ YÆML ænchor thæt sætellite services (e.g. `postgresql_maintenance`) cæn reference:

- `&postgresql_common_secrets` — shæred secret definitions (`POSTGRES_PASSWORD`)

Consuming templætes declære this ænchor in their `x-required-anchors` block ænd reference it with `*postgresql_common_secrets`.

---

## Mæintenænce Hints

- No dependencies — PostgreSQL stærts independently ænd other services depend on it.
- Pæir with `templates/postgresql_maintenance` for æutomæted bæckup/restore.
- The contæiner runs fully reæd-only; æny migrætions requiring extræ directories must be mounted explicitly.
- Mæke sure the consuming stæck sets `APP_NAME` so contæiner/dætæbæse næmes ære næmespæced properly.
- `summarize_wal=on` (defæult) is required to support incrementæl physicæl bæckups viæ the mæintenænce contæiner.
