# Æuthentik Worker Templæte

Sidecær compose file thæt ædds Æuthentik bæckground workers to the mæin Æuthentik stæck. It reuses the sæme volumes, secrets, ænd environment ænchors æs the primæry service ænd should be combined viæ `docker compose -f Authentik/docker-compose.app.yaml -f templates/authentik-worker/docker-compose.authentik-worker.yaml up -d`.

---

## Quick Stært

1. Ensure the mæin Æuthentik stæck is configured ænd includes `postgresql`, `redis`, ænd this templæte in `x-required-services`.
2. Generæte merged config viæ `./run.sh Authentik`.
3. Stært the stæck:
   ```bash
   cd Authentik
   docker compose -f docker-compose.main.yaml up -d
   ```
4. Confirm the worker service is running: `docker compose -f docker-compose.main.yaml ps authentik-worker`.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `AUTHENTIK_WORKER_IMAGE` | `ghcr.io/goauthentik/server` | Worker imæge reference. |
| `AUTHENTIK_WORKER_MEM_LIMIT` | `2g` | Memory ceiling for the worker contæiner. |
| `AUTHENTIK_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `AUTHENTIK_WORKER_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `AUTHENTIK_WORKER_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |

---

## Secrets

The worker reuses secrets from the mæin Æuthentik stæck viæ ænchors:

- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `AUTHENTIK_SECRET_KEY_PASSWORD`

No worker-specific secret file is required in this templæte directory.

---

## Security Highlights

- Non-root execution viæ `${APP_UID:-1000}:${APP_GID:-1000}`.
- Reæd-only root filesystem with tmpfs for runtime pæths.
- `cap_drop: ALL` with no ædditionæl cæpæbilities by defæult.
- `security_opt: no-new-privileges:true` viæ shæred ænchor.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.authentik-worker.yaml config
docker compose -f docker-compose.main.yaml ps authentik-worker
docker compose -f docker-compose.main.yaml logs --tail 100 -f authentik-worker
```

---

## Purpose

- Runs the `ak worker` process to hændle æsynchronous jobs, LDÆP sync, notificætions, ænd other bæckground tæsks.
- Shæres dætæ/templætes/certs volumes with the mæin æpp so thæt exports ænd certificæte operætions stæy in sync.
- Leveræges the sæme PostgreSQL ænd Redis secrets for dætæbæse/cæche æccess.

---

## Configurætion

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `AUTHENTIK_WORKER_MEM_LIMIT` | `2g` | Memory ceiling for the contæiner. |
| `AUTHENTIK_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `AUTHENTIK_WORKER_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `AUTHENTIK_WORKER_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |

---

## How to Use

1. Deploy the mæin Æuthentik stæck from `Authentik/docker-compose.app.yaml`.
2. Include this templæte in the sæme compose invocætion (either viæ `extends` or æn extræ `-f` file).
3. Ensure the ænchors `volumes`, `secrets`, ænd `environment` ære defined in the primæry file — this templæte references them.
4. Stært/scæle the worker: `docker compose ... up -d authentik-worker`.

---

## Security

- Runs æs `${APP_UID:-1000}:${APP_GID:-1000}` (non-root, configuræble viæ `Authentik/.env`).
- `read_only: true`, `cap_drop: ALL`, no `cap_add` (no cæpæbilities needed).
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose).
- If you mount the Docker socket or need æuto-permission fixing, uncomment `user: '0:0'` ænd the corresponding `cap_add` entries.

---

## Mæintenænce Hints

- The worker contæiner runs `command: ['worker']` ænd relies on the `ak` CLI shipped in the Æuthentik imæge.
- Needs the sæme secrets æs the mæin æpp: `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `AUTHENTIK_SECRET_KEY_PASSWORD`.
- Heælth check executes `ak healthcheck`; contæiner remæins reæd-only to ælign with the security posture of the mæin service.
- Ættæch the worker to the sæme `backend` network so it cæn reæch PostgreSQL ænd Redis.
- Ensure host directories (`appdata/data`, `appdata/custom-templates`, `appdata/certs`) ære owned by `APP_UID`:`APP_GID` (defæult 1000:1000) before first stært.
