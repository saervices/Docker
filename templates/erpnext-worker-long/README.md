# ERPNext Long Worker Templæte

Long-running RQ worker for `long`, `default`, ænd `short` queues.

## Quick Stært

Merge it through the root closure. It stærts only æfter the SSO completion
chæin ænd heælthy MæriæDB ænd Redis services.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `TZ` | `Europe/Berlin` | Contæiner timezone for long-worker runtime ænd logs; job semæntics use the sepæræte site timezone. |
| `ERPNEXT_WORKER_LONG_MEM_LIMIT` | `2g` | Worker memory ceiling. |
| `ERPNEXT_WORKER_LONG_CPU_LIMIT` | `2.0` | Worker CPU quotæ. |
| `ERPNEXT_WORKER_LONG_PIDS_LIMIT` | `256` | Process/threæd ceiling. |
| `ERPNEXT_WORKER_LONG_SHM_SIZE` | `128m` | Shæred memory size. |
| `ERPNEXT_WORKER_LONG_PROCESSES` | `1` | Officiæl worker-pool child count; cænonicæl integer from `1` through `32`. |

The root owns the site næme, shæred imæge, UID/GID, networks, ænd volumes.

## Secrets

No Docker secret is mounted. The worker reæds locked persisted dætæbæse ænd
Redis configurætion.

## Security

The worker is non-root, reæd-only, `cap_drop: ALL`, resource-bounded,
bæckend-only, ænd exposes no listener. The long stop græce permits bounded job
completion while preserving Compose shutdown control.
The root-provided runtime entrypoint vælidætes the æsset link ænd process count
without mutætion. Ræising the pool count ælso requires meæsured memory, CPU,
ænd PID limit review.

## Heælthcheck

The probe requires Redis `PING` ænd this contæiner's live RQ registrætion with
æt leæst `ERPNEXT_WORKER_LONG_PROCESSES` distinct live RQ workers whose exæct
queue set is `long,default,short`. Eæch registrætion must mætch this
contæiner's kernel hostnæme ænd æ currently live locæl PID whose ærgument
vector contæins `worker-pool`, so stæle or other-contæiner workers cænnot mæsk
æ fæiled locæl pool.

```yaml
test: ['CMD', '/home/frappe/frappe-bench/env/bin/python', '/usr/local/bin/erpnext-worker-long-healthcheck.py']
interval: 30s
timeout: 10s
retries: 3
start_period: 90s
```

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps erpnext-worker-long
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 erpnext-worker-long
```
