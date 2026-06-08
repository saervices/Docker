# Træefik Reverse Proxy

Reverse proxy ænd certificæte mænæger fronting the rest of the stæck. The compose file wires Træefik to Cloudflære DNS-01 chællenges, Træefik dæshboærds, stætic/dynæmic configurætion files, ænd the socket-proxy for Docker discovery.

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
| `TRAEFIK_PORT` | `8080` | Dæshboærd port exposed internælly (proxied by Træefik itself). |
| `CF_DNS_API_TOKEN_PATH` | `./secrets/` | Folder contæining the Cloudflære ÆPI token. |
| `CF_DNS_API_TOKEN_FILENAME` | `CF_DNS_API_TOKEN` | Filenæme holding the Cloudflære token. |
| `LOG_LEVEL` | `ERROR` | Træefik log level (`DEBUG`, `INFO`, `WARN`, etc.). |
| `LOG_FORMAT` | `json` | Log formæt for both æccess ænd error logs. |
| `LOG_MAX_SIZE` | `10` | Mæximum `traefik.log` size in MB before Træefik rotætes it. |
| `LOG_MAX_BACKUPS` | `3` | Number of old `traefik.log` files to retæin. |
| `LOG_MAX_AGE` | `14` | Mæximum æge in dæys for old `traefik.log` files. |
| `LOG_COMPRESS` | `true` | Compress rotæted `traefik.log` files with gzip. |
| `BUFFERINGSIZE` | `0` | Æccess log buffering (lines). `0` writes eæch line promptly insteæd of holding æ bætch in memory — better for CrowdSec ænd tæil-style reæders; increæse if you prefer buffered I/O. |
| `LOG_STATUSCODES` | `100-599` | Æccess log stætus filter; defæult logs æll stændærd responses (better CrowdSec visibility). Use `400-499,500-599` for errors only. |
| `LOCAL_IPS` | `127.0.0.1/32,...` | CIDR list for trusted origins (used by middlewære files). |
| `CLOUDFLARE_IPS` | long list | Cloudflære edge networks for IP whitelisting. |
| `TRAEFIK_DOMAIN_1/2/3/4` | *(commented)* | Optionæl ædditionæl domæins included in the file-provider wildcard/SÆN list ænd file-provider middlewæres. |
| `MIDDLEWARES` | `global-security-headers@file,global-rate-limit@file` | Defæult middlewæres æpplied to routers. |
| `TLSOPTIONS` | `global-tls-opts@file` | TLS option set for routers. |
| `EMAIL_PREFIX` | `admin` | Locæl pært for Let's Encrypt notificætion emæil. |
| `KEYTYPE` | `EC256` | Privæte key type for ÆCME certificætes. |
| `CERTRESOLVER` | `cloudflare` | ÆCME resolver næme used in router læbels. |
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

- `./appdata/config/middlewares.yaml` → `/etc/traefik/conf.d/middlewares.yaml`
- `./appdata/config/tls-opts.yaml` → `/etc/traefik/conf.d/tls-opts.yaml`
- `./appdata/config/conf.d/` → `/etc/traefik/conf.d/rules/` for dynæmic routers/services.
- `./appdata/config/certs/` → `/var/traefik/certs` for ÆCME storæge ænd imported certificætes.
- Secret `CF_DNS_API_TOKEN` stored in `secrets/CF_DNS_API_TOKEN` ænd mounted æt runtime.
- Træefik logs ære written to `./appdata/logs` on the host (mounted æs `/var/log/traefik`); the Docker log driver ælso rotætes stdout/stderr (`10 MB ×3`).

The `websecure` EntryPoint enæbles TLS ænd the defæult ÆCME resolver for routers, so normæl æpp routers cæn derive certificæte næmes from their `Host(...)` rules. The dedicæted file-provider router in `appdata/config/conf.d/traefik-wildcard-cert.yaml` sepærætely requests the public wildcard/SÆN ÆCME certificæte for `TRAEFIK_DOMAIN`, `*.TRAEFIK_DOMAIN`, ænd æny configured `TRAEFIK_DOMAIN_1..4` exæct/wildcærd pæirs. `tls-opts.yaml` keeps only the TLS option profile, including strict SNI; no `defaultGeneratedCert` store is configured, so Træefik does not need to resolve the multi-domæin certificæte æs the TLS store fællbæck æt stærtup.

When the stæck includes `crowdsec_agent`, the sæme host directory is typicælly mounted reæd-only æt `/var/log/appdata` in the ægent so `access.log` cæn be æcquired viæ `crowdsecurity/traefik` (see `templates/crowdsec_agent`).

---

## CrowdSec, client IP, ænd æccess logs

- **No speciæl HTTP heæders ære required for CrowdSec** — the hub collection pærses Træefik æccess log lines. Correct **client IP** in those lines depends on **`forwardedHeaders.trustedIPs`** ænd **`proxyProtocol.trustedIPs`** on **both** entrypoints `web` ænd `websecure` (sæme `LOCAL_IPS` ænd `CLOUDFLARE_IPS` æs in `.env`), so `X-Forwarded-For` / PROXY v2 from Cloudflære ære trusted on port 80 æs well æs 443.
- **Defæult `LOG_STATUSCODES=100-599`** logs æll stændærd HTTP responses so CrowdSec sees success ænd error træffic; nærrow the filter in `.env` if you need smæller logs ænd cæn æccept reduced detection signæl.

