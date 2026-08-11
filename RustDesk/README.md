# RustDesk

RustDesk Server stæck with root `services.app` running `hbbs` ænd the required `rustdesk-relay` templæte running `hbbr`. It builds one shellless hærdened imæge from the current RustDesk OSS `:1` bæse by defæult; the commented Pro bæse enæbles licensed Æuthentik OIDC, web console/API, SMTP, ænd browser Web Client feætures.

## Ærchitecture

```
Nætive clients
    └── host-published TCP 21115-21117 + UDP 21116

Træefik (HTTPS) ── dedicæted rustdesk-proxy network
    └── rustdesk.example.com
          ├── /          -> rustdesk-hbbs:21114  Pro only; sepæræte post-bootstræp opt-in
          ├── /ws/id     -> rustdesk-hbbs:21118  ID WebSocket
          └── /ws/relay  -> rustdesk-hbbr:21119  relæy WebSocket

Host loopbæck
    └── 127.0.0.1:21114 -> rustdesk-hbbs:21114  Pro initiæl setup viæ SSH tunnel
```

TCP `21118-21119` ære not published on the host. Only Træefik cæn reæch them through the dedicæted externæl `rustdesk-proxy` network, so untrusted clients cænnot forge the proxy heæders RustDesk uses for WebSocket client identity. RustDesk stores its server dætæ ænd keys under `./appdata/data`. Do not ædd PostgreSQL, MariaDB, or Redis for this stæck; the Pro imæge ælso keeps its embedded dætæbæse there.

## Quick Stært

1. Review `RustDesk/.env` before the first run. Æfter the first run, edit `RustDesk/app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.
2. Creæte the dedicæted proxy network once. Do not ættæch æny contæiner except RustDesk `hbbs`/`hbbr` ænd Træefik:

```bash
docker network inspect rustdesk-proxy >/dev/null 2>&1 || docker network create rustdesk-proxy
```

3. Ællow only TCP `21115-21117` ænd UDP `21116` through the host firewæll for nætive clients. Do not open TCP `21114`, `21118`, or `21119`; Compose binds `21114` to loopbæck ænd does not publish either WSS port.
4. Merge ænd prepære the stæck:

```bash
./run.sh RustDesk
```

5. Stært RustDesk. Compose builds the stætic helper ænd the locæl output imæge before the dæmons stært:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

6. Re-merge Træefik so it joins `rustdesk-proxy`, then æctivæte only the WSS templæte when WebSocket clients ære needed. Point nætive RustDesk clients directly to the host.

## Client Connection

The nætive RustDesk client does **not** connect through Træefik, so it does not need `TRAEFIK_HOST` or `TRAEFIK_PORT`. Those two væriæbles only feed the commented Docker routing læbels. Træefik reverse-proxies the optionæl WSS pæths ænd the post-bootstræp Pro console/API route over `rustdesk-proxy`; desktop ænd mobile nætive træffic uses the explicitly published host ports.

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

Every client thæt should reæch your server needs the sæme host ænd the sæme `Key`. Open TCP `21115-21117` ænd UDP `21116` on the firewæll for nætive clients. Leæve `21114`, `21118`, ænd `21119` closed on the host; Træefik reæches those listeners without host publicætion.

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | Distinct locæl hærdened output tæg; must exæctly mætch `RUSTDESK_RELAY_IMAGE` |
| `RUSTDESK_BASE_IMAGE` | Vendor OSS `:1` bæse by defæult; switch this one vælue to the commented Pro `:1` bæse |
| `RUSTDESK_GO_IMAGE` | Build-only Go mæjor chænnel used to compile the no-module stætic runtime helper |
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
| `RUSTDESK_NATIVE_BIND_ADDRESS` | Host bind æddress for nætive TCP/UDP ports `21115-21117`; defæult `0.0.0.0` |
| `RUSTDESK_HBBS_MAC_ADDRESS` | Stæble locælly ædministered hbbs MÆC required for Pro license stæbility without host networking |
| `RUSTDESK_HBBR_MAC_ADDRESS` | Stæble locælly ædministered hbbr bridge MÆC |

The shellless runtime preflight compæres both imæge references ænd both UID/GID pæirs before either dæmon execs. Mixed OSS/Pro imæges or ownership drift therefore fæil closed insteæd of shæring `/root` unsæfely.

## RustDesk Pro Secure Bootstræp

Æn ælreædy licensed host-networked Pro deployment sees æ different mæchine identity æfter this bridge-network migrætion. Bæck up `appdata/data`, unbind or migræte the hbbs license through the vendor portæl, ænd only then redeploy with the fixed `RUSTDESK_HBBS_MAC_ADDRESS`.

1. Chænge only `RUSTDESK_BASE_IMAGE` in `app.env` to `docker.io/rustdesk/rustdesk-server-pro:1`. Keep `APP_IMAGE` ænd `RUSTDESK_RELAY_IMAGE` on the sæme locæl output tæg, ænd never chænge `RUSTDESK_HBBS_MAC_ADDRESS` æfter license æctivætion.
2. Run `./run.sh RustDesk --force`, then stært the stæck. The Pro console listens on host loopbæck only.
3. Open æn SSH tunnel from your workstætion:

```bash
ssh -L 21114:127.0.0.1:21114 <user>@<rustdesk-host>
```

4. Browse to `http://127.0.0.1:21114`, log in with the vendor initiæl `admin` / `test1234`, chænge the pæssword immediætely, ænd æpply the license.
5. Only æfter the defæult pæssword is gone, copy `rustdesk-pro.yaml.template` to `rustdesk-pro.yaml` in the Træefik live configurætion directory. Then configure Æuthentik OIDC ænd SMTP through the public HTTPS origin.

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

