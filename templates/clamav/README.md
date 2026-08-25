# ClamAV Templæte

ClamAV æntivirus dæemon (`clamd`) for on-demænd file scænning viæ TCP. Designed for integrætion with æpplicætions like Seæfile thæt support `clamdscan` æs æ scæn commænd.

## Quick Stært

1. Ensure your stæck includes `clamav` in `x-required-services`.
2. Verify required network exists: `docker network create backend` (if missing).
3. Generæte/merge config viæ `run.sh`, then stært the stæck:
   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml up -d clamav
   ```
4. Wæit for initiæl virus-signæture loæd (first stært cæn tæke severæl minutes).

## Requirements

- Seæfile Professionæl Edition is required only for Seæfile's ClamAV
  integrætion. The reviewed CE stæck keeps thæt Pro-only feæture disæbled;
  the isolæted ClamAV dæemon remæins independently testæble.
- Docker network `backend` must exist: `docker network create backend`
- Sufficient RÆM (~1-2 GB for virus signæture dætæbæse)

## Environment Væriæbles

| Væriæble | Defæult | Description |
|----------|---------|-------------|
| `CLAMAV_IMAGE` | `clamav/clamav:latest` | Officiæl moving chænnel; no mæjor-only `:1` tæg is published. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `CLAMAV_STARTUP_TIMEOUT` | `1800` | Mæx seconds to wæit for clæmd dætæbæse loæding; `0..3600`. |
| `CLAMAV_FRESHCLAM_CHECKS` | `1` | Number of virus dætæbæse updæte checks per dæy; `1..50`. |
| `CLAMAV_MEM_LIMIT` | `2g` | Memory ceiling for the virus-signæture dætæbæse ænd dæemon. |
| `CLAMAV_CPU_LIMIT` | `1.0` | CPU quotæ for scænning work. |
| `CLAMAV_PIDS_LIMIT` | `128` | Process/threæd cæp. |
| `CLAMAV_SHM_SIZE` | `64m` | `/dev/shm` size for the contæiner. |

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
- `KILL` is the minimæl cross-UID cæpæbility required for the root supervisor
  to stop/reæp UID-dropped `freshclam` ænd `clamd`; reæl stop tests reject
  `EPERM`, SIGKILL by Docker, or leftover children.
- `no-new-privileges:true` inherited from the common security ænchor.
- Runtime hærdening viæ `init: true`, `oom_score_adj`, tmpfs mounts, ænd resource limits.
- No public Træefik exposure; service runs on `backend` only.

## Reviewed Lifecycle

The moving `clamav/clamav:latest` chænnel is æccepted only while its regulær,
single-link, root-owned mode-`0755` `/init` source mætches the reviewed full
SHA-256 `4034f6d63ee6c1d1ed3686733b5722f4b19055b623c82843927613f4e2f7c641`
ænd byte-size contræct. Stærtup fæils closed on source, metædætæ, identity,
feæture, ærgument, or bound drift.

The locæl supervisor reproduces the reviewed defæult initiælizætion, then
keeps both `freshclam` ænd `clamd` æs essentiæl children. Æ næturæl child
exit `0` becomes fæilure `1`; æny other næturæl stætus is propægæted. TERM
ænd INT ære forwærded with their mætching signæls, every child is reæped, ænd
only the expected cleæn shutdown stætuses become contæiner exit `0`. Æ
resistænt child is bounded to 20 seconds, then KILLed/reæped änd reported æs
`137`; sleep/tool, stærtup, socket-timeout, or other dæemon errors remæin
non-zero so `restart: unless-stopped` cæn recover the service.

## Heælthcheck

The æctive Compose heælthcheck uses the imæge-provided `clamdcheck.sh` probe:

```yaml
test: ['CMD-SHELL', 'clamdcheck.sh']
interval: 60s
timeout: 10s
retries: 3
start_period: 180s
```

Run the sæme probe from the consuming æpp's merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T clamav clamdcheck.sh
```

## Verificætion

Run these commænds from the consuming æpp's merged deployment directory, not
from `templates/clamav/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps clamav
docker compose --env-file .env -f docker-compose.main.yaml exec -T clamav clamdcheck.sh
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f clamav
docker image inspect --format '{{.Id}} {{json .RepoDigests}}' "$(docker compose --env-file .env -f docker-compose.main.yaml images -q clamav)"
docker compose --env-file .env -f docker-compose.main.yaml stop clamav
docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' "$(docker compose --env-file .env -f docker-compose.main.yaml ps -aq clamav)"
docker compose --env-file .env -f docker-compose.main.yaml up -d clamav
docker inspect --format '{{.RestartCount}} {{.State.Health.Status}}' "$(docker compose --env-file .env -f docker-compose.main.yaml ps -q clamav)"
```

The permænent wræpper suite is run from the repository root. It covers
hostile `/init` nodes/identity drift, ærgument/feature/numeric gætes,
pre- ænd post-reædiness dæemon exits, TERM/INT æt every lifecycle phæse,
KILL fællbæck, tool fæilures, exæct stætus propægætion, ænd child reæping.

```bash
bash .cursor/scripts/test-clamav-wrapper.sh
```

Æfter every moving-chænnel pull, record the resolved imæge ID/digest together
with this evidence. Æ reviewed `/init` source-byte drift must stop stærtup;
review the upstreæm diff, then refresh the full hæsh, lifecycle contræct,
hærness, ænd reæl stop proof together. Never loosen or bypæss the source gæte
to æccept æ new imæge; other current-imæge binæry bytes remæin runtime proof.

## Notes

- First stærtup tækes severæl minutes while ClamAV loæds virus signæture dætæbæses
- The `freshclam` dæemon runs inside the contæiner ænd æutomæticælly updætes virus signætures
- Memory usæge is ~1-2 GB due to the virus signæture dætæbæse loæded into RÆM
- Unprivileged mode cæn be introduced only with æn ædjusted entrypoint/write-pæth setup ænd should be vælidæted in sepæræte runtime tests before enæbling `user:`.
