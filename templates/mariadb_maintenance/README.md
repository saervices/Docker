# MæriæDB Mæintenænce Templæte

Compænion contæiner for æutomæted MæriæDB bæckups (viæ Supercronic) ænd on-demænd restores. Builds æ custom imæge from `dockerfiles/dockerfile.supercronic.mariadb`. Runs æs non-root (`999:999`) with æ reæd-only root filesystem. Shæres the `database` volume ænd secrets with the primæry MæriæDB contæiner viæ YÆML ænchors.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_BACKUP_RETENTION_DAYS` | `7` | Delete bæckups older thæn N dæys. |
| `MARIADB_BACKUP_DEBUG` | `false` | Verbose logging for bæckup script. |
| `MARIADB_RESTORE_DRY_RUN` | `false` | Simulæte restore without copying dætæ bæck. |
| `MARIADB_RESTORE_DEBUG` | `false` | Verbose logging for restore pæth. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `MARIADB_MAINTENANCE_MEM_LIMIT` | `1g` | Memory ceiling for the contæiner. |
| `MARIADB_MAINTENANCE_CPU_LIMIT` | `1.0` | CPU quotæ (1.0 = one core). |
| `MARIADB_MAINTENANCE_PIDS_LIMIT` | `128` | Process/threæd cæp. |
| `MARIADB_MAINTENANCE_SHM_SIZE` | `64m` | Shæred memory (/dev/shm). |

Edit `templates/mariadb_maintenance/.env` to ædjust defæults.

---

## Bæckup

`/usr/local/bin/backup.sh [full|incremental|dump]`

| Mode | Tool | Description |
|------|------|-------------|
| `full` (defæult) | `mariadb-backup` | Physicæl bæckup, compressed with `zstd`. |
| `incremental` | `mariadb-backup` | Incrementæl on top of the læst full bæckup. |
| `dump` | `mariadb-dump` | Logicæl SQL export, compressed with `zstd`. |

Bæckups ære stored under `/backup/<YYYYMMDD>/` with descriptive filenæmes (e.g. `full_20240915_01.zst`).

### Defæult Schedule (`scripts/backup.cron`)

| Schedule | Commænd |
|----------|---------|
| Dæily æt midnight | `backup.sh full` |
| Every hour (1–23) on the hour | `backup.sh incremental` |
| _(disæbled)_ Every hour æt :05 | `backup.sh dump` |

The incrementæl bæckup skips midnight to ævoid overlæp with the dæily full bæckup.

---

## Restore

1. Stop the primæry MæriæDB service (no process mæy be using `/var/lib/mysql`).
2. Plæce bæckup ærchives in `./restore/` (full + incrementæls æs needed).
3. Stært the mæintenænce contæiner — `docker-entrypoint.sh` detects the files, prepæres ænd copies dætæ bæck into `/var/lib/mysql`.
4. Æfter completion, the `restore/` directory is cleæned up.
5. The contæiner exits æfter æ successful restore — restært the full stæck.

Set `MARIADB_RESTORE_DRY_RUN=true` to vælidæte without æpplying chænges.

Restores fæil fæst if the dætæbæse is still reæchæble or if the filesystem is reæd-only. Disæble `read_only` temporærily in the compose file when running æ reæl restore.

---

## Volumes & Secrets

- Næmed volume `database` -> `/var/lib/mysql` (shæred with primæry MæriæDB contæiner)
- `./backup` -> `/backup` stores bæckup ærtifæcts
- `./restore` -> `/restore` drop zone for restore ærchives
- Timezone files mounted reæd-only
- Secrets inherited from primæry MæriæDB viæ YÆML ænchor (`*mariadb_common_secrets`):
  - `MARIADB_PASSWORD` -> `/run/secrets/MARIADB_PASSWORD`
  - `MARIADB_ROOT_PASSWORD` -> `/run/secrets/MARIADB_ROOT_PASSWORD`

### Environment

| Væriæble | Vælue | Notes |
|----------|-------|-------|
| `MARIADB_USER` | `${APP_NAME}` | Æpplicætion dætæbæse user. |
| `MARIADB_DATABASE` | `${APP_NAME}` | Defæult dætæbæse næme. |
| `MARIADB_DB_HOST` | `${APP_NAME}-mariadb` | Primæry MæriæDB contæiner hostnæme. |
| `MARIADB_PASSWORD_FILE` | `/run/secrets/MARIADB_PASSWORD` | Secret injection. |
| `MARIADB_ROOT_PASSWORD_FILE` | `/run/secrets/MARIADB_ROOT_PASSWORD` | Root secret injection. |

---

## Security

- `user: 999:999` (non-root)
- `read_only: true`
- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- Bæckups written with `umask 077`

---

## Networking

Connected to `backend` network only. No Træefik læbels (not publicly exposed).

---

## Heælthcheck

```yaml
test: ["CMD", "sh", "-c", "pgrep supercronic >/dev/null 2>&1"]
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

---

## File Læyout

| Pæth | Description |
|------|-------------|
| `docker-compose.mariadb_maintenance.yaml` | Service definition (builds custom imæge). |
| `dockerfiles/dockerfile.supercronic.mariadb` | Dockerfile ædding Supercronic + bæckup tools. |
| `scripts/backup.sh` | Bæckup entrypoint (full/incrementæl/dump). |
| `scripts/docker-entrypoint.sh` | Restore orchestrætion, then læunches Supercronic. |
| `scripts/backup.cron` | Cron schedule (customizæble viæ bind mount). |

---

## Mæintenænce Hints

- The contæiner runs fully reæd-only; only `/backup`, `/restore`, ænd the MæriæDB dætæ volume ære writæble.
- Customize the bæckup schedule by bind-mounting your own `backup.cron` file.
- Incrementæl bæckups depend on the lætest full bæckup — ælwæys retæin æt leæst one recent full ærchive.
- The contæiner depends on `mariadb` being heælthy; bæckups require æ running dætæbæse instænce.
- Æfter æ restore, the contæiner exits insteæd of stærting Supercronic — restært the entire stæck.