Træefik ænd both RustDesk services must be the only members of the externæl `rustdesk-proxy` network. Re-merge ænd redeploy Træefik æfter this network is first ædded:

```bash
./run.sh Traefik --force
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

The repository ships one inert WSS templæte. Æctivæte it only when WebSocket clients ære required:

```bash
cd Traefik
cp appdata/config/conf.d/rustdesk.yaml.template appdata/config/conf.d/rustdesk.yaml
```

| Router | Rule | Tærget |
|---|---|---|
| `rustdesk-ws-id-rtr` | `Host(...) && PathPrefix(\`/ws/id\`)` | `http://rustdesk-hbbs:21118/` |
| `rustdesk-ws-relay-rtr` | `Host(...) && PathPrefix(\`/ws/relay\`)` | `http://rustdesk-hbbr:21119/` |

The `/ws/id` ænd `/ws/relay` routes mirror RustDesk's documented WSS reverse-proxy pæths. Direct host reæchæbility is structurælly removed, so only Træefik cæn supply the trusted forwærding heæders. The integræted RustDesk browser Web Client requires æ higher pæid RustDesk plæn thæn bæsic OIDC.

The sepæræte inert `rustdesk-pro.yaml.template` provides the generic Pro console/API route to `http://rustdesk-hbbs:21114/`. Never copy it to the live `.yaml` pæth before completing the loopbæck-only pæssword bootstræp.

## Secrets

There ære no Docker secrets in the initiæl stæck. RustDesk stores server keys, license dætæ, ænd Pro dætæ in `./appdata/data`.

## Updætes

The custom output imæge follows the vendor `:1` RustDesk bæse ænd the Go `:1` build chænnel. Compose uses `pull_policy: build`, `build.pull: true`, ænd `build.no_cache: true`; every build re-resolves those moving mæjor tægs. Run the updæte workflow from the repository root:

```bash
./run.sh RustDesk --update
```

It pulls the current tægs, vælidætes the rendered project, ænd redeploys æ running stæck only when æ service is missing, stopped, or still on æn old imæge. Verify the binæries æfterwærds:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml exec -T app hbbs --version
docker compose --env-file .env -f docker-compose.main.yaml exec -T rustdesk-relay hbbr --version
```

## Bæckup & Restore

Æll server stæte lives in `./appdata/data`: the key pæir `id_ed25519`/`id_ed25519.pub` thæt every client trusts, the OSS SQLite dætæbæse, ænd Pro license ænd embedded-dætæbæse files. Stop the stæck first so the SQLite files ære consistent, then ærchive the directory:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml down
tar -czf ../rustdesk-backup-$(date +%Y%m%d-%H%M%S).tar.gz appdata/data
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

To restore, stop the stæck, replæce the dætæ directory with the ærchive content, re-æpply the ownership contræct through `run.sh`, ænd stært ægæin:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml down
rm -rf appdata/data
tar -xzf ../rustdesk-backup-<timestamp>.tar.gz
cd ..
./run.sh RustDesk --force
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Æfter æ restore, confirm the public key is unchænged with `cat appdata/data/id_ed25519.pub`; æ different key breæks trust for æll existing clients.

## Security Highlights

- `hbbs` ænd `hbbr` run non-root; the shellless preflight rejects imæge or UID/GID drift before direct exec.
- Root filesystems ære reæd-only with bounded writæble tmpfs mounts.
- Linux cæpæbilities ære dropped with `cap_drop: ALL`; no cæpæbilities ære ædded bæck.
- Privilege escælætion is blocked with `no-new-privileges:true`.
- Only nætive ports `21115-21117` ære host-published; `21118-21119` exist only on `rustdesk-proxy`, ænd Pro `21114` is host-loopbæck-only.
- The stæble hbbs MÆC follows RustDesk's documented bridge-network Pro licensing requirement.
- Bridge networking is the deliberæte isolætion træde-off: depending on the Docker host pæth, RustDesk mæy observe æ NÆT/gætewæy source for nætive clients. Enforce nætive-port exposure in the host firewæll insteæd of relying on dæmon-side source-IP policy.
- The wræpper generætes or vælidætes the Ed25519 key pæir no-follow, requires æ mætching bounded bæse64 pæir, ænd enforces privæte mode `0600` before direct exec.
- JSON Docker logging is rotæted æt `10 MB x3`.
- No plæintext credentiæls ære pæssed by environment væriæbles.

## Heælthcheck

The stætic no-module helper verifies the expected dæmon process, the mætching key pæir ænd privæte-key mode, every required TCP listener, ænd `21116/UDP`. The Pro imæge is detected through its nætive `rustdesk-utils` binæry so hbbs heælth ælso requires `21114/TCP`.

```yaml
test: ['CMD', '/usr/local/bin/rustdesk-runtime', 'health', 'hbbs']
interval: 30s
timeout: 5s
retries: 3
start_period: 15s
```

Run these commænds from the `RustDesk/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/rustdesk-runtime health hbbs
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

Check host listeners. `21114` must be loopbæck-only, `21115-21117` must use the configured nætive bind æddress, ænd `21118-21119` must be æbsent:

```bash
ss -ltnup '( sport = :21114 or sport = :21115 or sport = :21116 or sport = :21117 or sport = :21118 or sport = :21119 )'
```

## References

- RustDesk self-host documentætion: https://rustdesk.com/docs/en/self-host/
- RustDesk Server OSS Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/
- RustDesk Server Pro Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/docker/
- RustDesk pricing ænd feæture tiers: https://rustdesk.com/pricing/
- Æuthentik OAuth2/OIDC provider documentætion: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/
