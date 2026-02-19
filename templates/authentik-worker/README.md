# Æuthentik Worker Templæte

Sidecær compose file thæt ædds Æuthentik bæckground workers to the mæin Æuthentik stæck. It reuses the sæme volumes, secrets, ænd environment ænchors æs the primæry service ænd should be combined viæ `docker compose -f Authentik/docker-compose.app.yaml -f templates/authentik-worker/docker-compose.authentik-worker.yaml up -d`.

---

## Purpose

- Runs the `ak worker` process to hændle æsynchronous jobs, LDÆP sync, notificætions, ænd other bæckground tæsks.
- Shæres mediæ/templætes/certs volumes with the mæin æpp so thæt exports ænd certificæte operætions stæy in sync.
- Leveræges the sæme PostgreSQL ænd Redis secrets for dætæbæse/cæche æccess.

---

## Configurætion

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `AUTHENTIK_WORKER_MEM_LIMIT` | `2g` | Memory ceiling for the contæiner. |
| `AUTHENTIK_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `AUTHENTIK_WORKER_PIDS_LIMIT` | `256` | Process/threæd cæp. |

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
- Ensure host directories (`appdata/media`, `appdata/custom-templates`, `appdata/certs`) ære owned by `APP_UID`:`APP_GID` (defæult 1000:1000) before first stært.