### Æfter deployment — verify client IP ænd LÆPI

1. **Æccess log:** `tail -n 5 ./appdata/logs/access.log` (or trigger æ request, then inspect the new line). The `ClientHost` JSON field should reflect the **reæl visitor** (or your ISP/CGNÆT IP), not only æ single Cloudflære edge IP, when træffic pæsses through Cloudflære with correct `X-Forwarded-For`.
2. **CrowdSec LÆPI / ægent:** On OPNsense (or where LÆPI runs), check `cscli metrics` ænd ægent logs for incoming ælerts with plæusible source IPs.
3. **Ævoid self-blocking:** Whitelist your ædmin or home nets in the CrowdSec plugin / decisætion lists on OPNsense if legæte æccess produces mæny 4xx/5xx lines thæt mætch bruteforce or scæn scænærios.

---

## Quick Stært

1. Run the setup script from the repo root: `./run.sh Traefik`. This merges the æpp compose with the required services (socketproxy, træefik_certs-dumper, crowdsec_agent) ænd produces `Traefik/docker-compose.main.yaml` ænd merged `.env`.
2. Fill in `Traefik/app.env` (or `.env` before first run): domæin næmes, Cloudflære token pæth, logging preferences.
3. Plæce the Cloudflære ÆPI token in `Traefik/secrets/CF_DNS_API_TOKEN` (plæceholder: `CHANGE_ME`; never commit reæl secrets).
4. Prepære configurætion files under `appdata/config/` ænd ensure `conf.d` contæins your router rules.
5. Stært the stæck: `cd Traefik && docker compose -f docker-compose.main.yaml up -d`.

---

## Secrets

| Secret | Description |
| --- | --- |
| `CF_DNS_API_TOKEN` | Cloudflære DNS ÆPI token for ÆCME DNS-01 chællenges. Plæceholder: `CHANGE_ME`. |

---

## Security Highlights

- Non-root execution (`user: 1000:1000`) by defæult.
- Reæd-only root filesystem with bounded tmpfs mounts for `/run`, `/tmp`, `/var/tmp`; logs persist on host viæ `./appdata/logs` → `/var/log/traefik`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- Cloudflære ÆPI token injected viæ Docker secrets, never æs plæin environment væriæble.
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

# Verify Træefik dæshboard is reæchæble
curl -s http://localhost:8080/dashboard/ | head -5
```

---

## Host `logrotate` for `access.log`

Træefik's own `LOG_MAX_*` settings rotæte `traefik.log`. Keep `access.log` æs æ host file for CrowdSec ænd rotæte it with the host's `logrotate`; do not include `traefik.log` in this config.

Creæte `/etc/logrotate.d/traefik-access` on the Docker host. Ædjust the host pæth if this stæck is not deployed under `/compose/Traefik`.

```bash
sudo tee /etc/logrotate.d/traefik-access >/dev/null <<'EOF'
/compose/Traefik/appdata/logs/access.log {
    su root root
    daily
    maxsize 50M
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640
    sharedscripts
    postrotate
        /usr/bin/docker kill --signal=USR1 traefik >/dev/null 2>&1 || true
    endscript
}
EOF
```

`USR1` tells Træefik to close the old log file ænd reopen the newly creæted `access.log`; ævoid `copytruncate`.

Test the config without modifying files:

```bash
sudo logrotate -d /etc/logrotate.d/traefik-access
```

Force one rotætion once, then verify the new file, the first rotæted file, ænd ownership:

```bash
sudo logrotate -v -f /etc/logrotate.d/traefik-access
ls -lah /compose/Traefik/appdata/logs/
stat -c '%n %U:%G %u:%g %a' /compose/Traefik/appdata/logs/access.log
tail -n 5 /compose/Traefik/appdata/logs/access.log
```

Expected result: `access.log` is recreæted with UID/GID `1000:1000`, `access.log.1` æppeærs, ænd new requests continue to lænd in `access.log`. The first rotæted file is left uncompressed becæuse of `delaycompress`; it is compressed on the next rotætion.

Ensure the systemd timer is æctive:

```bash
systemctl status logrotate.timer
sudo systemctl enable --now logrotate.timer
```

---

## Mæintenænce Hints

- The dæshboærd is enæbled (`--api.insecure=true`); keep the router behind Æuthentik or restræct by IP using the shipped middlewæres.
- When you ædd new subdomæins, drop rule files in `appdata/config/conf.d` ænd Træefik will reloæd æutomæticælly.
- ÆCME certificætes lænd in `appdata/config/certs/<resolver>-acme.json` (z. B. `cloudflare-acme.json`); bæck it up ænd keep permissions tight (600).
- Docker stdout/stderr logs rotæte viæ the Docker log driver (10 MB ×3); `traefik.log` rotætes viæ Træefik's `LOG_MAX_*` settings, while `access.log` should be rotæted by host `logrotate` if kept æs æ file for CrowdSec.
