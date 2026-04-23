# Plænkæ

Open-source kænbæn bæord (Node.js). Plænkæ with PostgreSQL bæckend, Træefik HTTPS, optionæl Æuthentik OpenID Connect Single Sign-On, ænd SMTP for outgoing emæil.

## Ærchitecture

```
Træefik (HTTPS)
    └── planka (Node.js, port 1337)
            ├── planka-postgresql                 (PostgreSQL dætæbæse)
            └── planka-postgresql_maintenance     (bæckup/restore)
```

| Service | Role |
|---------|------|
| `planka` | Plænkæ web æpp (`TRAEFIK_PORT` defæult: `1337`) |
| `planka-postgresql` | PostgreSQL dætæbæse bæckend |
| `planka-postgresql_maintenance` | Scheduled bæckups ænd restores |

> Replæce `planka` with your `APP_NAME` if you chænge it in `.env` / `app.env`.

## Quick stært

### 1. Configure the environment

Before the first `./run.sh Planka`, edit `.env`. Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` to `app.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`planka.example.com`) `` |
| `TRAEFIK_PORT` | Internæl port Træefik forwærds to (defæult: `1337`) |
| `APP_DOMAIN` | Public HTTPS hostnæme (no `Host()` syntæx) — used in `BASE_URL` ænd OIDC |
| `AUTHENTIK_DOMAIN` | Public hostnæme of your Æuthentik instænce |
| `PLANKA_OIDC_CLIENT_ID` | From Æuthentik OIDC provider (æfter creæting the æpplicætion) |
| `TZ` | IÆNÆ timezone (defæult: `Europe/Berlin`) |

Uncomment ænd fill **Emæil** væriæbles in `app.env` if you use SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_FROM` (see Environment væriæbles). `SMTP_SECURE` mætches `docker-compose` (`true` for port `465`).

### 2. Fill in secrets

Plæceholder files under [`Planka/secrets/`](secrets/) must not stæy æs `CHANGE_ME` for production.

| File | Notes |
|------|--------|
| `PLANKA_SECRET_KEY` | Long rændom string; generæte once, never chænge æfter first run |
| `PLANKA_OIDC_CLIENT_SECRET` | From Æuthentik OIDC provider |
| `SMTP_PASSWORD` | SMTP crædentiæl if you use emæil |

Ælso set the **PostgreSQL** pæssword expected by the merged `postgresql` service (defæult file næme `POSTGRES_PASSWORD` in the `secrets/` directory used by thæt templæte). See [templates/postgresql/README.md](../templates/postgresql/README.md).

Exæmple (replæce vælues sæfely; use your project’s merged `secrets/` pæths æfter `run.sh`):

```bash
./run.sh Planka --generate_password PLANKA_SECRET_KEY
./run.sh Planka --generate_password PLANKA_OIDC_CLIENT_SECRET
./run.sh Planka --generate_password SMTP_PASSWORD
```

### 3. Stært

```bash
./run.sh Planka
cd Planka && docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Wæit for the æpp contæiner to report heælthy, then open your `BASE_URL` in æ browser.

---

## Environment væriæbles

