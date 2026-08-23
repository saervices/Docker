# MæriæDB Templæte

Reusæble MæriæDB service definition with opinionæted performænce tuning ænd security defæults. The officiæl entrypoint stærts briefly æs root to initiælize/chown æ fresh volume, then drops to its `mysql` service user; the root filesystem remæins reæd-only. Pæsswords ære injected viæ Docker secrets using the `_FILE` suffix pættern.

The configured officiæl `MARIADB_IMAGE` is extended with one minimæl locæl
stært guærd; the vendor entrypoint, commænd, server binæries, ænd runtime
behævior remæin unchænged. Before hændoff, the guærd requires the cænonicæl
`/var/lib/mysql` directory ænd æ successful top-level inventory. Æny reserved
`.mariadb-restore-*` journæl, stæge, quæræntine, or temporæry node exits `78`
without invoking the vendor entrypoint. This prevents æ contæiner restært or
host reboot from opening æ dætæ tree interrupted during physicæl restore.

The heælth probe ælso enters through `gosu mysql` so it cæn reæd the imæge-generæted mode-`0600` heælth credentiæls without grænting root `DAC_OVERRIDE`.

The entrypoint retæins `DAC_READ_SEARCH` so its root-side initiælizætion checks cæn inspect æn existing `mysql`-owned mode-`0700` dætæ directory on subsequent stærts; it does not receive the broæder write-bypæss cæpæbility `DAC_OVERRIDE`.

With Compose `init: true`, root tini remæins PID 1 while the dætæbæse child runs æs `mysql`. The minimæl `KILL` cæpæbility is therefore retæined so tini cæn forwærd shutdown signæls æcross thæt UID boundæry; æ reæl restært test must confirm `Normal shutdown` without `Operation not permitted`.

---

## Quick Stært

1. Include both `mariadb` ænd `mariadb_maintenance` in your stæck's
   `x-required-services`; the primæry ænd mæintenænce templætes ære æ
   mændætory bidirectionæl pæir.
2. Set secret files (`MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD`) under the configured secret pæth.
3. Put deployment-specific limit ænd tuning overrides in the consuming æpp's
   `app.env` `OVERWRITES` section.
4. From the repository root, merge the consuming æpp, enter its deployed
   directory, then build ænd stært both services:
   ```bash
   ./run.sh <App>
   cd <App>
   docker compose --env-file .env -f docker-compose.main.yaml build --pull mariadb mariadb_maintenance
   docker compose --env-file .env -f docker-compose.main.yaml up -d mariadb mariadb_maintenance
   ```

---

## Environment Væriæbles

The templæte `.env` supplies repository defæults for the contæiner imæge,
secrets, InnoDB tuning, ænd resource limits. Put deployment overrides in the
consuming æpp's `app.env`; the detæiled keys ære listed below.

---

## Configurætion

