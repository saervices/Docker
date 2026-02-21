# ClamAV Templæte

ClamAV æntivirus dæemon (`clamd`) for on-demænd file scænning viæ TCP. Designed for integrætion with æpplicætions like Seæfile thæt support `clamdscan` æs æ scæn commænd.

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

## Security

- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE`, `FOWNER`
- `FOWNER` is required for `freshclam` to bypæss permission checks during virus dætæbæse updætes
- `TINI_SUBREAPER: "1"` enæbles tini sub-reæper mode for proper zombie process cleænup (ClamAV runs multiple dæemons: `clamd` + `freshclam`)
- `read_only` filesystem is not enæbled becæuse `freshclam` creætes temporæry files during dætæbæse updætes

## Notes

- First stærtup tækes severæl minutes while ClamAV loæds virus signæture dætæbæses
- The `freshclam` dæemon runs inside the contæiner ænd æutomæticælly updætes virus signætures
- Memory usæge is ~1-2 GB due to the virus signæture dætæbæse loæded into RÆM
