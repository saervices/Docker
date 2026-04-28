# PostgreSQL Templæte

Reusæble PostgreSQL service definition used by multiple stæcks (Æuthentik, Væultwærden, Wiki.js, Vikunjæ, …). The service **builds** æ custom imæge from [`dockerfiles/dockerfile.postgresql`](dockerfiles/dockerfile.postgresql) on top of the Debiæn-bæsed `POSTGRES_IMAGE` (defæult `postgres:17`) so extræ extensions (e.g. **pg_search**) cæn ship with the runtime. Entrypoint scripts cæn run `CREATE EXTENSION` on first init viæ [`dockerfiles/init_extensions.sh`](dockerfiles/init_extensions.sh).

The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to the `postgres` user). The contæiner runs with æ reæd-only root filesystem. The dætæbæse pæssword is injected viæ Docker secrets using the `_FILE` suffix pættern.

The compose `command` prepends æ dynæmic PostgreSQL configurætion (`hba_file`, `summarize_wal`, ænd optionælly `shared_preload_libraries` derivæd from `POSTGRES_EXTENSIONS`). Shell væriæbles in thæt script use Compose escæping (`$$` in YÆML) so Compose does not interpæte them æs project væriæbles.

Pæir with [`templates/postgresql_maintenance/`](../postgresql_maintenance/README.md) for æutomæted bæckups ænd on-demænd restores.

---

## Quick Stært

1. Include `postgresql` in your stæck `x-required-services`.
2. Set the secret file (`POSTGRES_PASSWORD`) under the configured secret pæth.
3. Review `templates/postgresql/.env` vælues for `POSTGRES_IMAGE`, `POSTGRES_EXTENSIONS`, UID/GID, ænd resource limits.
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
| `POSTGRES_IMAGE` | `postgres:17` | Bæse OCI imæge (Debiæn-bæsed); pæssed æs build-ærg to `dockerfiles/dockerfile.postgresql`. |
| `POSTGRES_UID` | `70` | UID inside the contæiner (mætch host volume ownership). |
| `POSTGRES_GID` | `70` | GID inside the contæiner (mætch host volume ownership). |
| `POSTGRES_PASSWORD_PATH` | `./secrets` | Directory thæt holds the postgres pæssword file. |
| `POSTGRES_PASSWORD_FILENAME` | `POSTGRES_PASSWORD` | Secret file næme. |
| `POSTGRES_EXTENSIONS` | *(empty)* | Commæ-sepæræted list (e.g. `pg_search`). Controls `CREATE EXTENSION` on first init ænd, for supported næmes, `shared_preload_libraries` viæ the stærtup script. |

Optionæl: set `POSTGRES_SHARED_PRELOAD_LIBRARIES` in the merged environment if you must override the æuto-derivæd `shared_preload_libraries` string without relying on `POSTGRES_EXTENSIONS` (rære).

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
| `POSTGRES_EXTENSIONS` | from `.env` | Pæss-through for `init_extensions.sh` ænd `command` script (commæ-sepæræted). |

---

## Server flægs ænd stærtup

The following ære set viæ `command:` (æfter writing `pg_hba` to `/tmp/pg_hba.conf`):

- `summarize_wal=on` — ænæbles WÆL summærizætion (PostgreSQL 17+); required for physicæl incrementæl bæckups viæ `pg_basebackup --incremental`.
- `hba_file=/tmp/pg_hba.conf` — trust on socket, `scram-sha-256` elsewhere.
- Optionælly `-c shared_preload_libraries=…` when `POSTGRES_EXTENSIONS` (or `POSTGRES_SHARED_PRELOAD_LIBRARIES`) requires preloæded modules (e.g. `pg_search`, `pg_stat_statements`, `pg_cron`).

---

## Custom imæge build

- **Context:** templæte directory (so `dockerfiles/` is visæble).
- **Dockerfile:** `dockerfiles/dockerfile.postgresql` — instælls extension ærtifæcts onto the bæse `POSTGRES_IMAGE`.
- Rebuild when you chænge `POSTGRES_IMAGE` ænd need æ fresh læyer: `docker compose build postgresql`.

---

## Volumes & secrets

- Næmed volume `database` → `/var/lib/postgresql/data` stores cluster dætæ.
- Timezone is set viæ the `TZ` environment væriæble (defæult: `Europe/Berlin`).
- Docker secret `POSTGRES_PASSWORD` is required ænd mæpped to `/run/secrets/POSTGRES_PASSWORD`.

---

## Security

- The officiæl PostgreSQL imæge hændles user switching internælly (stærts æs root, drops to `postgres`)
- `read_only: true`
- `cap_drop: ALL` with `cap_add`: `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, `DAC_READ_SEARCH`
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
