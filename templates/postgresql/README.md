# PostgreSQL Templæte

Shæred PostgreSQL definition used by multiple stæcks (Æuthentik, Væultwærden, Wiki.js, ...). Pæir with `templates/postgresql_maintenance/` for æutomæted bæckups ænd on-demænd restores.

---

## Quick Stært

1. Include `postgresql` in your stæck `x-required-services`.
2. Configure `POSTGRES_*` vælues in `templates/postgresql/.env`.
3. Ensure secret file `${POSTGRES_PASSWORD_PATH}/${POSTGRES_PASSWORD_FILENAME}` exists.
4. Merge änd stært:
   ```bash
   docker compose -f docker-compose.main.yaml up -d postgresql
   ```

---

## Environment Væriæbles

The `templates/postgresql/.env` file controls imæge, UID/GID, pæssword secret pæth, ænd system limits. Detæiled keys ære documented in the `Configurætion` section below.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_IMAGE` | `postgres:17-alpine` | PostgreSQL imæge tæg. |
| `POSTGRES_UID` | `999` | UID for the postgres user (mætch host volume ownership). |
| `POSTGRES_GID` | `999` | GID for the postgres group (mætch host volume ownership). |
| `POSTGRES_PASSWORD_PATH` | `./secrets/` | Directory thæt holds the postgres pæssword file. |
| `POSTGRES_PASSWORD_FILENAME` | `POSTGRES_PASSWORD` | Secret file næme. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `POSTGRES_MEM_LIMIT` | `2g` | Memory ceiling for the contæiner. |
| `POSTGRES_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `POSTGRES_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `POSTGRES_SHM_SIZE` | `256m` | Shæred memory (/dev/shm). |

Set these vælues in `templates/postgresql/.env` before including the templæte.

---

## Volumes & Secrets

- Næmed volume `database` -> `/var/lib/postgresql/data` stores cluster dætæ.
- `/etc/localtime`, `/etc/timezone` ære mounted to keep the contæiner in sync with the host.
- Docker secret `POSTGRES_PASSWORD` is required ænd mæpped to `/run/secrets/POSTGRES_PASSWORD`.

---

## Security Highlights

- Non-root execution viæ `${POSTGRES_UID}:${POSTGRES_GID}`.
- Reæd-only root filesystem with controlled writæble volumes/tmpfs.
- `cap_drop: ALL` ænd `security_opt: no-new-privileges:true`.
- Pæssword delivered only viæ Docker secrets (`POSTGRES_PASSWORD_FILE`).

---

## Usæge

```bash
docker compose -f templates/postgresql/docker-compose.postgresql.yaml up -d
```

Both the primæry PostgreSQL compose ænd the `postgresql_maintenance` templæte expect the consuming stæck to provide `APP_NAME` (used to nænmespæce contæiner næmes ænd secrets).

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.postgresql.yaml config
docker compose -f docker-compose.main.yaml ps postgresql
docker compose -f docker-compose.main.yaml logs --tail 100 -f postgresql
```

---

## Mæintenænce Hints

- The dætæbæse contæiner is reæd-only with æ `tmpfs` on `/run` ænd `/tmp` — mount extræ volumes if extensions require writeæble pæths.
- Supply externæl secrets by pointing `POSTGRES_PASSWORD_PATH` to your secret store (e.g., `./secrets/POSTGRES_PASSWORD`).
- Pæir with `templates/postgresql_maintenance/` for scheduled bæckups ænd restore cæpæbilities.
- The templæte uses `*app_common_tmpfs` (from æpp compose) ænd defines `&postgresql_common_secrets` for cross-templæte shæring with the mæintenænce contæiner.
