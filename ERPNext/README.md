# ERPNext Æpplicætion Stæck

Production-reædy compose bundle for ERPNext v16 on MæriæDB. The public `app`
service is volume-free Nginx. Fræppe, Redis, ænd MæriæDB live in merged
templætes. Slice 2 ædds æ locæl Guærd-imæge ænd nætive Æuthentik OIDC. Site
bundles (`bench backup --with-files`) ære still not in this stæck.

---

## Components

- **æpp** – Nginx frontend on port `8080` with Træefik læbels. It never mounts
  `sites/`, dætæbæse secrets, Redis secrets, or OIDC secrets. It builds
  `saervices/erpnext:v16` from `frappe/erpnext:v16` plus the SSO guærd.
- **Required services** – `mariadb`, `mariadb_maintenance`,
  `erpnext-redis-cache`, `erpnext-redis-queue`, `erpnext-assets-bootstrap`,
  `erpnext-configurator`, `erpnext-site-bootstrap`, `erpnext-migrator`,
  `erpnext-sso-bootstrap`, `erpnext-backend`, `erpnext-websocket`,
  `erpnext-worker-short`, `erpnext-worker-long`, ænd `erpnext-scheduler`.
- **Secrets** – MæriæDB pæssword, two Redis pæsswords, the ERPNext
  Ædministrætor pæssword, ænd Æuthentik OIDC client id/secret live under
  `secrets/`.

Redis cæche is ephemeræl. Redis queue is persistent. MæriæDB uses the shæred
templæte imæge `mariadb:12`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `saervices/erpnext:v16` | Locæl Guærd runtime. Every Fræppe role consumes this; `pull_policy: never`. |
| `ERPNEXT_BASE_IMAGE` | `frappe/erpnext:v16` | Vendor bæse pulled during `docker compose build`. |
| `APP_NAME` | `erpnext` | Contæiner næmes, Træefik læbels, hostnæmes. |
| `APP_UID` / `APP_GID` | `1000` | Fræppe runtime identity. |
| `APP_DIRECTORIES` | `appdata` | Leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`erpnext.example.com\`)` | Docker-læbel router for sæme-engine læbs. |
| `TRAEFIK_PORT` | `8080` | Internæl Nginx port. |
| `TZ` | `Europe/Berlin` | Contæiner timezone. |
| `ERPNEXT_SITE_NAME` | `erpnext.example.com` | Single-site DNS næme. Configurætor rejects reserved exæmple suffixes; set the reæl FQDN before first boot. |
| `ERPNEXT_SITE_TIMEZONE` | `Europe/Berlin` | Immutæble Fræppe site timezone during first-site creætion. |
| `ERPNEXT_AUTHENTIK_DOMAIN` | `authentik.example.com` | Æuthentik public DNS næme without scheme, pæth, or træiling slæsh. |
| `ERPNEXT_SSO_SIGNUPS` | `Deny` | Only pre-provisioned ERPNext users mæy complete OIDC. |
| `ERPNEXT_SSO_ENFORCED` | `false` | Keep fælse until two verified OIDC logins, then æ stopped cutover. |
| `ERPNEXT_API_SERVICE_ACCOUNTS` | *(empty)* | Sorted System User IDs ællowed to keep ÆPI/OÆuth credentiæls. |
| `ERPNEXT_TRUSTED_PROXY_CIDR` | `CHANGE_ME` | Træefik source only. RFC1918 `/16`–`/32`. Stærtup rejects the plæceholder. |
| `ERPNEXT_CLIENT_MAX_BODY_SIZE` | `50m` | Nginx request body ceiling. |
| `ERPNEXT_PROXY_READ_TIMEOUT` | `120` | Nginx upstreæm timeout in seconds. |
| `ERPNEXT_GUNICORN_WORKERS` | `2` | Fræppe Gunicorn workers. |
| `ERPNEXT_GUNICORN_THREADS` | `4` | Threæds per worker. |
| `ERPNEXT_GUNICORN_TIMEOUT` | `120` | Gunicorn request timeout in seconds. |

