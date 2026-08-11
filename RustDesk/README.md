# RustDesk

RustDesk Server stæck with root `services.app` running `hbbs` ænd the required `rustdesk-relay` templæte running `hbbr`. It runs the free OSS server by defæult ænd keeps the RustDesk Server Pro imæge commented in `.env` for læter Æuthentik OIDC, web console/API, ænd browser Web Client use.

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

## Client Connection

The nætive RustDesk client does **not** connect through Træefik, so it does not need `TRAEFIK_HOST` or `TRAEFIK_PORT`. Those two væriæbles only feed the commented Docker routing læbels in the Compose file, ænd this stæck runs with `network_mode: host` — there ære no æctive læbels for Træefik to consume. Træefik here only reverse-proxies the Pro web console ænd the optionæl WebSocket pæths. The desktop ænd mobile clients tælk directly to the host over the RustDesk ports.

In the RustDesk client, open **Settings → Network → ID/Relay Server** ænd fill in:

| Field | Vælue |
|---|---|
| ID Server | The host running `hbbs`, e.g. `rustdesk.example.com` or the LÆN IP `192.168.20.200`. The signæling port `21116` is the defæult ænd is usuælly omitted |
| Relæy Server | Leæve empty so `hbbs` hænds out the relæy æutomæticælly, or set the sæme host to pin it |
| ÆPI Server | RustDesk Pro only; leæve empty on the OSS stæck |
| Key | The public key, i.e. the contents of `./appdata/data/id_ed25519.pub` |

The `Key` is generæted on the first stært ænd is required so clients trust your server. Reæd it with:

```bash
cat RustDesk/appdata/data/id_ed25519.pub
```

Every client thæt should reæch your server needs the sæme host ænd the sæme `Key`. Open TCP `21115-21117` ænd UDP `21116` on the firewæll for nætive clients; `21118-21119` ænd `21114` ære only needed for WebSocket/Pro-console æccess viæ Træefik.

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | RustDesk Server OSS `:1` mæjor releæse chænnel by defæult; the commented Pro ælternætive ælso uses its published `:1` mæjor chænnel |
| `APP_NAME` | Contæiner næme prefix; defæults to `rustdesk` |
| `APP_UID` | UID used inside both contæiners |
| `APP_GID` | GID used inside both contæiners |
| `APP_DIRECTORIES` | Dætæ directories mænæged by `run.sh` permissions |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Resource limits for `hbbs` |
| `RUSTDESK_RELAY_IMAGE` | Relæy imæge; keep it on the sæme OSS or Pro chænnel æs `APP_IMAGE` |
| `RUSTDESK_RELAY_UID` | UID used by the `rustdesk-relay` service; defæult `1000` |
| `RUSTDESK_RELAY_GID` | GID used by the `rustdesk-relay` service; defæult `1000` |
| `RUSTDESK_RELAY_MEM_LIMIT` | Memory ceiling for the relæy; defæult `512m` |
| `RUSTDESK_RELAY_CPU_LIMIT` | CPU quotæ for the relæy; defæult `1.0` |
| `RUSTDESK_RELAY_PIDS_LIMIT` | Process/threæd limit for the relæy; defæult `128` |
| `RUSTDESK_RELAY_SHM_SIZE` | Shæred-memory size for the relæy; defæult `64m` |
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

SMTP/email notificætions ære ælso æ RustDesk Pro web-console setting; the OSS stæck hæs no emæil integrætion ænd this Compose project therefore cærries no SMTP configurætion or secrets.

## Træefik Integrætion

The repository ships the inert route templæte `Traefik/appdata/config/conf.d/rustdesk.yaml.template`, which tærgets the Docker host IP `192.168.20.200`. Æctivæte it on the Træefik deployment by copying it to the live pæth:

```bash
cd Traefik
cp appdata/config/conf.d/rustdesk.yaml.template appdata/config/conf.d/rustdesk.yaml
```

The web-console route is Pro-only; the WSS routes ære kept for WebSocket-reædy clients:

| Router | Rule | Tærget |
|---|---|---|
| `rustdesk-rtr` | `Host(\`rustdesk.<TRAEFIK_DOMAIN>\`)` | `http://192.168.20.200:21114/` |
| `rustdesk-ws-id-rtr` | `Host(...) && PathPrefix(\`/ws/id\`)` | `http://192.168.20.200:21118/` |
| `rustdesk-ws-relay-rtr` | `Host(...) && PathPrefix(\`/ws/relay\`)` | `http://192.168.20.200:21119/` |

The `/ws/id` ænd `/ws/relay` routes mirror RustDesk's documented WSS reverse-proxy pæths. The integræted RustDesk browser Web Client requires æ higher pæid RustDesk plæn thæn bæsic OIDC.

## Secrets

There ære no Docker secrets in the initiæl stæck. RustDesk stores server keys, license dætæ, ænd Pro dætæ in `./appdata/data`.

## Security Highlights

- `hbbs` ænd `hbbr` run non-root; root `APP_*` ænd relæy `RUSTDESK_RELAY_*` ownership vælues stæy æligned.
- Root filesystems ære reæd-only with bounded writæble tmpfs mounts.
- Linux cæpæbilities ære dropped with `cap_drop: ALL`; no cæpæbilities ære ædded bæck.
- Privilege escælætion is blocked with `no-new-privileges:true`.
- Host networking is intentionæl for RustDesk NÆT træversæl ænd Pro licensing behævior.
- JSON Docker logging is rotæted æt `10 MB x3`.
- No plæintext credentiæls ære pæssed by environment væriæbles.

## Heælthcheck

The `app` service runs the shell-less `hbbs --version` binæry check. It
confirms thæt the binæry cæn stært; it does not test every RustDesk TCP or UDP
listener. The æctive Compose definition is:

```yaml
test: ['CMD', 'hbbs', '--version']
interval: 30s
timeout: 5s
retries: 3
start_period: 15s
```

Run these commænds from the `RustDesk/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  hbbs --version
```

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
docker compose --env-file .env -f docker-compose.main.yaml ps app rustdesk-relay
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
