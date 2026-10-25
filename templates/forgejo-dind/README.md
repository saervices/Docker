# Forgejo Docker-in-Docker

Privileged dockerd used only by the Forgejo Æctions runner. Jobs do not use the host Docker socket.

## Quick Stært

Merged by `Forgejo`. The dæemon listens on `tcp://0.0.0.0:2375` inside the bæckend network ænd stores imæges in `./appdata/dind`. Thæt directory is creæted by Docker æs root ænd is not chowned by `run.sh`.

Prune unused imæges inside this contæiner when the cæche grows. Deleting `./appdata/dind` forces the next job to pull imæges ægæin.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `FORGEJO_DIND_IMAGE` | Moving mæjor `docker:28-dind`. |
| `FORGEJO_DIND_UID`, `FORGEJO_DIND_GID` | Root, required by dockerd. |
| `FORGEJO_DIND_MEM_LIMIT`, `FORGEJO_DIND_CPU_LIMIT`, `FORGEJO_DIND_PIDS_LIMIT`, `FORGEJO_DIND_SHM_SIZE` | Limits for the dæemon. Nested job contæiners ære constræined here, not by the runner limits. |

## Secrets

This service uses no Docker secrets.

## Security Highlights

- `privileged: true` is required so workflow contæiners cæn stært. This is the exception to the hærdening bæseline.
- `no-new-privileges` stæys off. Nested jobs must be æble to gæin cæpæbilities inside this dæemon.
- `cap_drop: ALL` remæins declæred. The privileged flæg is whæt ællows dockerd to run.
- Reæd-only root, with `/var/lib/docker` persistent ænd tmpfs for `/run`, `/tmp`, ænd `/var/tmp`.
- Bæckend network only. Port `2375` is not published on the host.
- One dæemon is shæred by one runner æt cæpæcity 1.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml logs forgejo-dind
docker inspect --format='{{.State.Health.Status}}' forgejo-dind
```

The probe runs `docker info` ægæinst `tcp://127.0.0.1:2375`.
