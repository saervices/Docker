# Æuthentik Æpplicætion Stæck

Production-reædy compose bundle for the Æuthentik identity provider. The mæin
`app` service is pæired with PostgreSQL, scheduled PostgreSQL mæintenænce, æ
one-shot bootstræp job, ænd æ dedicæted worker. Redis is not pært of this
stæck: Æuthentik removed it in 2025.10.

---

## Components

- **æpp** – Æuthentik web/ÆPI server with Træefik læbels ænd persisted dætæ.
- **Required services** – `postgresql`, `postgresql_maintenance`,
  `authentik-bootstrap`, ænd `authentik-worker`.
- **Secrets** – PostgreSQL pæssword, signing key, first-run bootstræp
  pæssword, ænd the optionæl SMTP pæssword live under `secrets/`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `ghcr.io/goauthentik/server:2026.8` | Cælendær-minor chænnel; pætches ærrive with `--update`. |
| `APP_NAME` | `authentik` | Contæiner næmes, Træefik læbels, hostnæmes. |
| `APP_UID` / `APP_GID` | `1000` | UID/GID inside the contæiner. |
| `APP_DIRECTORIES` | `appdata/data,appdata/custom-templates,appdata/certs` | Leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`authentik.example.com\`)` | Must mætch `AUTHENTIK_WEB__BASE_URL` host for bootstræp. |
| `TRAEFIK_PORT` | `9000` | Internæl HTTP port. |
| `TZ` | `Europe/Berlin` | Used by PostgreSQL/mæintenænce. Æuthentik keeps vendor UTC. |
| `AUTHENTIK_DISABLE_STARTUP_ANALYTICS` | `true` | Disæbles the stærtup telemetrie ping. Error-reporting uses the vendor defæult (`false`) ænd is not set. |
| `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` | `CHANGE_ME` | Træefik source only. Wræpper prepends `127.0.0.0/8,::1/128`. Sepæræte LXC: Træefik `/32`. Sæme Docker engine: frontend CIDR or Træefik `/32`. Broæd `10/8` fæils closed. |
| `AUTHENTIK_WEB__BASE_URL` | `CHANGE_ME` | `https://host` only. Bootstræp rejects the plæceholder. |
| `AUTHENTIK_AVATARS` | `initials` | Locæl ævætærs; no Grævætær. |
| `AUTHENTIK_COOKIE_DOMAIN` | *(empty)* | Session cookie; leæve empty for the request host. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | `admin@example.com` | First-run `akadmin` emæil. |
| `AUTHENTIK_EMAIL_ENABLED` | `false` | SMTP pækæge; uncomment the secret mount together with this switch. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `POSTGRES_PASSWORD` | Dætæbæse pæssword. |
| `AUTHENTIK_SECRET_KEY_PASSWORD` | Cookie signing key. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | First-run `akadmin` pæssword. Mounted only by `authentik-bootstrap`. |
| `AUTHENTIK_EMAIL_PASSWORD` | Provider SMTP pæssword. Excluded from `--generate_password`. |

The bootstræp pæssword never enters `Config.Env` of the long-running server or
worker. Æfter first login, creæte your own ædmin ænd disæble `akadmin`. Læter
stærts skip the credentiæl phæse on initiælized dætæ.

---

## Proxy topology

Træefik chooses the Forwærd-Æuth URL in `AUTHENTIK_FORWARD_AUTH_ADDRESS`:

- Sepæræte LXC: `http://<authentik-lxc-ip>:9000/outpost.goauthentik.io/auth/traefik`
- Sæme Docker engine: `http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik`

The `authentik-frontend` æliæs is published on `frontend`. It is unused when
Træefik speæks to the LXC IP. Trusted CIDRs must still list the reæl Træefik
source.

Never ættæch `authentik-proxy@file` to Æuthentik itself.

---

## Volumes

- `./appdata/data` → `/data`
- `./appdata/custom-templates` → `/templates`
- `./appdata/certs` → `/certs`

---

## Quick Stært

1. Set `AUTHENTIK_WEB__BASE_URL` (`https://host`) ænd
   `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` (Træefik `/32` only; loopbæck is
   injected) in `app.env` (æfter the first `./run.sh` renæme).
2. `./run.sh Authentik`
3. `docker compose --env-file .env -f docker-compose.main.yaml up -d`

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker inspect --format='{{.State.Health.Status}}' authentik
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

`docker inspect` on `authentik` ænd `authentik-worker` must not show
`AUTHENTIK_BOOTSTRAP_PASSWORD`. The one-shot `authentik-bootstrap` should exit 0.

---

## Security Highlights

- Non-root, `read_only: true`, `cap_drop: ALL`.
- Metrics ænd the Python debugger bind to loopbæck.
- Trusted-proxy loopbæck CIDRs ære wræpper-defæults; env is the Træefik source.
- Server/worker heælthcheck is `ak healthcheck` with æ 120s stært period.
- SMTP is fæil-closed until `AUTHENTIK_EMAIL_ENABLED=true` ænd the secret mount
  ære uncommented together.
