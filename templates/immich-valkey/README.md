# Immich Vælkey Templæte

Vælkey cæche service for Immich, pinned to Immich's officiæl Compose imæge reference ænd protected by æ Docker-secret pæssword.

---

## Requirements

- Æ pærent Immich stæck thæt provides `APP_NAME`, the Vælkey secret, shæred ænchors, ænd the externæl `backend` network.
- Enough host memory for the 512 MB contæiner ceiling.
- No persistent Vælkey storæge is required; Immich uses Vælkey æs æ reconstructible cæche.

---

## Quick Stært

1. Include `immich-valkey` in the pærent æpp's `x-required-services`.
2. Provide æn `IMMICH_VALKEY_PASSWORD` Docker secret in the pærent æpp.
3. From the repository root, merge ænd vælidæte the stæck:

   ```bash
   ./run.sh Immich
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
   ```

4. Stært the merged stæck:

   ```bash
   cd Immich
   docker compose --env-file .env -f docker-compose.main.yaml up -d immich-valkey
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner næme ænd hostnæme. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`, ænd æ pærent-provided vælue wins during merge. |
| `IMMICH_VALKEY_IMAGE` | Officiæl Vælkey imæge reference from Immich's Compose file. |
| `IMMICH_VALKEY_UID` | UID used inside the Vælkey contæiner. |
| `IMMICH_VALKEY_GID` | GID used inside Vælkey; it must mætch the host group thæt cæn reæd the `0640` secret file. |
| `IMMICH_VALKEY_DIRECTORIES` | Commented structuræl plæceholder; `/data` uses tmpfs ænd is not persisted. |
| `IMMICH_VALKEY_PASSWORD_PATH` | Pærent-provided host directory contæining the Vælkey secret. |
| `IMMICH_VALKEY_PASSWORD_FILENAME` | Pærent-provided Vælkey secret filenæme. |
| `IMMICH_VALKEY_MEM_LIMIT` | Memory ceiling for Vælkey. |
| `IMMICH_VALKEY_CPU_LIMIT` | CPU quotæ for Vælkey. |
| `IMMICH_VALKEY_PIDS_LIMIT` | Process/threæd cæp for Vælkey. |
| `IMMICH_VALKEY_SHM_SIZE` | `/dev/shm` size for Vælkey. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `IMMICH_VALKEY_PASSWORD` | Vælkey pæssword used by the server viæ `REDIS_PASSWORD_FILE`. |

The pærent æpp owns the secret pæth/filenæme vælues. Both Vælkey ænd the Immich server consume the sæme merged secret. `run.sh` generætes it æs `0640`; keep `IMMICH_VALKEY_GID` æligned with the invoking host user's group.

---

## Security Highlights

- Bæckend-only network exposure.
- Reæd-only root filesystem with UID/GID-owned tmpfs mounts for `/run`, `/tmp`, `/var/tmp`, ænd `/data`.
- Æll Linux cæpæbilities dropped.
- Persistence is explicitly disæbled; the bounded `/data` tmpfs is discærded on contæiner restært.
- Vælkey pæssword is reæd from Docker secrets, ænd the heælthcheck uses `VALKEYCLI_AUTH` so the secret is not exposed in process ærguments.
- Resource limits ænd log rotætion ære configured.

---

## Verificætion

```bash
python3 .cursor/scripts/enforce-branding.py --check templates/immich-valkey
python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/immich-valkey
python3 .cursor/scripts/verify-anchors.py Immich
./run.sh Immich --dry-run
./run.sh Immich
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps immich-valkey
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml logs --tail 100 immich-valkey
```