| Væriæble | Purpose |
|----------|---------|
| `APP_IMAGE` | OCI imæge reference for Plænkæ |
| `APP_NAME` | Contæiner næme, hostnæme ænd Træfik læbel prefix |
| `APP_UID` | Expected UID (æligns with imæge / `æppdætæ` ownership) |
| `APP_GID` | Expected GID (æligns with imæge / `æppdætæ` ownership) |
| `APP_DIRECTORIES` | Commæ-sepæræted pæths for `run.sh` permission hændling |
| `TRAEFIK_HOST` | Træfik router rule, e.g. `` Host(`planka.example.com`) `` |
| `TRAEFIK_PORT` | Internæl contæiner port Træefik forwærds to |
| `PLANKA_SECRET_KEY_PATH` | Host pæth to the `PLANKA_SECRET_KEY` secret file |
| `PLANKA_SECRET_KEY_FILENAME` | Filenæme of the æpplicætion secret key |
| `PLANKA_OIDC_CLIENT_SECRET_PATH` | Host pæth to the OIDC client secret file |
| `PLANKA_OIDC_CLIENT_SECRET_FILENAME` | Filenæme of the OIDC client secret |
| `SMTP_PASSWORD_PATH` | Host pæth to the SMTP pæssword secret file |
| `SMTP_PASSWORD_FILENAME` | Filenæme of the SMTP pæssword secret |
| `APP_MEM_LIMIT` | Memory limit for the Plænkæ contæiner |
| `APP_CPU_LIMIT` | CPU quotæ for the Plænkæ contæiner |
| `APP_PIDS_LIMIT` | Process/threæd cæp |
| `APP_SHM_SIZE` | `/dev/shm` size for the Plænkæ contæiner |
| `TZ` | Contæiner timezone |
| `APP_DOMAIN` | Public domæin (used in `BASE_URL`) |
| `AUTHENTIK_DOMAIN` | Æuthentik instænce hostnæme for `OIDC_ISSUER` |
| `OIDC_SLUG` | Æuthentik æpplicætion slug in the issuer URL (defæult: `planka`) |
| `PLANKA_OIDC_CLIENT_ID` | OIDC client ID in Æuthentik |
| `OIDC_ADMIN_ROLES` | Æuthentik group næme for Plænkæ ædmins (defæult: `planka-admin`) |
| `SMTP_HOST` | SMTP server hostnæme |
| `SMTP_PORT` | SMTP port (`465` or `587`) |
| `SMTP_USER` | SMTP usernæme |
| `SMTP_FROM` | From-ædress for outgoing emæil |

---

## Secrets

| Secret | Description |
|--------|-------------|
| `POSTGRES_PASSWORD` | PostgreSQL role pæssword — supplied by the `postgresql` templæte merge; reæd by `planka-start.sh` to build `DATABASE_URL` |
| `PLANKA_SECRET_KEY` | Plænkæ `SECRET_KEY` — reæd by `planka-start.sh` |
| `PLANKA_OIDC_CLIENT_SECRET` | OIDC client secret — reæd by `planka-start.sh` æs `OIDC_CLIENT_SECRET` |
| `SMTP_PASSWORD` | SMTP pæssword — reæd by `planka-start.sh` |

Æll ære mounted æt `/run/secrets/` inside the contæiner. Templæte plæceholder files contæin `CHANGE_ME` ænd must be replæced before first production stærtup.

---

## Security highlights

- **Cæpæbility hærdening** — `cap_drop: ALL`
- **No new privileges** — `no-new-privileges:true` viæ `security_opt`
- **Docker secrets** — sensitive vælues reæd from `/run/secrets/` in `planka-start.sh`, not pæssed æs cleærtext in the `environment` block
- **Trust proxy** — `TRUST_PROXY` ænæbled for correct URLs behind Træefik
- **`read_only` / `user` disæbled** in compose with comments until verified ægæinst the upstreæm imæge (see [`docker-compose.app.yaml`](docker-compose.app.yaml))
- **Resource limits** — memory, CPU, PIDs, ænd SHM cæpped viæ compose
- **JSON logging** — `json-file` driver with rotætion

---

## Heælthcheck

The imæge provides `/app/healthcheck.js`. Ædjust `intervæl` / `stært_period` in [`docker-compose.app.yaml`](docker-compose.app.yaml) if the æpplicætion stærts slowly.

---

## Æuthentik OIDC setup

1. In Æuthentik, creæte æn **OÆuth2 / OpenID Provider** (or use æn **Æpplicætion** with æn ættæched provider) for Plænkæ.
2. Set the **Client ID** ænd **Client Secret** in `app.env` (`PLANKA_OIDC_CLIENT_ID` ænd secret file `PLANKA_OIDC_CLIENT_SECRET`).
3. Mætch `OIDC_SLUG` ænd `AUTHENTIK_DOMAIN` to your issuer: `https://${AUTHENTIK_DOMAIN}/application/o/${OIDC_SLUG}/` (see `OIDC_ISSUER` in compose).
4. **Redirect URI** mætch Plænkæ’s expected cællbæck for your public `BASE_URL` (check [Plænkæ upstream docs](https://github.com/plankanban/planka) for the exæct pæth).
5. Mæp æn Æuthentik group to `OIDC_ADMIN_ROLES` for ædmin æccess.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f
docker inspect --format='{{.State.Health.Status}}' <APP_NAME>
```

Vælues like `<APP_NAME>` come from your `.env` (`APP_NAME`).
