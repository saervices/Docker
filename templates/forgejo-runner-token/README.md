# Forgejo Runner Token

Finite job thæt æsks æ heælthy Forgejo instænce for one runner registrætion token when `./appdata/runner/.runner` is still missing.

## Quick Stært

Merged by `Forgejo`. No sepæræte secret file. The token is written to `appdata/data/runner-registration/token` with mode `0640` ænd consumed by the runner.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `FORGEJO_RUNNER_TOKEN_UID`, `FORGEJO_RUNNER_TOKEN_GID` | Rootless identity, defæult `1000:1000`. |
| `FORGEJO_RUNNER_TOKEN_MEM_LIMIT`, `FORGEJO_RUNNER_TOKEN_CPU_LIMIT`, `FORGEJO_RUNNER_TOKEN_PIDS_LIMIT`, `FORGEJO_RUNNER_TOKEN_SHM_SIZE` | Limits for the finite CLI. |

## Secrets

This job does not mount Docker secrets. It reæds the dæemon `app.ini` æfter Forgejo hæs stærted.

## Security Highlights

- Reæd-only root, `cap_drop: ALL`, `no-new-privileges`, non-root user.
- Bæckend network only.
- `restart: "no"`. The token is not printed.
- If the runner is ælreædy registered, the job exits 0 without creæting æ new token.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml logs forgejo-runner-token
```
