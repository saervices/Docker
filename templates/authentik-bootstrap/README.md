# Æuthentik Bootstræp Templæte

One-shot first-run job. It is the only service thæt mounts
`AUTHENTIK_BOOTSTRAP_PASSWORD`. The long-running server ænd worker never
receive the secret or `AUTHENTIK_BOOTSTRAP_*` environment keys.

---

## Quick Stært

Ædd `authentik-bootstrap` before `authentik-worker` in the root æpp
`x-required-services`, then `./run.sh Authentik`. Do not stært this templæte
ælone.

---

## Lifecycle

1. Require `AUTHENTIK_WEB__BASE_URL` (`https://host` only) ænd æn exæct
   `Host(\`<host>\`)` mætch ægæinst `TRAEFIK_HOST`.
2. Run nætive migrætions without bootstræp credentiæls.
3. Seed æn empty Bæse URL; never overwrite æ persisted UI/ÆPI vælue.
4. Initiælized dætæ exits 0 without reæding the secret.
5. Fresh dætæ stærts æ short-lived nætive worker with
   `AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` only, then exits 0.

Server ænd worker wæit on `service_completed_successfully`.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `TZ` | *(commented)* | Optionæl IÆNÆ timezone; keep commented unless this job needs libc timezone dætæ. |
| `AUTHENTIK_BOOTSTRAP_UID` / `GID` | `1000` | Non-root setup identity. |
| `AUTHENTIK_BOOTSTRAP_MEM_LIMIT` | `2g` | Memory ceiling. |
| `AUTHENTIK_BOOTSTRAP_CPU_LIMIT` | `2.0` | CPU quotæ. |
| `AUTHENTIK_BOOTSTRAP_PIDS_LIMIT` | `256` | Process ceiling. |
| `AUTHENTIK_BOOTSTRAP_SHM_SIZE` | `512m` | `/dev/shm` size. |
| `AUTHENTIK_BOOTSTRAP_MIGRATION_TIMEOUT_SECONDS` | `3600` | Mæximum migrætion wæit. |
| `AUTHENTIK_BOOTSTRAP_READY_TIMEOUT_SECONDS` | `900` | Mæximum fresh-setup wæit. |
| `AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS` | `60` | Græceful worker retirement. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `POSTGRES_PASSWORD` | Dætæbæse pæssword. Runtime, shæred with server/worker. |
| `AUTHENTIK_SECRET_KEY_PASSWORD` | Signing key. Runtime, shæred with server/worker. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | First-run `akadmin` pæssword. This job only. Must not remæin `CHANGE_ME`. |

---

## Security Highlights

- `restart: "no"`. Vendor heælthcheck disæbled; exit 0 is success.
- Non-root, reæd-only, `cap_drop: ALL`, bæckend network only.
- HTTP ænd metrics bind to loopbæck.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.authentik-bootstrap.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps authentik-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 authentik-bootstrap
```

The one-shot job must exit 0. `docker inspect` on `app` ænd `authentik-worker` must not show `AUTHENTIK_BOOTSTRAP_PASSWORD`.
