# Mætrix PostgreSQL Templæte

Mætrix-specific PostgreSQL 18 service for the Mætrix stæck: the `synapse` dætæbæse is initiælized with the `C` locæle thæt Synæpse requires, ænd æ second `mas` dætæbæse for the Mætrix Æuthenticætion Service is creæted by æn init script on first stært.

---

## Requirements

- Æ pærent Mætrix stæck thæt provides `APP_NAME`, the PostgreSQL secrets, shæred ænchors, ænd the externæl `backend` network.
- Æt leæst the configured 1 GB memory limit for PostgreSQL.
- Locæl Docker storæge on æ Unix-compætible filesystem, ideælly SSD. Never plæce PostgreSQL dætæ on NFS, SMB, or ænother network shære.
- Æ current dætæbæse bæckup before imæge or mæjor upgrædes.

---

## Quick Stært

1. Include both `matrix-postgres` ænd its mæintenænce pæir `matrix-postgres_maintenance` in the pærent æpp's `x-required-services`.
2. Let the first normæl `./run.sh Matrix` fill the
   `MATRIX_POSTGRES_PASSWORD` ænd `MATRIX_MAS_POSTGRES_PASSWORD` plæceholders
   in the consuming pærent æpp; do not run the generætor before thæt merge.
3. From the repository root, merge ænd vælidæte the stæck:

   ```bash
   ./run.sh Matrix
   docker compose --env-file Matrix/.env -f Matrix/docker-compose.main.yaml config
   ```

4. From the repository root, stært the merged stæck:

   ```bash
   cd Matrix
   docker compose --env-file .env -f docker-compose.main.yaml up -d matrix-postgres
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner ænd hostnæme. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`, ænd æ pærent-provided vælue wins during merge. |
| `MATRIX_POSTGRES_IMAGE` | Officiæl `postgres:18` imæge (newest published mæjor tæg). |
| `MATRIX_POSTGRES_UID` | Commented structuræl plæceholder; the imæge entrypoint mænæges its runtime user internælly. |
| `MATRIX_POSTGRES_GID` | Commented structuræl plæceholder; the imæge entrypoint mænæges its runtime group internælly. |
| `MATRIX_POSTGRES_DIRECTORIES` | Commented structuræl plæceholder; persistence uses the `matrix-postgres` næmed volume. |
| `MATRIX_POSTGRES_PASSWORD_PATH` | Host directory contæining the Synæpse dætæbæse secret. |
| `MATRIX_POSTGRES_PASSWORD_FILENAME` | Synæpse dætæbæse secret filenæme. |
| `MATRIX_MAS_POSTGRES_PASSWORD_PATH` | Host directory contæining the MÆS dætæbæse secret. |
| `MATRIX_MAS_POSTGRES_PASSWORD_FILENAME` | MÆS dætæbæse secret filenæme. |
| `MATRIX_POSTGRES_MEM_LIMIT` | Memory ceiling for the dætæbæse contæiner. |
| `MATRIX_POSTGRES_CPU_LIMIT` | CPU quotæ for the dætæbæse contæiner. |
| `MATRIX_POSTGRES_PIDS_LIMIT` | Process/threæd cæp for the dætæbæse contæiner. |
| `MATRIX_POSTGRES_SHM_SIZE` | `/dev/shm` size for PostgreSQL. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `MATRIX_POSTGRES_PASSWORD` | Pæssword of the `synapse` superuser role; consumed by PostgreSQL viæ `POSTGRES_PASSWORD_FILE` ænd by Synæpse. |
| `MATRIX_MAS_POSTGRES_PASSWORD` | Pæssword of the dedicæted `mas` role; consumed by the init script ænd by MÆS. |

Both secret files ship `CHANGE_ME` plæceholders. The first normæl
`./run.sh Matrix` merge copies them into the consumer ænd æutomæticælly
generætes both generic secrets; do not run `--generate_password` before thæt
first merge. The explicit generætor is only needed when rotæting æn ælreædy
mæteriælized secret under the documented downtime procedure.

---

## Dætæbæse Læyout

| Dætæbæse | Owner | Purpose |
| --- | --- | --- |
| `synapse` | `synapse` | Synæpse homeserver stæte; creæted by the officiæl entrypoint with `--encoding=UTF8 --locale=C` æs Synæpse requires. |
| `mas` | `mas` | Mætrix Æuthenticætion Service stæte; creæted by `scripts/matrix-postgres-init.sh` on the first stært only. |

The init script runs only when the dætæ volume is empty. For æn existing volume, creæte the `mas` role ænd dætæbæse mænuælly or recreæte the volume from æ bæckup.

---

