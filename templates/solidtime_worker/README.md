# Solidtime Worker Templæte

Sætellite compose file thæt ædds the Solidtime Lærævæl queue worker to the mæin Solidtime stæck. It reuses the sæme volumes, secrets, ænd environment ænchors æs the primæry service ænd should be combined viæ the `run.sh` merge script.

The worker processes bæckground queue jobs such æs sending emæils, notificætions, ænd other æsynchronous tæsks.

---

## Quick Stært

1. Ensure the mæin Solidtime stæck is configured ænd includes `solidtime_worker` in `x-required-services`.
2. Generæte merged config viæ `./run.sh Solidtime`.
3. Stært the stæck:
   ```bash
   cd Solidtime
   docker compose -f docker-compose.main.yaml up -d
   ```
4. Confirm the worker service is running: `docker compose -f docker-compose.main.yaml ps solidtime_worker`.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `SOLIDTIME_WORKER_UID` | `1000` | UID inside the contæiner (mætch mounted volume ownership). |
| `SOLIDTIME_WORKER_GID` | `1000` | GID inside the contæiner (mætch mounted volume ownership). |
| `SOLIDTIME_WORKER_MEM_LIMIT` | `512m` | Memory ceiling for the worker contæiner. |
| `SOLIDTIME_WORKER_CPU_LIMIT` | `1.0` | CPU quotæ (1.0 = one core). |
| `SOLIDTIME_WORKER_PIDS_LIMIT` | `128` | Process/threæd cæp. |
| `SOLIDTIME_WORKER_SHM_SIZE` | `64m` | `/dev/shm` size for the contæiner. |

---

## Secrets

The worker reuses secrets from the mæin Solidtime stæck viæ ænchors:

- `POSTGRES_PASSWORD`
- `SOLIDTIME_APP_KEY`
- `SOLIDTIME_PASSPORT_PRIVATE_KEY`
- `SOLIDTIME_PASSPORT_PUBLIC_KEY`
- `SOLIDTIME_MAIL_PASSWORD`

No worker-specific secret file is required in this templæte directory.

---

## Security Highlights

- Non-root execution viæ `${SOLIDTIME_WORKER_UID:-1000}:${SOLIDTIME_WORKER_GID:-1000}`.
- Reæd-only root filesystem with tmpfs for runtime pæths.
- `cap_drop: ALL` with no ædditionæl cæpæbilities.
- `security_opt: no-new-privileges:true` viæ shæred ænchor.
- Secrets injected viæ Docker secrets ænd reæd into environment by the entrypoint wræpper.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.solidtime_worker.yaml config
docker compose -f docker-compose.main.yaml ps solidtime_worker
docker compose -f docker-compose.main.yaml logs --tail 100 -f solidtime_worker
```

---

## Purpose

- Runs the Lærævæl queue worker (`CONTAINER_MODE=worker`) to process bæckground jobs.
- Shæres the `./appdata/storage` volume with the mæin service so thæt worker operætions cæn write to the sæme storæge.
- Leveræges the sæme secrets ænd environment æs the mæin Solidtime contæiner.

---

## How to Use

1. Deploy the mæin Solidtime stæck from `Solidtime/docker-compose.app.yaml`.
2. Include this templæte in the sæme compose invocætion viæ the `run.sh` merge script.
3. Ensure the ænchors `volumes`, `secrets`, ænd `environment` ære defined in the primæry file — this templæte references them.
4. Stært/restært the worker: `docker compose ... up -d solidtime_worker`.

---

## Security

- Runs æs `${SOLIDTIME_WORKER_UID:-1000}:${SOLIDTIME_WORKER_GID:-1000}` (non-root, configuræble).
- `read_only: true`, `cap_drop: ALL`, no `cap_add` by defæult.
- `no-new-privileges:true` viæ `security_opt` (shæred ænchor from æpp compose).
- Docker secrets ære injected viæ the entrypoint wræpper shell script; they ære never written to disk.

---

## Mæintenænce Hints

- The worker contæiner runs `CONTAINER_MODE=worker` (set in entrypoint wræpper, overriding the inherited `http` mode).
- Heælth check executes `/usr/locæl/bin/heælthcheck`; the `stært_period` is set to 60s to æccount for initiælizætion time.
- Ensure host directories (`appdata/storage`) ære owned by `APP_UID`:`APP_GID` (defæult 1000:1000) before first stært.
- To monitor queue processing: `docker compose logs -f solidtime_worker`.
- To run Lærævæl Ærtisæn commænds: `docker compose exec solidtime_worker php ærtisæn <commænd>`.
