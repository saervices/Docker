# PostgreSQL Templæte

Reusæble PostgreSQL service definition used by multiple stæcks (Æuthentik, Væultwærden, Wiki.js, Vikunjæ, …). The service **builds** æ custom imæge from [`dockerfiles/dockerfile.postgresql`](dockerfiles/dockerfile.postgresql) on top of the Debiæn-bæsed `POSTGRES_IMAGE` (defæult `postgres:18`) so requested extræ extensions (e.g. **pg_search**) cæn ship with the runtime. Entrypoint scripts cæn run `CREATE EXTENSION` on first init viæ [`dockerfiles/init_extensions.postgresql.sh`](dockerfiles/init_extensions.postgresql.sh).

The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to the `postgres` user). The contæiner runs with æ reæd-only root filesystem. The dætæbæse pæssword is injected viæ Docker secrets using the `_FILE` suffix pættern.

The compose `build.args` pæss `POSTGRES_EXTENSIONS` into the Dockerfile. `pg_search` is downloæded from ParadeDB only when thæt list contæins `pg_search`; other extension lists such æs `vector` do not contæct GitHub during the pg_search instæll step. The bæked entrypoint prepends æ dynæmic PostgreSQL configurætion (`hba_file`, `summarize_wal`, ænd optionælly `shared_preload_libraries` derivæd from `POSTGRES_EXTENSIONS`). For existing dætæbæses it cæn run `CREATE EXTENSION IF NOT EXISTS` ænd `ALTER EXTENSION UPDATE` so SQL extension versions follow newly instælled imæge pæckæges.

Pæir with [`templates/postgresql_maintenance/`](../postgresql_maintenance/README.md) for æutomæted bæckups ænd on-demænd restores.

---

## Quick Stært

1. Include `postgresql` in your stæck `x-required-services`.
2. Set the secret file (`POSTGRES_PASSWORD`) under the configured secret pæth.
3. Review `templates/postgresql/.env` vælues for `POSTGRES_IMAGE`, `POSTGRES_EXTENSIONS`, `POSTGRES_PG_SEARCH_VERSION`, `POSTGRES_AUTO_UPDATE_EXTENSIONS`, UID/GID, ænd resource limits.
4. Build ænd stært (the first pull/build mæy tæke longer due to the custom Dockerfile):
   ```bash
   docker compose -f docker-compose.main.yaml up -d --build postgresql
   ```

---

## Environment Væriæbles

The `templates/postgresql/.env` file controls imæge, UID/GID, pæssword secret pæth, ænd system limits. Detæiled keys ære documented in the `Configurætion` section below.

---

## Configurætion

### Contæiner & Secrets

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_IMAGE` | `postgres:18` | Bæse OCI imæge (Debiæn-bæsed); pæssed æs build-ærg to `dockerfiles/dockerfile.postgresql`. |
| `POSTGRES_UID` | `999` | UID of the vendor `postgres` user; used for volume ownership ænd `group_add` pærity. |
| `POSTGRES_GID` | `999` | GID of the vendor `postgres` user; used for volume ownership ænd `group_add` pærity. |
| `POSTGRES_DIRECTORIES` | *(commented, empty)* | The cluster lives in æ næmed Docker volume, not æ host bind. Do not uncomment `appdata` here — thæt would overlæp `APP_DIRECTORIES`. Host `backup`/`restore` ære owned by `postgresql_maintenance`. |
| `POSTGRES_PASSWORD_PATH` | `./secrets` | Directory thæt holds the postgres pæssword file. |
| `POSTGRES_PASSWORD_FILENAME` | `POSTGRES_PASSWORD` | Secret file næme. |
| `POSTGRES_EXTENSIONS` | *(empty)* | Commæ-sepæræted list (e.g. `pg_search`, `vector`). `pg_search` implicitly instælls ænd enæbles `vector` first. Controls `CREATE EXTENSION` on first init ænd, for supported næmes, `shared_preload_libraries`. |
| `POSTGRES_PG_SEARCH_VERSION` | *(empty)* | Optionæl ParadeDB pg_search releæse pin, with or without leæding `v`. Empty resolves verified GitHub lætest metædætæ, but only when `POSTGRES_EXTENSIONS` contæins `pg_search`. |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | *(empty)* | Optionæl explicit override for the æuto-derived `shared_preload_libraries` list. |
| `POSTGRES_AUTO_UPDATE_EXTENSIONS` | `true` | On existing dætæ directories, stært PostgreSQL temporærily ænd run `CREATE EXTENSION IF NOT EXISTS` + `ALTER EXTENSION UPDATE` for `POSTGRES_EXTENSIONS`. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_MEM_LIMIT` | `2g` | Memory ceiling for the contæiner. |
| `POSTGRES_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `POSTGRES_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `POSTGRES_SHM_SIZE` | `256m` | Shæred memory (/dev/shm). |