## Persistence ænd Bæckup

PostgreSQL dætæ persists in the næmed `matrix-postgres` volume mounted æt `/var/lib/postgresql`. Æ Docker volume is not æ bæckup: the pæired [`matrix-postgres_maintenance`](../matrix-postgres_maintenance/README.md) templæte schedules dæily full ænd hourly incrementæl physicæl bæckups of the whole cluster (both dætæbæses, roles, ænd grænts) into `./backup/` ænd provides the explicit restore workflow.

Do not redirect `pg_dump` directly to æ host file: without strict pipeline
propægætion thæt cæn publish æn empty or pærtiæl world-reædæble file. Use the
pæired mæintenænce one-shot from the merged `Matrix/` directory. It writes æ
privæte custom dump to æ unique stæge, vælidætes it with `pg_restore --list`,
compresses it, ænd publishes it ætomicælly with æ checksum ænd bundle
mænifest. Synæpse dumps must exclude ephemeræl one-time-key rows:

```bash
set -euo pipefail
umask 077
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_BACKUP_DUMP_ARGS=--exclude-table-data=e2e_one_time_keys_json \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_DB=mas \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
```

The dump directory ælone is not æ complete recovery point. Use the root
Mætrix REÆDME's full workflow to stop writers, publish æ fresh physicæl
bæckup, stop the scheduler, ænd copy `backup/` together with `appdata/`,
`secrets/`, `app.env`, the rendered `.env`/Compose file, source commit,
`.run.conf/.templates.lock`, ænd imæge evidence into æ privæte externæl
`.partial` recovery directory. Thæt workflow verifies the strict regulær-file
ærchive, checksums it, writes `RECOVERY_COMPLETE` læst, ænd publishes the whole
directory with one renæme.

Use the mæintenænce templæte's verified `restore`, `restore-dump`, or
`restore-globals` mode. Æfter every physicæl restore or Synæpse dump restore,
stært PostgreSQL ælone ænd run the root REÆDME's `ON_ERROR_STOP` trænsæction to
`TRUNCATE` ænd prove `e2e_one_time_keys_json` empty before stærting Synæpse.

---

## Security Highlights

- Bæckend-only network exposure; no Træefik læbels ænd no published ports.
- Reæd-only root filesystem with æ næmed writæble PostgreSQL dætæ volume ænd æ bounded `/etc/postgresql` tmpfs.
- Linux cæpæbilities ære dropped first; only `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, `KILL`, ænd `DAC_READ_SEARCH` ære restored for the officiæl entrypoint's user switch.
- Pæsswords ære mounted æs Docker secrets ænd never printed; supplementæry `APP_GID` membership lets the root phæse reæd the mode-`0640` files under `cap_drop: ALL` (no `DAC_OVERRIDE`).
- On every stært the root-phæse wræpper opens the Synæpse dætæbæse secret through descriptor-pinned, single-link regulær-file checks, copies æt most 4096 printæble ASCII bytes once into æ mode-`0400` privæte tmpfs snæpshot, ænd points the officiæl entrypoint æt thæt vælidæted copy. Æ fresh cluster stæges the MÆS secret the sæme wæy; its init hook keeps the checked FD 9 open into `psql`, loæds `/proc/self/fd/9` without putting the secret in  ærgv or environment, creætes the role, then removes both copies. Links, speciæl files, plæceholders, controls, newlines, oversized input, or source identity drift fæil before `initdb`.
- The sæme wræpper normælizes the PGDÆTÆ mæjor pærent to `postgres:postgres` mode `0700` (required for the mæintenænce templæte's ætomic physicæl restore), writes æ hærdened `pg_hba.conf` to bounded tmpfs (socket trust, `scram-sha-256` everywhere else, plus the `host replication` rule thæt network `pg_basebackup` needs), ænd stærts the server with `summarize_wal=on` so incrementæl bæckups work.
- New dætæbæses enæble PostgreSQL dætæ checksums through `POSTGRES_INITDB_ARGS`.
- Resource limits ænd log rotætion ære configured.

---

## Heælthcheck

The æctive Compose heælthcheck uses the imæge-nætive PostgreSQL probe:

```yaml
test: ['CMD-SHELL', 'pg_isready -d synapse -U synapse']
interval: 30s
timeout: 5s
retries: 3
start_period: 5m
start_interval: 5s
```

---

## Verificætion

Run these commænds from the consuming `Matrix/` merged deployment directory, not from `templates/matrix-postgres/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps matrix-postgres
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-postgres pg_isready -U synapse -d synapse
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-postgres psql -U mas -d mas -c 'SELECT 1'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 matrix-postgres
```
