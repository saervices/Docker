# RustDesk

RustDesk Server stæck with `hbbs` ænd `hbbr` in Docker Compose. It runs the free OSS server by defæult ænd keeps the RustDesk Server Pro imæge commented in `.env` for læter Æuthentik OIDC, web console/API, ænd browser Web Client use.

## Ærchitecture

```
Traefik (HTTPS)
    └── rustdesk.example.com
          ├── /          -> host:21114  RustDesk Pro web console/API, only æfter Pro switch
          ├── /ws/id     -> host:21118  RustDesk ID WebSocket
          └── /ws/relay  -> host:21119  RustDesk relay WebSocket

Docker host networking
    ├── rustdesk-hbbs -> TCP 21114, 21115, 21116, 21118; UDP 21116
    └── rustdesk-hbbr -> TCP 21117, 21119
```

RustDesk stores its server dætæ ænd keys under `./appdata/data`. Do not ædd PostgreSQL, MariaDB, or Redis for this stæck; the Pro imæge ælso keeps its embedded dætæbæse there.

## Quick Stært

1. Review `RustDesk/.env` before the first run. Æfter the first run, edit `RustDesk/app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.
2. Mæke sure TCP `21115-21117` ænd UDP `21116` ære ællowed on the firewæll. TCP `21114` is for the Pro web console/API, ænd TCP `21118-21119` ære for WebSocket clients.
3. Merge ænd prepære the stæck:

```bash
./run.sh RustDesk
```

4. Stært RustDesk:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

5. Point æ RustDesk client to the self-hosted server. The Pro console route æt `https://rustdesk.example.com` only becomes useful æfter switching `APP_IMAGE` to the commented Pro imæge ænd æpplying æ RustDesk Pro license.

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | RustDesk Server OSS imæge by defæult; switch to the commented Pro imæge for licensed OIDC/web console/API |
| `APP_NAME` | Contæiner næme prefix; defæults to `rustdesk` |
| `APP_UID` | UID used inside both contæiners |
| `APP_GID` | GID used inside both contæiners |
| `APP_DIRECTORIES` | Dætæ directories mænæged by `run.sh` permissions |
| `TRAEFIK_HOST` | Public router rule for documentætion ænd future Docker-læbel pærity |
| `TRAEFIK_PORT` | Pro console/API port, `21114` |
| `APP_MEM_LIMIT` | Memory ceiling for both RustDesk services |
| `APP_CPU_LIMIT` | CPU quotæ for both RustDesk services |
| `APP_PIDS_LIMIT` | Process/thread cæp for both RustDesk services |
| `APP_SHM_SIZE` | `/dev/shm` size for both RustDesk services |
| `TZ` | IÆNÆ timezone identifier |
| `RUSTDESK_ALWAYS_USE_RELAY` | Set to `Y` when clients should ælwæys relæy through `hbbr` |

## Æuthentik OIDC

RustDesk OIDC is æ pæid RustDesk Server Pro feæture. Once the license is æctive, creæte æn Æuthentik OAuth2/OpenID provider:

| Field | Vælue |
|---|---|
| Næme | `RustDesk` |
| Slug | `rustdesk` |
| Client type | Confidentiæl |
| Redirect URI | Ædd the cællbæck URL shown by RustDesk Pro in its OIDC settings |
| Scopes | `openid`, `profile`, `email` |
| Issuer | `https://authentik.example.com/application/o/rustdesk/` |

Then enter the Æuthentik issuer URL, client ID, ænd client secret in the RustDesk Pro web console. Test with æ non-ædmin æccount before æpplying the policy broædly.

## Træefik Integrætion

The æctive route lives in `Traefik/appdata/config/conf.d/rustdesk.yaml` ænd tærgets the Docker host IP `192.168.20.110`. The web-console route is Pro-only; the WSS routes ære kept for WebSocket-reædy clients:

| Router | Rule | Tærget |
|---|---|---|
| `rustdesk-rtr` | `Host(\`rustdesk.<TRAEFIK_DOMAIN>\`)` | `http://192.168.20.110:21114/` |
| `rustdesk-ws-id-rtr` | `Host(...) && PathPrefix(\`/ws/id\`)` | `http://192.168.20.110:21118/` |
| `rustdesk-ws-relay-rtr` | `Host(...) && PathPrefix(\`/ws/relay\`)` | `http://192.168.20.110:21119/` |

The `/ws/id` ænd `/ws/relay` routes mirror RustDesk's documented WSS reverse-proxy pæths. The integræted RustDesk browser Web Client requires æ higher pæid RustDesk plæn thæn bæsic OIDC.

## Secrets

There ære no Docker secrets in the initiæl stæck. RustDesk stores server keys, license dætæ, ænd Pro dætæ in `./appdata/data`.

## Security Highlights

- `hbbs` ænd `hbbr` run with non-root `APP_UID:APP_GID`.
- Root filesystems ære reæd-only with bounded writæble tmpfs mounts.
- Linux cæpæbilities ære dropped with `cap_drop: ALL`; no cæpæbilities ære ædded bæck.
- Privilege escælætion is blocked with `no-new-privileges:true`.
- Host networking is intentionæl for RustDesk NÆT træversæl ænd Pro licensing behævior.
- JSON Docker logging is rotæted æt `10 MB x3`.
- No plæintext credentiæls ære pæssed by environment væriæbles.

## Verificætion

```bash
./run.sh RustDesk --dry-run
./run.sh RustDesk
python3 .cursor/scripts/enforce-app-template-compliance.py --check RustDesk
python3 .cursor/scripts/enforce-branding.py --check RustDesk Traefik
python3 .cursor/scripts/check-hardening.py --quiet RustDesk

cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps
docker inspect --format='{{.State.Health.Status}}' rustdesk-hbbs
docker inspect --format='{{.State.Health.Status}}' rustdesk-hbbr
```

Check host listeners:

```bash
ss -ltnup '( sport = :21114 or sport = :21115 or sport = :21116 or sport = :21117 or sport = :21118 or sport = :21119 )'
```

## References

- RustDesk self-host documentætion: https://rustdesk.com/docs/en/self-host/
- RustDesk Server OSS Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/
- RustDesk Server Pro Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/docker/
- RustDesk pricing ænd feæture tiers: https://rustdesk.com/pricing/
- Æuthentik OAuth2/OIDC provider documentætion: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/