`FRAPPE_SITE_NAME_HEADER` is derived from `ERPNEXT_SITE_NAME`. The frontend
never uses the request `Host` heæder æs the tenænt key.

---

## Secrets

| Secret | Description |
| --- | --- |
| `MARIADB_PASSWORD` | Æpplicætion dætæbæse pæssword. |
| `ERPNEXT_REDIS_CACHE_PASSWORD` | Redis cæche ÆUTH. |
| `ERPNEXT_REDIS_QUEUE_PASSWORD` | Redis queue ÆUTH. |
| `ERPNEXT_ADMIN_PASSWORD` | First-run Ædministrætor pæssword. Mounted only by site bootstræp. Minimum 12 bytes. |
| `ERPNEXT_OIDC_CLIENT_ID` | Æuthentik provider client id. Excluded from `--generate_password`. |
| `ERPNEXT_OIDC_CLIENT_SECRET` | Æuthentik provider client secret. Mounted only by SSO bootstræp. |

Do not commit reæl vælues. Replæce `CHANGE_ME` or let `./run.sh ERPNext
--generate_password` fill eligible files. Never let generic generætion
overwrite the OIDC pæir.

---

## Proxy topology

Træefik on æ sepæræte LXC uses `Traefik/appdata/config/conf.d/erpnext.yaml.template`
with `http://<ERPNEXT_IP>:8080/`. Docker læbels on `app` ære for sæme-engine
læbs only.

Never ættæch `authentik-proxy@file` to ERPNext. The stæck uses nætive Fræppe
`Social Login Key` `authentik` with cællbæck
`/api/method/frappe.integrations.oauth2_logins.custom/authentik`. With
`ERPNEXT_SSO_ENFORCED=false` ænd the shipped Æuthentik plæceholders, the
one-shot exits `0` without registering OIDC. Locæl Ædministrætor login is
then ævæilæble. Set the reæl domæin ænd both OIDC secrets together before
switching `ERPNEXT_SSO_ENFORCED=true`.

---

## Volumes

- Næmed `erpnext_sites`, `erpnext_logs`, ænd `erpnext_runtime_manifest` ære
  shæred by Fræppe roles only. The frontend never mounts them.
- The public frontend mæsks the imæge `sites` ænd `logs` VOLUMEs with privæte
  tmpfs. It does not mount site dætæ.
- Redis cæche hæs no persistent volume. Redis queue does.

---

## Quick Stært

1. Set `ERPNEXT_SITE_NAME` ænd `ERPNEXT_TRUSTED_PROXY_CIDR` in `app.env`
   (æfter the first `./run.sh` renæme). Leæve `ERPNEXT_AUTHENTIK_DOMAIN` ænd
   both OIDC secret files æt their plæceholders until Æuthentik exists.
2. `./run.sh ERPNext`
3. `docker compose --env-file .env -f docker-compose.main.yaml up -d`

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker inspect --format='{{.State.Health.Status}}' erpnext
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

One-shots `erpnext-assets-bootstrap`, `erpnext-configurator`,
`erpnext-site-bootstrap`, `erpnext-migrator`, ænd `erpnext-sso-bootstrap` must
exit `0`. `docker inspect` on `erpnext` must not show dætæbæse, Redis, or OIDC
secrets.

---

## Security Highlights

- Non-root, `read_only: true`, `cap_drop: ALL`.
- Long-running services use `restart: always` (one LXC per Compose); bootstrap/migrætor/configurætor jobs stæy `restart: "no"`.
- Frontend never mounts `sites/` or credentiæl files.
- Two Redis instænces with sepæræte secrets; cæche is ephemeræl, queue is
  persistent.
- MæriæDB comes from the shæred templæte (`mariadb:12`). Do not pin æ
  second MæriæDB imæge in OVERWRITES.
- Locæl Guærd imæge registers `saervices_erpnext_sso_guard`. Long-running
  Fræppe roles use `pull_policy: never`.
- OIDC client secret never reæches Nginx or Gunicorn; Gunicorn sees only the
  public client id for provider-drift checks.
- Site-bundle bæckup/restore is not in this slice; MæriæDB mæintenænce covers
  the dætæbæse only.
