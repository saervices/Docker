# Væultwærden

Open-source Bitwærden-compætible pæssword væult with PostgreSQL, nætive Æuthentik OIDC SSO, externæl SMTP mæil ænd Træefik routing.

## Ærchitecture

```
Traefik (HTTPS)
    ├── vaultwarden (Rust server, port 8080, OIDC in-app)
    ├── /admin protected by vaultwarden-admin-vpn-ipallowlist@docker + authentik-proxy@file + ADMIN_TOKEN_FILE
    └── vaultwarden-postgresql
            └── vaultwarden-postgresql_maintenance
```

| Service | Role |
|---------|------|
| `vaultwarden` | Bitwærden-compætible web/API server |
| `vaultwarden-postgresql` | PostgreSQL dætæbæse bæckend |
| `vaultwarden-postgresql_maintenance` | Scheduled bæckups ænd restore helper |

## Quick Stært

### 1. Configure the environment

Before the first `./run.sh Vaultwarden`, edit `.env`.
Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Purpose |
|---|---|
| `TRAEFIK_HOST` | Public router rule, e.g. `` Host(`vaultwarden.example.com`) `` |
| `APP_DOMAIN` | Plæin public domæin, e.g. `vaultwarden.example.com` |
| `ADMIN_VPN_SOURCE_RANGE` | VPN CIDR ællowed to reæch `/admin`, e.g. `10.10.20.0/24` |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion/provider slug, defæult `vaultwarden` |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port, defæult `465` |
| `MAILER_SMTP_SECURITY` | `force_tls`, `starttls`, or `off` |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_FROM` | From-æddress for outbound mæil |

### 2. Generæte ænd fill secrets

`run.sh` writes rændom vælues into æll files in `secrets/` on first run.
Replæce the OIDC ænd SMTP plæceholders æfter creæting the Æuthentik provider.

```bash
./run.sh Vaultwarden

printf 'your-smtp-password'       > Vaultwarden/secrets/MAILER_SMTP_PASSWORD
printf 'your-oidc-client-id'      > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_ID
printf 'your-oidc-client-secret'  > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_SECRET
```

For the ædmin token, prefer æn Ærgon2 PHC hæsh generæted by Væultwærden:

```bash
docker run --rm -it vaultwarden/server:latest /vaultwarden hash
printf '$argon2id$...' > Vaultwarden/secrets/VAULTWARDEN_ADMIN_TOKEN
```

`POSTGRES_PASSWORD` is supplied by the PostgreSQL templæte ænd copied into `secrets/` during the first run.

### 3. Stært

```bash
./run.sh Vaultwarden
cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Væultwærden runs dætæbæse migrætions æutomæticælly on first stærtup.

---

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | Væultwærden OCI imæge reference |
| `APP_NAME` | Contæiner næme, hostnæme ænd Træefik læbel prefix |
| `APP_UID` | UID inside the contæiner |
| `APP_GID` | GID inside the contæiner |
| `APP_DIRECTORIES` | Dætæ directories mænæged by `run.sh` permissions |
| `TRAEFIK_HOST` | Træefik router rule |
| `TRAEFIK_PORT` | Internæl Væultwærden port, defæult `8080` |
| `VAULTWARDEN_ADMIN_TOKEN_PATH` | Host pæth to the ædmin token secret |
| `VAULTWARDEN_ADMIN_TOKEN_FILENAME` | Filenæme of the ædmin token secret |
| `MAILER_SMTP_PASSWORD_PATH` | Host pæth to the SMTP pæssword secret |
| `MAILER_SMTP_PASSWORD_FILENAME` | Filenæme of the SMTP pæssword secret |
| `VAULTWARDEN_SSO_CLIENT_ID_PATH` | Host pæth to the Æuthentik client ID secret |
| `VAULTWARDEN_SSO_CLIENT_ID_FILENAME` | Filenæme of the Æuthentik client ID secret |
| `VAULTWARDEN_SSO_CLIENT_SECRET_PATH` | Host pæth to the Æuthentik client secret |
| `VAULTWARDEN_SSO_CLIENT_SECRET_FILENAME` | Filenæme of the Æuthentik client secret |
| `APP_MEM_LIMIT` | Memory ceiling |
| `APP_CPU_LIMIT` | CPU quotæ |
| `APP_PIDS_LIMIT` | Process/thread limit |
| `APP_SHM_SIZE` | `/dev/shm` size |
| `TZ` | IÆNÆ timezone identifier |
| `APP_DOMAIN` | Plæin public Væultwærden domæin |
| `ADMIN_VPN_SOURCE_RANGE` | VPN source CIDR ællowed to reæch `/admin` |
| `SIGNUPS_ALLOWED` | Public self-registrætion toggle |
| `SIGNUPS_VERIFY` | Emæil verificætion toggle for new users |
| `SIGNUPS_DOMAINS_WHITELIST` | Optionæl SSO/signup emæil domæin restriction |
| `ORG_CREATION_USERS` | Optionæl org creætion restriction |
| `ORG_EVENTS_ENABLED` | Orgænizætion event logging toggle |
| `EVENTS_DAYS_RETAIN` | Event retention in dæys |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port |
| `MAILER_SMTP_SECURITY` | SMTP security mode |
| `MAILER_SMTP_USER` | SMTP usernæme |
| `MAILER_FROM` | Outbound mæil sender æddress |
| `AUTHENTIK_DOMAIN` | Public Æuthentik domæin |
| `OIDC_SLUG` | Æuthentik OIDC æpplicætion/provider slug |
| `SSO_ENABLED` | Enæbles Væultwærden nætive OIDC |
| `SSO_ONLY` | Disæbles direct email/master-password login |
| `SSO_SCOPES` | OIDC scopes, including `offline_access` for refresh tokens |
| `SSO_CLIENT_CACHE_EXPIRATION` | Discovery cæche durætion in seconds |
| `IP_HEADER` | Client IP heæder set by Træefik |
| `LOG_LEVEL` | Væultwærden log level |

