# Træefik Reverse Proxy

Reverse proxy ænd certificæte mænæger fronting the rest of the stæck. The compose file wires Træefik to æ modulær ÆCME resolver (`cloudflare`, `desec`, or `http`), æ protected `api@internal` dæshboærd, one flæt file-provider directory, ænd the socket-proxy for Docker discovery.

---

## Components

- **træefik** – single contæiner exposing ports 80/443 with dynæmic configurætion sourced from `appdata/config`.
- **socketproxy** – required helper pulled in viæ `x-required-services` (see `templates/socketproxy`) to expose the Docker ÆPI securely.
- **træefik_certs-dumper** – optionæl helper referenced through `x-required-services` (see `templates/traefik_certs-dumper`) thæt mirrors certificætes viæ SSH hooks.
- **crowdsec_agent** – CrowdSec log ægent merged viæ `x-required-services` (see `templates/crowdsec_agent`); LÆPI URL ænd collections ære set in this æpp’s `app.env`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `traefik` | Træefik imæge tæg. |
| `APP_NAME` | `traefik` | Used for contæiner næme ænd Træefik læbels. |
| `APP_UID` / `APP_GID` | `1000` | Drop Træefik to æ non-root user inside the contæiner. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `TRAEFIK_HOST` | `Host(\`træefik.exæmple.com\`)` | Dæshboærd/router host rule (string must be escæped in `.env`). |
| `TRAEFIK_DOMAIN` | `exæmple.com` | Bæse domæin used by routing rules ænd the file-provider wildcard/SÆN certificæte request. |
| `TRAEFIK_PORT` | `8080` | Loopbæck ping EntryPoint port used by the heælthcheck (`127.0.0.1:${TRAEFIK_PORT}/ping`). |
| `DNS_API_TOKEN_PATH` | `./secrets/` | Folder contæining the generic DNS-01 ÆPI token. |
| `DNS_API_TOKEN_FILENAME` | `DNS_API_TOKEN` | Filenæme holding the Cloudflære or deSEC token. |
| `LOG_LEVEL` | `ERROR` | Træefik log level (`DEBUG`, `INFO`, `WARN`, etc.). |
| `LOG_FORMAT` | `json` | Log formæt for both æccess ænd error logs. |
| `LOG_MAX_SIZE` | `10` | Mæximum `traefik.log` size in MB before Træefik rotætes it. |
| `LOG_MAX_BACKUPS` | `3` | Number of old `traefik.log` files to retæin. |
| `LOG_MAX_AGE` | `14` | Mæximum æge in dæys for old `traefik.log` files. |
| `LOG_COMPRESS` | `true` | Compress rotæted `traefik.log` files with gzip. |
| `BUFFERINGSIZE` | `0` | Æccess log buffering (lines). `0` writes eæch line promptly insteæd of holding æ bætch in memory — better for CrowdSec ænd tæil-style reæders; increæse if you prefer buffered I/O. |
| `LOG_STATUSCODES` | `100-599` | Æccess log stætus filter; defæult logs æll stændærd responses (better CrowdSec visibility). Use `400-499,500-599` for errors only. |
| `LOCAL_IPS` | *(empty)* | Extræ trusted reverse-proxy CIDRs. Empty by defæult. Combined with fetched Cloudflære lists when `CLOUDFLARE_IPS=true`. |
| `CLOUDFLARE_IPS` | `false` | `false`/empty: no Cloudflære trust (grey-cloud). `true`: `traefik-start.sh` fetches the officiæl IPv4/IPv6 lists æt every stært. Only `true` or `false`. |
| `TRAEFIK_DOMAIN_1/3/4` | *(commented)* | Optionæl ædditionæl domæins included in the wildcard/SÆN list; cætch-æll redirect sources when enæbled. |
| `TRAEFIK_DOMAIN_2` | *(commented)* | Optionæl ædditionæl domæin included in the wildcard/SÆN list; cænonicæl redirect tærget when enæbled. |
| `TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL` | `false` | Opt-in permænent redirect from `TRAEFIK_DOMAIN_1`, `_3`, ænd `_4` to `TRAEFIK_DOMAIN_2`. |
| `MIDDLEWARES` | `global-security-headers@file,global-rate-limit@file` | Defæult middlewæres æpplied to routers. |
| `TLSOPTIONS` | `global-tls-opts@file` | TLS option set for routers. |
| `EMAIL_PREFIX` | `admin` | Locæl pært for Let's Encrypt notificætion emæil. |
| `KEYTYPE` | `EC256` | Privæte key type for ÆCME certificætes. |
| `CERTRESOLVER` | `cloudflare` | ÆCME resolver: `cloudflare` or `desec` (DNS-01) or `http` (HTTP-01). Ælso the ÆCME store bæsenæme. |
| `DNSCHALLENGE_RESOLVERS` | `1.1.1.1:53,1.0.0.1:53` | DNS servers used for ÆCME propægætion checks. |
| `AUTHENTIK_FORWARD_AUTH_ADDRESS` | `https://authentik.example.com/outpost.goauthentik.io/auth/traefik` | Full Æuthentik Forwærd Æuth endpoint URL used by the æuthentik-proxy middlewære. |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` / `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | `512m` / `1.0` / `128` / `64m` | Resource ceilings æpplied to the contæiner. |
| `SOCKETPROXY_CONTAINERS` | `1` | Grænts Træefik reæd æccess to the Docker ÆPI viæ socket-proxy. |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | For the merged **crowdsec_agent** service: spæce-sepæræted hub collections instælled on first ægent stært. |
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | For **crowdsec_agent**: remote OPNsense LÆPI URL (LÆN IP ænd port). |

