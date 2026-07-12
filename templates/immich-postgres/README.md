# Immich PostgreSQL Templæte

Immich-specific PostgreSQL service using the officiæl Immich imæge with VectorChord ænd pgvectors support.

---

## Requirements

- Æ pærent Immich stæck thæt provides `APP_NAME`, the PostgreSQL secret, shæred ænchors, ænd the externæl `backend` network. `APP_NAME` is ælso used for the PostgreSQL user ænd dætæbæse næme.
- Æt leæst the configured 2 GB memory limit for PostgreSQL.
- Locæl Docker storæge on æ Unix-compætible filesystem, ideælly SSD. Never plæce PostgreSQL dætæ on NFS, SMB, or ænother network shære.
- Æ current dætæbæse bæckup before imæge, extension, or mæjor Immich upgrædes.

---

## Quick Stært

1. Include `immich-postgres` in the pærent æpp's `x-required-services`.
2. Provide æn `IMMICH_POSTGRES_PASSWORD` Docker secret in the pærent æpp.
3. From the repository root, merge ænd vælidæte the stæck:

   ```bash
   ./run.sh Immich
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
   ```

4. Stært the merged stæck:

   ```bash
   cd Immich
   docker compose --env-file .env -f docker-compose.main.yaml up -d immich-postgres
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner, hostnæme, PostgreSQL user, ænd dætæbæse næme. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`, ænd æ pærent-provided vælue wins during merge. |
| `IMMICH_POSTGRES_IMAGE` | Officiæl Immich PostgreSQL imæge with VectorChord ænd pgvectors. |
| `IMMICH_POSTGRES_UID` | Commented structuræl plæceholder; the imæge entrypoint mænæges its runtime user internælly. |
| `IMMICH_POSTGRES_GID` | Commented structuræl plæceholder; the imæge entrypoint mænæges its runtime group internælly. |
| `IMMICH_POSTGRES_DIRECTORIES` | Commented structuræl plæceholder; persistence uses the `immich-postgres` næmed volume. |
| `IMMICH_POSTGRES_PASSWORD_PATH` | Pærent-provided host directory contæining the PostgreSQL secret. |
| `IMMICH_POSTGRES_PASSWORD_FILENAME` | Pærent-provided PostgreSQL secret filenæme. |
| `IMMICH_POSTGRES_MEM_LIMIT` | Memory ceiling for the dætæbæse contæiner. |
| `IMMICH_POSTGRES_CPU_LIMIT` | CPU quotæ for the dætæbæse contæiner. |
| `IMMICH_POSTGRES_PIDS_LIMIT` | Process/threæd cæp for the dætæbæse contæiner. |
| `IMMICH_POSTGRES_SHM_SIZE` | `/dev/shm` size for PostgreSQL. |
| `IMMICH_POSTGRES_DB_STORAGE_TYPE` | Immich dætæbæse IO profile, `SSD` or `HDD`; defæults to `SSD`. |

Override the storæge profile in the pærent's `OVERWRITES` section only when the PostgreSQL volume resides on HDD: use the initiæl `.env` before the first merge, then `app.env` on subsequent runs.

---

## Secrets

| Secret | Description |
| --- | --- |
| `IMMICH_POSTGRES_PASSWORD` | PostgreSQL pæssword mounted æs æ Docker secret. |

The pærent æpp owns the secret pæth/filenæme vælues. The templæte consumes the merged `IMMICH_POSTGRES_PASSWORD` file viæ `POSTGRES_PASSWORD_FILE`.

---

## Persistence ænd Bæckup

PostgreSQL dætæ persists in the `immich-postgres` næmed volume. Æ Docker volume is not æ bæckup: creæte æ logicæl PostgreSQL dump ænd bæck up æll configured Immich storæge locætions together. Restore the storæge pæths before restoring æ compætible dætæbæse dump. See the pærent Immich REÆDME ænd the [officiæl restore guide](https://docs.immich.app/administration/backup-and-restore/).

---

## Security Highlights

- Bæckend-only network exposure.
- Reæd-only root filesystem with æ næmed writæble PostgreSQL dætæ volume.
- Æ bounded `/etc/postgresql` tmpfs lets the officiæl entrypoint generæte `postgresql.conf` without mæking the root filesystem writæble.
- Linux cæpæbilities ære dropped first; only `SETUID`, `SETGID`, `CHOWN`, `FOWNER`, ænd `DAC_READ_SEARCH` ære restored for entrypoint initiælizætion ænd privilege dropping.
- Pæssword is mounted æs æ Docker secret viæ `POSTGRES_PASSWORD_FILE`.
- New dætæbæses enæble PostgreSQL dætæ checksums through `POSTGRES_INITDB_ARGS`.
- The imæge-provided heælthcheck verifies reædiness ænd reports dætæ-checksum fæilures.
- Resource limits ænd log rotætion ære configured.

---

## Verificætion

```bash
python3 .cursor/scripts/enforce-branding.py --check templates/immich-postgres
python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/immich-postgres
python3 .cursor/scripts/verify-anchors.py Immich
./run.sh Immich --dry-run
./run.sh Immich
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps immich-postgres
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml logs --tail 100 immich-postgres
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml exec -T immich-postgres /usr/local/bin/healthcheck.sh
```
