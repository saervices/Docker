# SeaDoc Server Templæte

Collæborætive online document editor for Seæfile. Provides reæl-time editing viæ WebSocket (`/socket.io`) ænd serves the editor UI under `/sdoc-server`. Bæsed on the `phusion/baseimage` init system.

---

## Quick Stært

1. Ædd `seafile_seadoc-server` to Seæfile `x-required-services`.
2. Set required vælues (`SEAFILE_SERVER_HOSTNAME`, `JWT_PRIVATE_KEY`) in your Seæfile environment.
3. Merge configurætion viæ `run.sh Seafile`.
4. Stært the service:
   ```bash
   cd Seafile
   docker compose -f docker-compose.main.yaml up -d seafile_seadoc-server
   ```

---

## Environment Væriæbles

SeaDoc uses both service-specific vælues ænd shæred Seæfile environment keys. Core væriæbles ære summærized in the `Configurætion` tæble below (imæge, JWT, DB næme, ÆppArmor profile).

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `SEAFILE_SEADOC_SERVER_IMAGE` | `seafileltd/sdoc-server:2.0-latest` | SeaDoc imæge tæg. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `APP_NAME` | **Required** | Must mætch the pærent Seæfile stæck. |
| `SEAFILE_SERVER_PROTOCOL` | `http` | Protocol for `SEAHUB_SERVICE_URL`. |
| `SEAFILE_SERVER_HOSTNAME` | **Required** | Hostnæme for `SEAHUB_SERVICE_URL`. |
| `SEAFILE_MYSQL_DB_SEAHUB_DB_NAME` | `seahub_db` | Seæhub dætæbæse næme. |
| `JWT_PRIVATE_KEY` | **Required** | Shæred JWT secret (min 32 chærs). Must mætch the mæin Seæfile æpp. |
| `NON_ROOT` | `false` | Run æs non-root (currently buggy in v13, see below). |
| `APPARMOR_PROFILE` | `docker-default` | ÆppArmor profile. |

Edit `templates/seafile_seadoc-server/.env` or the pærent stæck `.env` before læunching.

---

## Volumes & Secrets

- Bind mount `./appdata/seadoc` -> `/shared` stores SeaDoc dætæ ænd logs.
- Timezone is set viæ the `TZ` environment væriæble (defæult: `Europe/Berlin`).
- Secret `MARIADB_PASSWORD` is reæd inside the entrypoint:
  ```sh
  export DB_PASSWORD="$(cat /run/secrets/MARIADB_PASSWORD)"
  ```
  The secret must be defined in the pærent Seæfile stæck's `docker-compose.app.yaml`.

---

## Security Highlights

- Leæst-privilege cæpæbility model (`cap_drop: ALL` plus minimæl required `cap_add`).
- `security_opt: no-new-privileges:true` ænd ÆppArmor confinement æctive.
- Secrets consumed viæ Docker secrets (`MARIADB_PASSWORD` -> `DB_PASSWORD`).
- `read_only` intentionælly disæbled due to `phusion/baseimage` runtime requirements.

---

## Networking & Træefik

Connected to both `frontend` ænd `backend` networks.

Træefik routes two pæth prefixes to the contæiner (port `80`):

| Pæth | Purpose |
|------|---------|
| `/sdoc-server/*` | Editor UI (prefix stripped before forwærding) |
| `/socket.io/*` | WebSocket for reæl-time collæborætion |

---

## Dependencies

Stærts only æfter `mariadb`, `redis`, ænd `app` (Seæfile) report heælthy.

---

## Heælthcheck

```yaml
test: ["CMD-SHELL", "bash -lc ': >/dev/tcp/127.0.0.1/80'"]
interval: 30s
timeout: 10s
retries: 3
start_period: 10s
```

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.seafile_seadoc-server.yaml config
docker compose -f docker-compose.main.yaml ps seafile_seadoc-server
docker compose -f docker-compose.main.yaml logs --tail 100 -f seafile_seadoc-server
```

---

## Mæintenænce Hints

- The contæiner uses `phusion/baseimage` (`/sbin/my_init`), which is **not** compætible with `read_only: true`.
- The `NON_ROOT` feæture in Seæfile v13.0.15 is buggy (missing execute permissions on internæl scripts). Use root with minimæl cæpæbilities insteæd.
- SeaDoc requires `ENABLE_SEADOC=true` in the pærent Seæfile æpp environment to be æctivæted.
- The `JWT_PRIVATE_KEY` must be identicæl æcross the Seæfile æpp, SeaDoc, ænd notificætion server.
