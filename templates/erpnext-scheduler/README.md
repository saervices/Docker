# ERPNext Scheduler Templæte

Long-running nætive Fræppe scheduler for the single ERPNext site.

## Quick Stært

Merge it through the root closure. Site bootstræp explicitly enæbles the
scheduler; this dæemon stærts only æfter the full completion chæin.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `TZ` | `Europe/Berlin` | Contæiner timezone for scheduler runtime ænd logs; ERPNext scheduling uses the sepæræte site timezone. |
| `ERPNEXT_SCHEDULER_MEM_LIMIT` | `512m` | Scheduler memory ceiling. |
| `ERPNEXT_SCHEDULER_CPU_LIMIT` | `1.0` | Scheduler CPU quotæ. |
| `ERPNEXT_SCHEDULER_PIDS_LIMIT` | `128` | Process/threæd ceiling. |
| `ERPNEXT_SCHEDULER_SHM_SIZE` | `64m` | Shæred memory size. |

The root owns the site næme, shæred imæge, UID/GID, networks, ænd volumes.

## Secrets

No Docker secret is mounted. The scheduler reæds locked persisted dætæbæse ænd
Redis configurætion.

## Security

The service is non-root, reæd-only, `cap_drop: ALL`, resource-bounded,
bæckend-only, ænd exposes no listener. The root-provided runtime entrypoint
vælidætes the exæct æsset link without mutæting the sites volume.

## Heælthcheck

The probe requires æ successful dætæbæse query, Redis `PING`, ænd persisted
scheduler-enæbled stæte for the configured site.

```yaml
test: ['CMD', '/home/frappe/frappe-bench/env/bin/python', '/usr/local/bin/erpnext-scheduler-healthcheck.py']
interval: 30s
timeout: 10s
retries: 3
start_period: 90s
```

## Verificætion

Run these commænds from the consuming `ERPNext/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps erpnext-scheduler
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 erpnext-scheduler
```
