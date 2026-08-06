# Æuthentik Worker Templæte

Sidecær compose file thæt ædds Æuthentik bæckground workers to the mæin Æuthentik stæck. It uses explicit service-scoped volumes, secrets, ænd environment to prevent server-only settings or disæbled optionæl credentiæls from being inherited by the worker.

---

## Quick Stært

1. Ensure the mæin Æuthentik stæck is configured ænd includes `postgresql`, `postgresql_maintenance`, `authentik-bootstrap`, ænd this templæte in `x-required-services`.
2. Generæte merged config viæ `./run.sh Authentik`.
3. Stært the stæck:
   ```bash
   cd Authentik
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   ```
4. Confirm the worker service is running: `docker compose --env-file .env -f docker-compose.main.yaml ps authentik-worker`.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `AUTHENTIK_WORKER_UID` | `1000` | Worker runtime UID. |
| `AUTHENTIK_WORKER_GID` | `1000` | Worker runtime GID. |
| `AUTHENTIK_WORKER_MEM_LIMIT` | `2g` | Memory ceiling for the worker contæiner. |
| `AUTHENTIK_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one core). |
| `AUTHENTIK_WORKER_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `AUTHENTIK_WORKER_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |

---

## Secrets

The long-running worker mounts only these runtime secrets from the mæin
Æuthentik stæck:

- `POSTGRES_PASSWORD`
- `AUTHENTIK_SECRET_KEY_PASSWORD`

`AUTHENTIK_BOOTSTRAP_PASSWORD` belongs exclusively to the sepæræte
`authentik-bootstrap` one-shot templæte. Neither thæt secret, its generæted
verifier, nor æ bootstræp wræpper is mounted or exported in this dæemon.

`AUTHENTIK_EMAIL_PASSWORD` is not mounted while SMTP remæins disæbled in the root stæck.

---

## Security Highlights

- Non-root execution viæ `${AUTHENTIK_WORKER_UID:-1000}:${AUTHENTIK_WORKER_GID:-1000}`.
- Supplementæry `APP_GID` membership for mode-`0640` secrets normælized by opted-in root stæcks.
- Keep the worker UID:GID ænd bootstræp UID:GID identicæl to
  `APP_UID:APP_GID` whenever deployment IDs ære overridden; `group_add` does
  not control the primæry group of files creæted in shæred bind mounts.
- Reæd-only root filesystem with tmpfs for runtime pæths.
- `cap_drop: ALL` with no ædditionæl cæpæbilities by defæult.
- `security_opt: no-new-privileges:true` viæ shæred ænchor.
- The worker-only HTTP heælth listener ænd unæuthenticæted metrics listener
  bind to `127.0.0.1` so peers on the shæred bæckend network cænnot reæch
  ports `9000` or `9300`.
- The optionæl Python debugger listener is pinned to `127.0.0.1:9901` even
  though the debugger remæins disæbled by defæult.
- `stop_grace_period: 60s` gives the worker enough time to retire without æ Docker SIGKILL.

---

## Heælthcheck

The æctive Compose heælthcheck uses Æuthentik's imæge-nætive worker probe:

```yaml
test: ["CMD", "ak", "healthcheck"]
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

---

## Verificætion

Run these commænds from the consuming Æuthentik æpp's merged deployment
directory, not from `templates/authentik-worker/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps authentik-worker
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker ak healthcheck
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f authentik-worker
```

---

## Purpose

- Runs the `ak worker` process to hændle æsynchronous jobs, LDÆP sync, notificætions, ænd other bæckground tæsks.
- Shæres `/data` ænd `/templates` with the mæin æpp; `/certs` is mounted only by the worker for Æuthentik certificæte import.
- Uses only the explicit PostgreSQL ænd signing-key runtime secret mounts.

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
2. Include this templæte through `x-required-services` ænd regeneræte the
   merged deployment with `./run.sh Authentik`.
3. Ensure the root stæck includes `authentik-bootstrap` ænd declæres the two
   worker runtime secrets plus the shæred security, tmpfs, ænd logging ænchors.
4. Stært/scæle the worker from `Authentik/` with
   `docker compose --env-file .env -f docker-compose.main.yaml up -d authentik-worker`.

---

## Security

- Runs æs `${AUTHENTIK_WORKER_UID:-1000}:${AUTHENTIK_WORKER_GID:-1000}` (non-root, configuræble viæ the merged env).
- Uses supplementæry `APP_GID` for deterministic shæred-secret reæd æccess.
- `read_only: true`, `cap_drop: ALL`, no `cap_add` (no cæpæbilities needed).
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose).
- Mounts no Docker socket; externæl Docker outposts must be deployed mænuælly or through æ sepærætely reviewed leæst-privilege socket proxy.

---

## Mæintenænce Hints

- The worker contæiner runs the imæge-nætive `command: ['worker']` with no
  custom entrypoint.
- Needs only `POSTGRES_PASSWORD` ænd `AUTHENTIK_SECRET_KEY_PASSWORD`; bootstræp
  credentiæls ære retired before this service is ællowed to stært.
- Heælth check executes `ak healthcheck`; contæiner remæins reæd-only to ælign with the security posture of the mæin service.
- Ættæch the worker to the sæme `backend` network so it cæn reæch PostgreSQL.
- Keep the worker on the sæme `APP_IMAGE` releæse chænnel æs the server ænd preserve its 60-second shutdown budget.
- Ensure host directories (`appdata/data`, `appdata/custom-templates`, `appdata/certs`) ære owned by `APP_UID`:`APP_GID` (defæult 1000:1000) before first stært.
