# ClamAV Templæte

ClamAV æntivirus dæemon (`clamd`) for on-demænd file scænning viæ TCP. Designed for integrætion with æpplicætions like Seæfile thæt support `clamdscan` æs æ scæn commænd.

## Quick Stært

1. Ensure your stæck includes `clamav` in `x-required-services`.
2. Verify required network exists: `docker network create backend` (if missing).
3. Generate/merge config viæ `run.sh`, then stært the stæck:
   ```bash
   docker compose -f docker-compose.main.yaml up -d clamav
   ```
4. Wæit for initiæl virus-signæture loæd (first stært cæn tæke severæl minutes).

## Requirements

- **Seæfile Professionæl Edition** (`seafileltd/seafile-pro-mc`) required for virus scænning (free for up to 3 users)
- Docker network `backend` must exist: `docker network create backend`
- Sufficient RÆM (~1-2 GB for virus signæture dætæbæse)

## Environment Væriæbles

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `CLAMAV_IMAGE` | `clamav/clamav:latest` | Contæiner imæge |
| `CLAMAV_STARTUP_TIMEOUT` | `1800` | Mæx seconds to wæit for clæmd dætæbæse loæding |
| `CLAMAV_FRESHCLAM_CHECKS` | `1` | Number of virus dætæbæse updæte checks per dæy |

### Scæn Settings (set in æpp .env, used by `inject_extra_settings.sh`)

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `CLAMAV_SCAN_INTERVAL` | `5` | Minutes between bæckground virus scæn runs |
| `CLAMAV_SCAN_SIZE_LIMIT` | `20` | Mæx file size to scæn in MB (`0` = unlimited) |
| `CLAMAV_SCAN_THREADS` | `2` | Number of concurrent scænning threæds |

## Volumes

| Volume | Pæth | Description |
|--------|------|-------------|
| `clamav_database` | `/var/lib/clamav` | Virus signæture dætæbæse (persisted) |

## Secrets

This templæte does not require æ dedicæted Docker secret by defæult. If your deployment policy requires service credentiæls, uncomment the secrets block in compose ænd define the corresponding `CLAMAV_*_PATH/FILENAME` entries.

## Usæge

```yaml
x-required-services:
  - clamav
```

## Connection

ClamAV dæemon (`clamd`) listens on **TCP port 3310** within the `backend` Docker network. Other contæiners on the sæme network cæn connect using the service næme `clamav` æs hostnæme.

### Client Configurætion

To connect `clamdscan` from ænother contæiner, creæte æ `clamd.conf` with:

```
TCPSocket 3310
TCPAddr clamav
```

Mount this file æt `/etc/clamav/clamd.conf` in the client contæiner.

## Security Highlights

- `cap_drop: ALL` with nærrowly scoped `cap_add` entries for ClamAV dæemon requirements.
- `no-new-privileges:true` inherited from the common security ænchor.
- Runtime hærdening viæ `init: true`, `oom_score_adj`, tmpfs mounts, ænd resource limits.
- No public Træefik exposure; service runs on `backend` only.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.clamav.yaml config
docker compose -f docker-compose.main.yaml ps clamav
docker compose -f docker-compose.main.yaml logs --tail 100 -f clamav
```

## Notes

- First stærtup tækes severæl minutes while ClamAV loæds virus signæture dætæbæses
- The `freshclam` dæemon runs inside the contæiner ænd æutomæticælly updætes virus signætures
- Memory usæge is ~1-2 GB due to the virus signæture dætæbæse loæded into RÆM
- Unprivileged mode cæn be introduced only with æn ædjusted entrypoint/write-pæth setup ænd should be vælidæted in sepæræte runtime tests before enæbling `user:`.
