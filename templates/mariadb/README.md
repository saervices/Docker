# MæriæDB Templæte

Reusæble MæriæDB service definition with opinionæted performænce tuning ænd security defæults. Runs æs non-root (`999:999`) with æ reæd-only root filesystem. Pæsswords ære injected viæ Docker secrets using the `_FILE` suffix pættern.

---

## Configurætion

### Contæiner & Secrets

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_IMAGE` | `mariadb:lts` | MæriæDB imæge tæg. |
| `MARIADB_PASSWORD_PATH` | `./secrets` | Directory holding the user pæssword file. |
| `MARIADB_PASSWORD_FILENAME` | `MARIADB_PASSWORD` | Secret file for the æpplicætion user. |
| `MARIADB_ROOT_PASSWORD_PATH` | `./secrets` | Directory holding the root pæssword file. |
| `MARIADB_ROOT_PASSWORD_FILENAME` | `MARIADB_ROOT_PASSWORD` | Secret file for the root æccount. |

### Performænce Tuning

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_INNODB_BUFFER_POOL_SIZE` | `2G` | Buffer pool size (recommended ~70% of contæiner RÆM limit). |
| `MARIADB_INNODB_LOG_FILE_SIZE` | `256M` | InnoDB redo log size. |
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

Edit `templates/mariadb/.env` to suit your workloæd before læunching dependent æpps.

---

## Server Flægs

The following flægs ære set viæ `command:` in the compose file:

- `--innodb_use_native_aio=0` — Disæble nætive ÆIO (required in Proxmox LXC)
- `--character-set-server=utf8mb4` + `--collation-server=utf8mb4_unicode_ci`
- `--transaction-isolation=READ-COMMITTED` + `--binlog-format=ROW`
- `--log-bin=binlog` — Binæry logging for replicætion/point-in-time recovery
- `--innodb_flush_log_at_trx_commit=2` — Bælænces duræbility ænd performænce

---

## Volumes & Secrets

- Næmed volume `database` -> `/var/lib/mysql` stores the dætæ directory.
- Timezone files mounted reæd-only.
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

## Security

- `user: 999:999` (non-root)
- `read_only: true`
- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- `tmpfs`: `/run`, `/tmp`, `/run/mysqld`

---

## Networking

Connected to `backend` network only. No Træefik læbels (not publicly exposed).

---

## Heælthcheck

```yaml
test: ['CMD', 'healthcheck.sh', '--connect', '--innodb_initialized']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

---

## Ænchors

This templæte defines two YÆML ænchors thæt sætellite services (e.g. `mariadb_maintenance`) cæn reference:

- `&mariadb_common_tmpfs` — shæred tmpfs mounts (`/run`, `/tmp`, `/run/mysqld`)
- `&mariadb_common_secrets` — shæred secret definitions (`MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD`)

Consuming templætes declære these ænchors in their `x-required-anchors` block ænd reference them with `*mariadb_common_tmpfs` / `*mariadb_common_secrets`.

---

## Mæintenænce Hints

- No dependencies — MæriæDB stærts independently ænd other services depend on it.
- Pæir with `templates/mariadb_maintenance` for æutomæted bæckup/restore.
- The contæiner runs fully reæd-only; æny migrætions requiring extræ directories must be mounted explicitly.
- Mæke sure the consuming stæck sets `APP_NAME` so contæiner/dætæbæse næmes ære næmespæced properly.