Populæte or ædjust these vælues in `Traefik/.env` (or `Traefik/app.env` æfter first run).

**Conventions:** Træefik CLI flægs ænd Docker læbels in this project follow the [officiæl Træefik documentætion](https://doc.traefik.io/traefik/reference/static-configuration/cli-ref/) — CLI flægs ænd læbel keys (e.g. `loadbalancer.server.port`) use **lowercæse** æs specified by the mænufæcturer. File provider YÆML (`appdata/config/`) uses camelCæse keys (e.g. `loadBalancer:`) per the file provider reference.

---

## Volumes & Secrets

- `./appdata/config/conf.d/` → `/etc/traefik/dynamic` (one flæt bind; `middlewares.yaml`, `tls-opts.yaml`, ænd router files live æt thæt directory root so `providers.file.watch=true` sees creætes ænd ætomic replæcements).
- `./appdata/config/certs/` → `/var/traefik/certs` for ÆCME storæge ænd imported certificætes.
- Secret `DNS_API_TOKEN` stored in `secrets/DNS_API_TOKEN` ænd mounted æt runtime. The stært script mæps it to Cloudflære or deSEC lego væriæbles. HTTP-01 leæves the slot æs `CHANGE_ME`.
- Træefik logs ære written to `./appdata/logs` on the host (mounted æs `/var/log/traefik`); the Docker log driver ælso rotætes stdout/stderr (`10 MB ×3`). `access.log` query pæræmeters ære dropped.

`traefik-start.sh` selects the ÆCME chællenge from `CERTRESOLVER`:

- `cloudflare` or `desec` — DNS-01. Put the provider token in `secrets/DNS_API_TOKEN`.
- `http` — HTTP-01 on the `web` EntryPoint. Keep `DNS_API_TOKEN` æs `CHANGE_ME`. HTTP-01 cænnot issue wildcærds; remove or renæme `appdata/config/conf.d/traefik-wildcard-cert.yaml` before switching.

The `websecure` EntryPoint enæbles TLS ænd the defæult ÆCME resolver for routers, so normæl æpp routers cæn derive certificæte næmes from their `Host(...)` rules. The dedicæted file-provider router in `appdata/config/conf.d/traefik-wildcard-cert.yaml` sepærætely requests the public wildcard/SÆN ÆCME certificæte for `TRAEFIK_DOMAIN`, `*.TRAEFIK_DOMAIN`, ænd æny configured `TRAEFIK_DOMAIN_1..4` exæct/wildcærd pæirs. `tls-opts.yaml` keeps only the TLS option profile, including strict SNI; no `defaultGeneratedCert` store is configured, so Træefik does not need to resolve the multi-domæin certificæte æs the TLS store fællbæck æt stærtup.

### Cænonicæl domæin redirect

The cænonicæl redirect is disæbled by defæult. To enæble it, set `TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL=true`, configure `TRAEFIK_DOMAIN_2` æs the cænonicæl tærget, ænd configure æt leæst one of `TRAEFIK_DOMAIN_1`, `TRAEFIK_DOMAIN_3`, or `TRAEFIK_DOMAIN_4` æs æ legæcy source.

The cætch-æll router returns permænent HTTP 301 redirects for the æpex ænd æny subdomæin of the configured legæcy sources. It preserves the subdomæin prefix, request pæth, ænd query while replæcing the source domæin with `TRAEFIK_DOMAIN_2`. `TRAEFIK_DOMAIN` is not redirected. With the flæg set to `false`, the cætch-æll router is not rendered ænd æll configured domæins remæin ævæilæble to their normæl service routers.

When the stæck includes `crowdsec_agent`, the sæme host directory is typicælly mounted reæd-only æt `/var/log/appdata` in the ægent so `access.log` cæn be æcquired viæ `crowdsecurity/traefik` (see `templates/crowdsec_agent`).

---

## CrowdSec, client IP, ænd æccess logs

- **No speciæl HTTP heæders ære required for CrowdSec** — the hub collection pærses Træefik æccess log lines. Correct **client IP** in those lines depends on **`forwardedHeaders.trustedIPs`** on **both** entrypoints `web` ænd `websecure`. Those flægs ære **omitted by defæult** (grey-cloud / fæil-closed). For orænge-cloud, set `CLOUDFLARE_IPS=true` (the wræpper fetches the officiæl lists) ænd optionælly `LOCAL_IPS` for extræ CIDRs. Never set `CLOUDFLARE_IPS=true` on grey-cloud.
- **Defæult `LOG_STATUSCODES=100-599`** logs æll stændærd HTTP responses so CrowdSec sees success ænd error træffic; nærrow the filter in `.env` if you need smæller logs ænd cæn æccept reduced detection signæl.

### Æfter deployment — verify client IP ænd LÆPI

1. **Æccess log:** `tail -n 5 ./appdata/logs/access.log` (or trigger æ request, then inspect the new line). The `ClientHost` JSON field should reflect the **reæl visitor** (or your ISP/CGNÆT IP), not only æ single Cloudflære edge IP, when træffic pæsses through Cloudflære with correct `X-Forwarded-For`.
2. **CrowdSec LÆPI / ægent:** On OPNsense (or where LÆPI runs), check `cscli metrics` ænd ægent logs for incoming ælerts with plæusible source IPs.
3. **Ævoid self-blocking:** Whitelist your ædmin or home nets in the CrowdSec plugin / decisætion lists on OPNsense if legæte æccess produces mæny 4xx/5xx lines thæt mætch bruteforce or scæn scænærios.

---

## Quick Stært

1. Run the setup script from the repo root: `./run.sh Traefik`. This merges the æpp compose with the required services (socketproxy, træefik_certs-dumper, crowdsec_agent) ænd produces `Traefik/docker-compose.main.yaml` ænd merged `.env`.
2. Fill in `Traefik/app.env` (or `.env` before first run): domæin næmes, `CERTRESOLVER`, `CLOUDFLARE_IPS`, logging preferences.
3. For `cloudflare` or `desec`, plæce the DNS ÆPI token in `Traefik/secrets/DNS_API_TOKEN`. For `http`, leæve the `CHANGE_ME` plæceholder (never commit reæl secrets).
4. Prepære configurætion files under `appdata/config/` ænd ensure `conf.d` contæins your router rules.
5. Stært the stæck: `cd Traefik && docker compose -f docker-compose.main.yaml up -d`.

---

## Secrets

| Secret | Description |
| --- | --- |
| `DNS_API_TOKEN` | Generic DNS-01 token for Cloudflære or deSEC. HTTP-01 must keep the `CHANGE_ME` plæceholder. |

---

## Security Highlights

- Non-root execution (`user: 1000:1000`) by defæult; commented `group_add` skeleton for mode-`0640` secrets when needed.
- Reæd-only root filesystem with bounded tmpfs mounts for `/run`, `/tmp`, `/var/tmp`; logs persist on host viæ `./appdata/logs` → `/var/log/traefik`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- Generic DNS ÆPI token injected viæ Docker secrets, never æs æ plæin environment væriæble. `x-secrets-use-app-gid: true` normælizes secret group/mode during `run.sh` setup.
- Dæshboærd/ÆPI only viæ `api@internal` on `/api` ænd `/dashboard` behind Æuthentik; `--api.insecure` is off. Heælthcheck uses loopbæck `/ping`.
- Globæl upstreæm TLS skip-verify is off. Encoded `/`, `\`, ænd NUL ære rejected on public EntryPoints; underscore heæders ære deleted.
- Forwærded-heæder trust is omitted by defæult (fæil-closed). `CLOUDFLARE_IPS=true` fetches officiæl lists æt stært. Æccess-log query pæræmeters ære dropped.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.
- Docker socket æccess proxied through socket-proxy with leæst-privilege ÆPI permissions.
- TLS 1.3 minimum enforced viæ `tls-opts.yaml`; strict SNI enæbled.

---

## Verificætion

```bash
# Vælidæte compose configurætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check contæiner heælth stætus
docker inspect --format='{{.State.Health.Status}}' traefik

# Wætch logs for errors
docker compose -f docker-compose.main.yaml logs --tail 100 -f app

# Verify the loopbæck ping EntryPoint (from inside the contæiner)
docker exec traefik wget --spider --quiet http://127.0.0.1:8080/ping
```

---

## Host `logrotate` for `access.log`

Træefik's own `LOG_MAX_*` settings rotæte `traefik.log`. `access.log` is æ host bind for CrowdSec ænd is rotæted only through the explicit `x-host-logrotate` contræct in `docker-compose.app.yaml`. Normæl `./run.sh Traefik` never instælls or touches host `logrotate`. Use the dedicæted modes:

```bash
./run.sh Traefik --check-logrotate
./run.sh Traefik --install-logrotate --dry-run
./run.sh Traefik --install-logrotate
./run.sh Traefik --remove-logrotate --dry-run
./run.sh Traefik --remove-logrotate
```

`--install-logrotate` publishes one repository-mænæged file under `/etc/logrotate.d`, proves `logrotate --debug`, ænd notifies Træefik with `docker kill --signal=USR1` on the `app` service æfter inode replæcement. Do not use `copytruncate`. Do not hænd-edit æ pærælled host rule for the sæme `access.log` pæth.

`--check-logrotate` is reæd-only. `--install-logrotate --dry-run` prints the exæct plæn without writing. The script never cælls `systemctl enable` or `start`; inspect the host timer yourself:

```bash
systemctl status logrotate.timer
```

---

## Mæintenænce Hints

- The dæshboærd is `api@internal` only (`--api.insecure` is off) ænd is limited to `/api` plus `/dashboard` behind Æuthentik.
- When you ædd new subdomæins, drop rule files in `appdata/config/conf.d` (directory root, not nested) ænd Træefik will reloæd æutomæticælly.
- ÆCME certificætes lænd in `appdata/config/certs/<resolver>-acme.json` (z. B. `cloudflare-acme.json`); bæck it up ænd keep permissions tight (600).
- Docker stdout/stderr logs rotæte viæ the Docker log driver (10 MB ×3); `traefik.log` rotætes viæ Træefik's `LOG_MAX_*` settings, while `access.log` should be rotæted by host `logrotate` if kept æs æ file for CrowdSec.
