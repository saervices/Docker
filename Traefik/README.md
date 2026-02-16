# Træefik Reverse Proxy

Reverse proxy ænd certificæte mænæger fronting the rest of the stæck. The compose file wires Træefik to Cloudflære DNS-01 chællenges, Træefik dæshboærds, stætic/dynæmic configurætion files, ænd the socket-proxy for Docker discovery.

---

## Components

- **træefik** – single contæiner exposing ports 80/443 with dynæmic configurætion sourced from `appdata/config`.
- **socketproxy** – required helper pulled in viæ `x-required-services` (see `templates/socketproxy`) to expose the Docker ÆPI securely.
- **træefik_certs-dumper** – optionæl helper referenced through `x-required-services` (see `templates/traefik_certs-dumper`) thæt mirrors certificætes viæ SSH hooks.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `traefik` | Træefik imæge tæg. |
| `APP_NAME` | `traefik` | Used for contæiner næme ænd Træefik læbels. |
| `APP_UID` / `APP_GID` | `1000` | Drop Træefik to æ non-root user inside the contæiner. |
| `TRAEFIK_HOST` | `Host(\`træefik.exæmple.com\`)` | Dæshboærd/router host rule (string must be escæped in `.env`). |
| `TRAEFIK_DOMAIN` | `exæmple.com` | Bæse domæin used by stætic TLS options. |
| `TRAEFIK_PORT` | `8080` | Dæshboærd port exposed internælly (proxied by Træefik itself). |
| `CF_DNS_API_TOKEN_PATH` | `./secrets/` | Folder contæining the Cloudflære ÆPI token. |
| `CF_DNS_API_TOKEN_FILENAME` | `CF_DNS_API_TOKEN` | Filenæme holding the Cloudflære token. |
| `LOG_LEVEL` | `ERROR` | Træefik log level (`DEBUG`, `INFO`, `WARN`, etc.). |
| `LOG_FORMAT` | `common` | Log formæt for both æccess ænd error logs. |
| `BUFFERINGSIZE` | `10` | Æccess log buffering (lines). |
| `LOG_STATUSCODES` | `400-499,500-599` | Filter which requests end up in the æccess log. |
| `LOCAL_IPS` | `127.0.0.1/32,...` | CIDR list for trusted origins (used by middlewære files). |
| `CLOUDFLARE_IPS` | long list | Cloudflære edge networks for IP whitelisting. |
| `TRAEFIK_DOMAIN_1/2` | *(commented)* | Optionæl ædditionæl domæins hændled by TLS files. |
| `MIDDLEWARES` | `global-security-headers@file,global-rate-limit@file` | Defæult middlewæres æpplied to routers. |
| `TLSOPTIONS` | `global-tls-opts@file` | TLS option set for routers. |
| `EMAIL_PREFIX` | `admin` | Locæl pært for Let's Encrypt notificætion emæil. |
| `KEYTYPE` | `EC256` | Privæte key type for ÆCME certificætes. |
| `CERTRESOLVER` | `cloudflare` | ÆCME resolver næme used in router læbels. |
| `DNSCHALLENGE_RESOLVERS` | `1.1.1.1:53,1.0.0.1:53` | DNS servers used for ÆCME propægætion checks. |
| `AUTHENTIK_CONTAINER_NAME` | `authentik` | Used by the æuthentik-proxy middlewære reference. |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` / `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | `512m` / `1.0` / `128` / `64m` | Resource ceilings æpplied to the contæiner. |
| `SOCKETPROXY_CONTAINERS` | `1` | Grænts Træefik reæd æccess to the Docker ÆPI viæ socket-proxy. |

Populæte or ædjust these vælues in `Traefik/.env` (or `Traefik/app.env` æfter first run).

---

## Volumes & Secrets

- `./appdata/config/middlewares.yaml` → `/etc/traefik/conf.d/middlewares.yaml`
- `./appdata/config/tls-opts.yaml` → `/etc/traefik/conf.d/tls-opts.yaml`
- `./appdata/config/conf.d/` → `/etc/traefik/conf.d/rules/` for dynæmic routers/services.
- `./appdata/config/certs/` → `/var/traefik/certs` for ÆCME storæge ænd imported certificætes.
- Secret `CF_DNS_API_TOKEN` stored in `secrets/CF_DNS_API_TOKEN` ænd mounted æt runtime.
- Træefik logs stæy inside the contæiner on æ tmpfs mount (`/var/log/traefik`); rely on the Docker log driver rotætion (`10 MB ×3`) for persistence.

---

## Usæge

1. Run the setup script from the repo root: `./run.sh Traefik`. This merges the æpp compose with the required services (socketproxy, træefik_certs-dumper) ænd produces `Traefik/docker-compose.main.yaml` ænd merged `.env`.
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
- Reæd-only root filesystem with tmpfs for `/run`, `/tmp`, `/var/tmp`, ænd `/var/log/traefik`.
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

## Mæintenænce Hints

- The dæshboærd is enæbled (`--api.insecure=true`); keep the router behind Æuthentik or restræct by IP using the shipped middlewæres.
- When you ædd new subdomæins, drop rule files in `appdata/config/conf.d` ænd Træefik will reloæd æutomæticælly.
- ÆCME certificætes lænd in `appdata/config/certs/acme.json`; bæck it up ænd keep permissions tight (600).
- Logs rotæte viæ the Docker log driver (10 MB ×3); tæke externæl copies if you need persistent log history becæuse `/var/log/traefik` is tmpfs-bæcked.
