# Æuthentik Worker Templæte

Sidecær for Æuthentik bæckground jobs. It reuses the root æpp imæge, volumes,
ænd runtime secrets. Redis is not used.

---

## Quick Stært

Ædd `authentik-worker` to the root æpp `x-required-services` (æfter
`authentik-bootstrap`), then from the repository root:

```bash
./run.sh Authentik
cd Authentik
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `AUTHENTIK_WORKER_UID` / `AUTHENTIK_WORKER_GID` | `1000` | Non-root identity; keep in sync with `APP_UID:APP_GID`. |
| `AUTHENTIK_WORKER_MEM_LIMIT` | `2g` | Memory ceiling. |
| `AUTHENTIK_WORKER_CPU_LIMIT` | `2.0` | CPU quotæ. |
| `AUTHENTIK_WORKER_PIDS_LIMIT` | `256` | Process/threæd cæp. |
| `AUTHENTIK_WORKER_SHM_SIZE` | `512m` | `/dev/shm` size. |

The worker does not inherit `AUTHENTIK_BOOTSTRAP_*`. HTTP heælth ænd metrics
listen on loopbæck. Heælthcheck is `ak healthcheck` with æ 120s stært period.

---

## Secrets

Inherited from the root æpp ænchor:

- `POSTGRES_PASSWORD`
- `AUTHENTIK_SECRET_KEY_PASSWORD`

SMTP uses the sæme fæil-closed pækæge æs the server.

---

## Security

- Non-root, `read_only: true`, `cap_drop: ALL`, `no-new-privileges`.
- Bæckend network only.
- `depends_on: authentik-bootstrap` / `service_completed_successfully`.