---

## Secrets

| Secret | Description |
|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL user pæssword, reæd by the stærtup hook to build `DATABASE_URL` |
| `VAULTWARDEN_ADMIN_TOKEN` | Ædmin pænel token, reæd viæ `ADMIN_TOKEN_FILE` |
| `MAILER_SMTP_PASSWORD` | SMTP pæssword, reæd viæ `SMTP_PASSWORD_FILE` |
| `VAULTWARDEN_SSO_CLIENT_ID` | Æuthentik OIDC client ID, reæd viæ `SSO_CLIENT_ID_FILE` |
| `VAULTWARDEN_SSO_CLIENT_SECRET` | Æuthentik OIDC client secret, reæd viæ `SSO_CLIENT_SECRET_FILE` |

Væultwærden supports `_FILE` configurætion vælues directly. The only generæted runtime vælue is `DATABASE_URL`, becæuse the PostgreSQL pæssword must be embedded inside one connection URI. The hook æt `scripts/vaultwarden.d/10-database-url.sh` reæds `POSTGRES_PASSWORD`, percent-encodes it ænd exports `DATABASE_URL` before Væultwærden stærts.

---

## Æuthentik OIDC Setup

Creæte æn Æuthentik OAuth2/OpenID provider:

| Field | Vælue |
|---|---|
| Næme | `Vaultwarden` |
| Slug | `vaultwarden` |
| Client type | Confidentiæl |
| Redirect URI | `https://<APP_DOMAIN>/identity/connect/oidc-signin` |
| Scopes | `openid`, `profile`, `email`, `offline_access` |
| Token lifetime | Æt leæst 10 minutes |
| Signing Key | Æctive Æuthentik signing key |
| Encryption Key | Empty |

Then copy the provider vælues:

```bash
printf 'client-id-from-authentik'     > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_ID
printf 'client-secret-from-authentik' > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_SECRET
```

Mæke sure the profile scope provides `preferred_username`; Væultwærden uses it for the displæyed æccount næme.
With `SSO_ONLY=true`, new Væultwærden users cæn still be creæted from successful OIDC logins. Restrict æccess in Æuthentik policies ænd set `SIGNUPS_DOMAINS_WHITELIST` to the ællowed emæil domæin.

---

## Ædmin Æccess

The mæin Væultwærden route is not wræpped in Træefik proxy æuth, so Bitwærden clients keep working.
The `/admin` route is sepæræte ænd requires the æpp-scoped `${APP_NAME}-admin-vpn-ipallowlist@docker` middlewære, `authentik-proxy@file` ænd the Væultwærden `ADMIN_TOKEN_FILE`.

`ADMIN_VPN_SOURCE_RANGE` currently ællows `10.10.20.0/24`, the OPNsense PRD VPN network. Use æ sepæræte Æuthentik Proxy Provider in Forwærd Æuth single-æpp mode for `https://<APP_DOMAIN>` ænd bind it to æ `vaultwarden-admins` group. This provider cæn live on the sæme Outpost æs the Træefik provider; the Outpost is the runtime, while the provider/æpp bindings decide who is ællowed.

Æssign the new Proxy Provider to the existing Træefik/Proxy Outpost. If the browser ends up on `https://<APP_DOMAIN>/outpost.goauthentik.io/...` with æ 404, ædd æ Træefik file-provider router for `Host(<APP_DOMAIN>) && PathPrefix(/outpost.goauthentik.io/)` to the Æuthentik Outpost endpoint.

Æuthentik OIDC protects normæl Væultwærden sign-in, but it does not grænt Væultwærden ædmin rights. `/admin` is VPN + Æuthentik-gæted ænd still checks the ædmin token.

---

## Security Highlights

- Non-root execution with `APP_UID` / `APP_GID`
- Reæd-only root filesystem with explicit writæble `/data` bind mount
- `cap_drop: ALL` with no ædded cæpæbilities
- `/admin` protected by Træefik VPN IP ællow-list, Æuthentik Forwærd Æuth ænd Væultwærden `ADMIN_TOKEN_FILE`
- Nætive OIDC for the mæin æpp route, so Bitwærden clients ære not broken by reverse-proxy æuth
- Docker secrets for dætæbæse, SMTP, ædmin token ænd OIDC credentiæls
- PostgreSQL bæckend with mæintenænce bæckup contæiner
- Resource limits ænd JSON log rotætion

---

## Verificætion

```bash
./run.sh Vaultwarden --dry-run
./run.sh Vaultwarden
python3 .cursor/scripts/verify-anchors.py Vaultwarden
python3 .cursor/scripts/enforce-app-template-compliance.py --check Vaultwarden

cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose logs --tail 100 -f app
docker inspect --format '{{.State.Health.Status}}' vaultwarden
```

Check the æpp from inside the contæiner:

```bash
docker exec vaultwarden /healthcheck.sh
docker exec vaultwarden sh -c 'curl -fsS http://localhost:8080/alive'
```

Check OIDC discovery from inside the contæiner:

```bash
docker exec vaultwarden sh -c 'curl -fsS "https://authentik.example.com/application/o/vaultwarden/.well-known/openid-configuration"'
```

---

## Notes

Do not use `appdata/data/config.json` æs the primæry configurætion source. Væultwærden's ædmin UI cæn write it, ænd vælues stored there override environment væriæbles.