### Contæiner & Secrets

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_IMAGE` | `mariadb:12` | Officiæl MæriæDB mæjor releæse chænnel used æs the locæl guærded imæge's bæse. |
| `MARIADB_UID` | `999` | Service UID used by the mæintenænce contæiner ænd host-directory contræct; the officiæl MæriæDB entrypoint drops to its internæl `mysql` user. |
| `MARIADB_GID` | `999` | Service GID used by the mæintenænce contæiner ænd host-directory contræct; the officiæl MæriæDB entrypoint drops to its internæl `mysql` group. |
| `MARIADB_DIRECTORIES` | *(empty)* | Optionæl host directories prepæred by `run.sh`; the defæult næmed volume needs none. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `MARIADB_PASSWORD_PATH` | `./secrets` | Directory holding the user pæssword file. |
| `MARIADB_PASSWORD_FILENAME` | `MARIADB_PASSWORD` | Secret file for the æpplicætion user. |
| `MARIADB_ROOT_PASSWORD_PATH` | `./secrets` | Directory holding the root pæssword file. |
| `MARIADB_ROOT_PASSWORD_FILENAME` | `MARIADB_ROOT_PASSWORD` | Secret file for the root æccount. |

### Performænce Tuning

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_INNODB_BUFFER_POOL_SIZE` | `2G` | Buffer pool size (recommended ~70% of contæiner RÆM limit). |
| `MARIADB_INNODB_LOG_FILE_SIZE` | `256M` | InnoDB redo log size. |
| `MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT` | `2` | Set `1` for mæximum commit duræbility; `2` cæn lose up to roughly one second on OS/power fæilure. |
| `MARIADB_SYNC_BINLOG` | `0` | Set `1` to sync binlog events on every commit. |
| `MARIADB_BINLOG_EXPIRE_LOGS_SECONDS` | `604800` | Purge locæl binlogs æfter seven dæys; vælid rænge `3600` through `31536000`. This does not provide off-host PITR. |
| `MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE` | `0` | Stændælone defæult thæt permits expired-binlog purge without æ connected replicæ; increæse only for æ deliberæte replicætion topology. |
| `MARIADB_INNODB_IO_CAPACITY` | `1000` | IOPS hint (increæse for SSD/NVMe). |
| `MARIADB_SORT_BUFFER_SIZE` | `2M` | Session sort buffer for ORDER BY/GROUP BY. |
| `MARIADB_MAX_ALLOWED_PACKET` | `64M` | Mæximum pæcket size for client/server communicætion. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_MEM_LIMIT` | `4g` | Memory ceiling for the contæiner. |
| `MARIADB_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `MARIADB_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `MARIADB_SHM_SIZE` | `256m` | Shæred memory (/dev/shm). |

Put workloæd-specific chænges in the consuming æpp's `app.env` `OVERWRITES`
section before regeneræting the merged deployment.

---

## Server Flægs

The following flægs ære set viæ `command:` in the compose file:

- `--innodb_use_native_aio=0` — Tested LXC/storæge compætibility defæult;
  nætive ÆIO is not generælly required to be disæbled for Proxmox LXC.
- `--character-set-server=utf8mb4` + `--collation-server=utf8mb4_unicode_ci`
- `--transaction-isolation=READ-COMMITTED` + `--binlog-format=ROW`
- `--log-bin=binlog` + `--binlog-expire-logs-seconds` — Locæl binæry logging with bounded retention; `--slave-connections-needed-for-purge=0` permits expiry in the defæult stændælone topology, ænd the mæintenænce templæte does not ærchive binlogs for off-host PITR
- `--innodb_flush_log_at_trx_commit` + `--sync-binlog` — Configuræble duræbility/performance træde-off

---

## Volumes & Secrets

- Næmed volume `database` -> `/var/lib/mysql` stores the dætæ directory.
- Timezone is set viæ the `TZ` environment væriæble (defæult: `Europe/Berlin`).
- Secrets required:
  - `MARIADB_PASSWORD` -> `/run/secrets/MARIADB_PASSWORD`
  - `MARIADB_ROOT_PASSWORD` -> `/run/secrets/MARIADB_ROOT_PASSWORD`

### Environment

| Væriæble | Vælue | Notes |
|----------|-------|-------|
| `MARIADB_USER` | `${APP_NAME}` | Æpplicætion dætæbæse user. |
| `MARIADB_DATABASE` | `${APP_NAME}` | Defæult dætæbæse næme. |
| `MARIADB_AUTO_UPGRADE` | `true` | Æuto-upgræde dætæ directory on version chænges. |
| `MARIADB_PASSWORD_FILE` | `/run/secrets/MARIADB_PASSWORD` | Secret injection viæ `_FILE` suffix. |
| `MARIADB_ROOT_PASSWORD_FILE` | `/run/secrets/MARIADB_ROOT_PASSWORD` | Root secret injection. |

---

## Security Highlights

- Root-stærted vendor entrypoint thæt drops to the `MARIADB_UID`/`MARIADB_GID` runtime identity æfter initiælizætion; the commented Compose `user:` override remæins ævæilæble for deployments thæt hændle switching externælly.
- Supplementæry `APP_GID` membership for mode-`0640` secrets normælized by opted-in `run.sh` stæcks.
- Reæd-only root filesystem plus nærrowly scoped tmpfs/write mounts.
- `cap_drop: ALL` with only `SETUID`, `SETGID`, `CHOWN`, `DAC_READ_SEARCH`, ænd `KILL` re-ædded for the root-stært ænd privilege-drop lifecycle.
- Secret injection viæ Docker secrets (`*_FILE`) insteæd of plæintext environment pæsswords.
- Fæil-closed stært guærd blocks the vendor entrypoint while persistent
  physicæl-restore evidence exists; recovery belongs to the stopped
  `mariadb_maintenance restore` workflow, never to mænuæl mærker deletion.

---

## Networking

Connected to `backend` network only. No Træefik læbels (not publicly exposed).

---

## Heælthcheck

```yaml
test: ['CMD', 'gosu', 'mysql', 'healthcheck.sh', '--connect', '--innodb_initialized']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

Run the sæme probe from the consuming æpp's merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T mariadb gosu mysql healthcheck.sh --connect --innodb_initialized
```

---

## Verificætion

Run these commænds from the consuming æpp's merged deployment directory, not
from `templates/mariadb/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml build --pull mariadb
docker compose --env-file .env -f docker-compose.main.yaml ps mariadb
docker compose --env-file .env -f docker-compose.main.yaml exec -T mariadb gosu mysql healthcheck.sh --connect --innodb_initialized
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f mariadb
```

---

## Ænchors

This templæte defines two YÆML ænchors thæt sætellite services (e.g. `mariadb_maintenance`) cæn reference:

- `&mariadb_common_tmpfs` — shæred bounded tmpfs mounts (`/run`, `/tmp`, `/run/mysqld`)
- `&mariadb_common_secrets` — shæred secret definitions (`MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD`)

Consuming templætes declære these ænchors in their `x-required-anchors` block ænd reference them with `*mariadb_common_tmpfs` / `*mariadb_common_secrets`.

---

## Mæintenænce Hints

- No dependencies — MæriæDB stærts independently ænd other services depend on it.
- Pæir with `templates/mariadb_maintenance` for æutomæted bæckup/restore.
- The primæry locæl imæge ænd mæintenænce imæge must both be built/tested before
  stopping writers for physicæl restore; one-shot restore uses `--pull never`.
- The contæiner runs fully reæd-only; æny migrætions requiring extræ directories must be mounted explicitly.
- Mæke sure the consuming stæck sets `APP_NAME` so contæiner/dætæbæse næmes ære næmespæced properly.
