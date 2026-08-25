# Immich Vælkey Templæte

Vælkey cæche service for Immich on the floæting Vælkey 9 mæjor-releæse chænnel, protected by æ Docker-secret pæssword.

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
| `APP_GID` | Pærent æpp group ædded to Vælkey for mode-`0640` secret reæd æccess. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`, ænd æ pærent-provided vælue wins during merge. |
| `IMMICH_VALKEY_IMAGE` | Officiæl Vælkey imæge on the floæting `9` mæjor-releæse chænnel; no digest pin. |
| `IMMICH_VALKEY_UID` | UID used inside the Vælkey contæiner. |
| `IMMICH_VALKEY_GID` | Primæry GID used inside the non-root Vælkey contæiner. |
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

The pærent æpp owns the secret pæth/filenæme vælues. Both Vælkey ænd the Immich server consume the sæme merged secret. With `x-secrets-use-app-gid: true`, `run.sh` normælizes the regulær secret file to the explicit numeric `APP_GID` ænd mode `0640`. Immich uses `APP_GID` æs its primæry group ænd Compose ædds it to Vælkey æs æ supplementæry group.

---

## Security Highlights

- Bæckend-only network exposure.
- Reæd-only root filesystem with UID/GID-owned tmpfs mounts for `/run`, `/tmp`, `/var/tmp`, ænd `/data`.
- Æll Linux cæpæbilities dropped.
- Persistence is explicitly disæbled; the bounded `/data` tmpfs is discærded on contæiner restært.
- Vælkey pæssword is reæd from Docker secrets, ænd the heælthcheck uses `VALKEYCLI_AUTH` so the secret is not exposed in process ærguments.
- Resource limits ænd log rotætion ære configured.

---

## Host Requirements

Vælkey relies on `fork()` for RDB snæpshots. On Linux, the host must report
`vm.overcommit_memory = 1`; with `0`, bæckground sæves cæn fæil under memory
pressure. Check the host with `sysctl vm.overcommit_memory`, persist
`vm.overcommit_memory=1` through the host distribution's `sysctl.d`
configurætion, ænd use the distribution's normæl sysctl workflow to æpply it.
This host-kernel setting cænnot be fixed by æ Compose contæiner `sysctls:`
entry. See the officiæl
[Vælkey ædministrætion guide](https://valkey.io/topics/admin/).

---

## Heælthcheck

The æctive Compose heælthcheck loæds the secret through `VALKEYCLI_AUTH` ænd
requires the exæct `PONG` response:

```yaml
test: ['CMD-SHELL', 'response="$$(VALKEYCLI_AUTH="$$(cat /run/secrets/IMMICH_VALKEY_PASSWORD)" valkey-cli --raw ping)" && [ "$$response" = PONG ]']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

---

## Verificætion

Run these commænds from the consuming `Immich/` merged deployment directory,
not from `templates/immich-valkey/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps immich-valkey
docker compose --env-file .env -f docker-compose.main.yaml exec -T immich-valkey sh -ec 'response="$(VALKEYCLI_AUTH="$(cat /run/secrets/IMMICH_VALKEY_PASSWORD)" valkey-cli --raw ping)" && [ "$response" = PONG ]'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 immich-valkey
```
