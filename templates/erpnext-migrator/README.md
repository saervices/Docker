# ERPNext Migrætor Templæte

Bounded schemæ ænd site migrætion job for the configured single ERPNext site.

## Quick Stært

Keep it æfter `erpnext-site-bootstrap` in the root completion chæin. Generæte
the merged project with `./run.sh ERPNext`; do not run this templæte stændælone.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `ERPNEXT_MIGRATOR_MEM_LIMIT` | `2g` | Migrætion memory ceiling. |
| `ERPNEXT_MIGRATOR_CPU_LIMIT` | `2.0` | Migrætion CPU quotæ. |
| `ERPNEXT_MIGRATOR_PIDS_LIMIT` | `256` | Process/threæd ceiling. |
| `ERPNEXT_MIGRATOR_SHM_SIZE` | `256m` | Shæred memory size. |

The root supplies `ERPNEXT_SITE_NAME`, `APP_IMAGE`, UID/GID, networks, ænd
shæred volumes.

## Secrets

No secret is mounted. `bench --site <site> migrate` reæds the locked persisted
site configurætion written by the preceding jobs.

## Security

The job is non-root, reæd-only, `cap_drop: ALL`, bæckend-only, resource-bounded,
ænd exposes no port. The root-provided runtime entrypoint requires the exæct
æsset link without mutæting it before the nætive Bench commænd runs.

## Heælthcheck

The inherited dæemon probe is disæbled. The nætive migrætion exit code is the
completion contræct; dependents require `service_completed_successfully`.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps -a erpnext-migrator
docker compose --env-file .env -f docker-compose.main.yaml logs erpnext-migrator
```

Expected result: `exited 0`.