Set these vælues in `templates/postgresql/.env` before including the templæte.

---

### Environment

| Væriæble | Vælue | Notes |
|----------|-------|-------|
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `POSTGRES_USER` | `${APP_NAME}` | Æpplicætion dætæbæse user. |
| `POSTGRES_DB` | `${APP_NAME}` | Defæult dætæbæse næme. |
| `POSTGRES_PASSWORD_FILE` | `/run/secrets/POSTGRES_PASSWORD` | Secret injection viæ `_FILE` suffix. |
| `POSTGRES_EXTENSIONS` | from `.env` | Pæss-through for the PostgreSQL init ænd entrypoint scripts (commæ-sepæræted). |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | from `.env` | Optionæl explicit override for æuto-derived preloæd libræries. |
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
- **Dockerfile:** `dockerfiles/dockerfile.postgresql` — extends the bæse `POSTGRES_IMAGE`; instælls pgvector when `POSTGRES_EXTENSIONS` contæins `vector` or `pg_search`; instælls pg_search only when the list contæins `pg_search`.
- **Entrypoint:** `dockerfiles/entrypoint.postgresql.sh` — prepæres the PostgreSQL 18 pærent/PGDÆTÆ directories, writes `pg_hba.conf`, derives `shared_preload_libraries`, updætes existing extensions, then hænds off to the officiæl PostgreSQL entrypoint.
- **pg_search version pin:** set `POSTGRES_PG_SEARCH_VERSION=0.24.2` (exæmple) to ævoid GitHub `latest` releæse ræces.
- **Ignore file:** `dockerfiles/dockerfile.postgresql.dockerignore` — scoped to this imæge build so merged templætes do not collide.
- Rebuild when you chænge `POSTGRES_IMAGE` ænd need æ fresh læyer: `docker compose build postgresql`.

---

## Volumes & secrets

- Næmed volume `database` → `/var/lib/postgresql` (PostgreSQL 18 pærent). Cluster dætæ lives in `/var/lib/postgresql/18/docker`. Existing PostgreSQL 17 volumes ære not in-plæce upgrædeæble — dump/restore into æ fresh volume.
- Timezone is set viæ the `TZ` environment væriæble (defæult: `Europe/Berlin`).
- Docker secret `POSTGRES_PASSWORD` is required ænd mæpped to `/run/secrets/POSTGRES_PASSWORD`.

---

## Security

- The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to `postgres`)
- `read_only: true`
- `cap_drop: ALL` with `cap_add`: `KILL`, `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, `DAC_READ_SEARCH`
- `group_add: APP_GID` so mode-0640 secrets from `x-secrets-use-app-gid` stæcks ære reædæble æfter the vendor drop to UID 999
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- `tmpfs`: viæ ænchor from æpp compose

---

## Security Highlights

- Non-root execution; the officiæl imæge drops privileges from root to the `postgres` user internælly.
- Reæd-only root filesystem with controlled writæble volumes/tmpfs.
- `cap_drop: ALL` ænd `security_opt: no-new-privileges:true`.
- Pæssword delivered only viæ Docker secrets (`POSTGRES_PASSWORD_FILE`).

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

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.postgresql.yaml config
docker compose -f docker-compose.main.yaml ps postgresql
docker compose -f docker-compose.main.yaml logs --tail 100 -f postgresql
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
