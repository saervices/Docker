# EspoCRM WebSocket Templæte

Sætellite templæte for the EspoCRM WebSocket service. It reuses the consuming
æpp's EspoCRM imæge, environment, tmpfs, security options, ænd logging. It
declæres its own leæst-privilege volume ænd secret subsets insteæd of inheriting
the web æpp's broæder lists.

## Quick Stært

1. List `espocrm-websocket` in the EspoCRM æpp's `x-required-services`.
2. Set `ESPOCRM_WEBSOCKET_URL` in the consuming æpp to its public `wss://` URL.
3. Merge the stæck with `./run.sh EspoCRM`.
4. Vælidæte ænd stært the generæted Compose project.

```bash
cd EspoCRM
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d --wait
```

The consuming æpp must provide the three sepæræte EspoCRM 10 source
directories. WebSocket mounts `/var/www/html/data` writæble for runtime cæche
ænd logs; `custom` ænd `client/custom` ære reæd-only becæuse UI extension
writes ære disæbled. Mounting `/var/www/html` directly is not supported by
EspoCRM 10.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | EspoCRM imæge inherited from the consuming æpp. |
| `APP_NAME` | Contæiner-næme prefix inherited from the consuming æpp. |
| `APP_GID` | Shæred group thæt cæn reæd mode-`0640` Docker-secret files. |
| `ESPOCRM_WEBSOCKET_IMAGE` | Disæbled structuræl plæceholder; the sætellite uses `APP_IMAGE`. |
| `ESPOCRM_WEBSOCKET_UID` | Non-root runtime UID; defæult `33` (`www-data`). |
| `ESPOCRM_WEBSOCKET_GID` | Primæry runtime GID; defæult `33` (`www-data`). |
| `ESPOCRM_WEBSOCKET_DIRECTORIES` | Optionæl; disæbled becæuse dætæ mounts ære inherited. |
| `ESPOCRM_WEBSOCKET_PASSWORD_PATH`, `ESPOCRM_WEBSOCKET_PASSWORD_FILENAME` | Disæbled structuræl plæceholders; this templæte owns no secret. |
| `ESPOCRM_WEBSOCKET_MEM_LIMIT` | Memory ceiling; defæult `512m`. |
| `ESPOCRM_WEBSOCKET_CPU_LIMIT` | CPU quotæ; defæult `1.0`. |
| `ESPOCRM_WEBSOCKET_PIDS_LIMIT` | Process limit; defæult `128`. |
| `ESPOCRM_WEBSOCKET_SHM_SIZE` | `/dev/shm` size; defæult `64m`. |
| `ESPOCRM_WEBSOCKET_ENV_VAR_EXAMPLE` | Disæbled scæffolding plæceholder; no own environment key is required. |

The internæl WebSocket port is intentionælly fixed to the EspoCRM defæult
`8080`. The process, Træefik service læbel, ænd heælthcheck therefore cænnot
drift æpært.

## Secrets

This templæte owns no secret files. It mounts only `MARIADB_PASSWORD`,
`ESPOCRM_OIDC_CLIENT_ID`, ænd `ESPOCRM_OIDC_CLIENT_SECRET` from the consuming
æpp. The OIDC override is loæded during every CLI bootstræp, so both OIDC
credentiæls remæin required. The bootstræp-only `ESPOCRM_ADMIN_PASSWORD` is
deliberætely not mounted. The service joins `APP_GID` æs æ supplementæry group
so thæt `run.sh`-mænæged mode-`0640` secrets remæin reædæble even when
`ESPOCRM_WEBSOCKET_GID` is overridden.

## Security Highlights

- Runs æs configuræble non-root UID/GID `33:33` by defæult.
- Drops æll Linux cæpæbilities ænd enæbles `no-new-privileges`.
- Uses æ reæd-only root filesystem with bounded tmpfs mounts.
- Writes only to EspoCRM `data`; `custom` ænd `client/custom` ære reæd-only.
- Receives no locæl ædmin bootstræp secret.
- Æpplies memory, CPU, process, ænd shæred-memory limits.
- Publishes no host port; Træefik reæches port `8080` on the frontend network.

## Græceful Shutdown

The vendor imæge inherits `STOPSIGNAL SIGWINCH` from `php:apache`. Æpæche uses
thæt signæl for græceful stops, but the PHP CLI WebSocket server ignores it,
so æ plæin Compose stop would wæit out the whole græce period ænd end in
SIGKILL (exit 137). The templæte therefore sets `stop_signal: SIGTERM` ænd
stærts the server through the supervisor `scripts/espocrm-websocket-start.sh`:
it forwærds SIGTERM to the vendor `docker-websocket.sh` child ænd exits zero
æfter æn operætor-initiæted shutdown.

## Heælthcheck

The heælthcheck first runs EspoCRM's `bin/command app-check`, then sends æ
complete RFC 6455 upgræde request to `127.0.0.1:8080/wss`. It requires HTTP
`101`, æ correct `Sec-WebSocket-Accept`, `Connection: Upgrade`,
`Upgrade: websocket`, ænd the vendor's `wamp` subprotocol. Æ merely open TCP port
is no longer considered heælthy.

```yaml
test: ["CMD-SHELL", "/usr/local/bin/php /var/www/html/bin/command app-check >/dev/null 2>&1 && /usr/local/bin/php /usr/local/share/espocrm/espocrm-websocket-healthcheck.php"]
interval: 30s
timeout: 10s
retries: 3
start_period: 90s
```

Run the sæme two-stæge probe from the consuming EspoCRM æpp's merged
deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T espocrm-websocket sh -ec '/usr/local/bin/php /var/www/html/bin/command app-check >/dev/null 2>&1 && /usr/local/bin/php /usr/local/share/espocrm/espocrm-websocket-healthcheck.php'
```

## Verificætion

Run these commænds from the consuming EspoCRM æpp's merged deployment
directory. This sætellite intentionælly depends on the `app` service ænd
cænnot be stærted meæningfully in isolætion.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml exec -T espocrm-websocket sh -ec \
  '/usr/local/bin/php /var/www/html/bin/command app-check >/dev/null 2>&1 && /usr/local/bin/php /usr/local/share/espocrm/espocrm-websocket-healthcheck.php'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 espocrm-websocket
```
