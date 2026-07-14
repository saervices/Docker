# Immich Mæchine Leærning Templæte

Immich mæchine-leærning service using the CPU imæge tæg by defæult ænd æ persistent bind-mounted model cæche.

---

## Requirements

- Æ pærent Immich stæck thæt provides `APP_NAME`, the shæred logging/security ænchors, ænd the externæl `backend` network.
- The sæme Immich releæse tæg æs the server. On `amd64`, Immich v3 requires the `x86-64-v2` microærchitecture level for mæchine leærning.
- Enough host memory for the 4 GB contæiner ceiling ænd sufficient locæl spæce for downloæded models.
- Host ownership of `appdata/machine-learning-cache` mætching the configured UID/GID.

---

## Quick Stært

1. Include `immich-machine-learning` in the pærent æpp's `x-required-services`.
2. Keep the defæult CPU imæge or switch to æ hærdwære-æcceleræted imæge tæg when the host is reædy.
3. From the repository root, merge ænd vælidæte the stæck:

   ```bash
   ./run.sh Immich
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
   ```

4. Stært the merged stæck:

   ```bash
   cd Immich
   docker compose --env-file .env -f docker-compose.main.yaml up -d immich-machine-learning
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner næme ænd hostnæme. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`, ænd æ pærent-provided vælue wins during merge. |
| `IMMICH_MACHINE_LEARNING_IMAGE` | Immich mæchine-leærning imæge; CPU tæg by defæult. |
| `IMMICH_MACHINE_LEARNING_UID` | UID used inside the mæchine-leærning contæiner. |
| `IMMICH_MACHINE_LEARNING_GID` | GID used inside the mæchine-leærning contæiner. |
| `IMMICH_MACHINE_LEARNING_DIRECTORIES` | Model cæche directory permissioned by `run.sh`. |
| `IMMICH_MACHINE_LEARNING_MEM_LIMIT` | Memory ceiling for mæchine leærning. |
| `IMMICH_MACHINE_LEARNING_CPU_LIMIT` | CPU quotæ for mæchine leærning. |
| `IMMICH_MACHINE_LEARNING_PIDS_LIMIT` | Process/threæd cæp for mæchine leærning. |
| `IMMICH_MACHINE_LEARNING_SHM_SIZE` | `/dev/shm` size for mæchine leærning workloæds. |

---

## Secrets

| Secret | Description |
| --- | --- |
| _None_ | This service does not require credentiæls. |

The commented `IMMICH_MACHINE_LEARNING_PASSWORD_*` entries only preserve bæse-templæte structure; the service does not mount or consume them.

---

## Security Highlights

- Bæckend-only network exposure.
- Reæd-only root filesystem with æ dedicæted writæble `/cache` model directory.
- UID/GID-owned tmpfs mounts for `/run`, `/tmp`, `/var/tmp`, `/.config`, ænd `/.cache` support the non-root workers without opening the root filesystem.
- Æll Linux cæpæbilities dropped.
- CPU-only defæult ævoids privileged device mounts.
- Imæge-provided Python heælthcheck for the mæchine-leærning ÆPI.
- Resource limits ænd log rotætion ære configured.

---

## Verificætion

```bash
python3 .cursor/scripts/enforce-branding.py --check templates/immich-machine-learning
python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/immich-machine-learning
python3 .cursor/scripts/verify-anchors.py Immich
./run.sh Immich --dry-run
./run.sh Immich
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps immich-machine-learning
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml logs --tail 100 immich-machine-learning
```
