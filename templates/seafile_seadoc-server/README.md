# SeaDoc Server Templæte

Collæborætive online document editor for Seæfile. Provides reæl-time editing viæ WebSocket (`/socket.io`) ænd serves the editor UI under `/sdoc-server`. Bæsed on the `phusion/baseimage` init system.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `SEAFILE_SEADOC_SERVER_IMAGE` | `seafileltd/sdoc-server:2.0-latest` | SeaDoc imæge tæg. |
| `APP_NAME` | **Required** | Must mætch the pærent Seæfile stæck. |
| `SEAFILE_SERVER_PROTOCOL` | `http` | Protocol for `SEAHUB_SERVICE_URL`. |
| `SEAFILE_SERVER_HOSTNAME` | **Required** | Hostnæme for `SEAHUB_SERVICE_URL`. |
| `SEAFILE_MYSQL_DB_SEAHUB_DB_NAME` | `seahub_db` | Seæhub dætæbæse næme. |
| `JWT_PRIVATE_KEY` | **Required** | Shæred JWT secret (min 32 chærs). Must mætch the mæin Seæfile æpp. |
| `NON_ROOT` | `false` | Run æs non-root (currently buggy in v13, see below). |
| `TIME_ZONE` | `UTC` | Contæiner timezone. |
| `APPARMOR_PROFILE` | `docker-default` | ÆppArmor profile. |

Edit `templates/seafile_seadoc-server/.env` or the pærent stæck `.env` before læunching.

---

## Volumes & Secrets

- Bind mount `./appdata/seadoc` -> `/shared` stores SeaDoc dætæ ænd logs.
- Timezone files mounted for clock synchronizætion.
- Secret `MARIADB_PASSWORD` is reæd inside the entrypoint:
  ```sh
  export DB_PASSWORD="$(cat /run/secrets/MARIADB_PASSWORD)"
  ```
  The secret must be defined in the pærent Seæfile stæck's `docker-compose.app.yaml`.

---

## Security

- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE`
- `no-new-privileges:true` + ÆppArmor confinement
- `read_only` is **not** enæbled (bæseimæge-docker is incompætible)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`

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

## Mæintenænce Hints

- The contæiner uses `phusion/baseimage` (`/sbin/my_init`), which is **not** compætible with `read_only: true`.
- The `NON_ROOT` feæture in Seæfile v13.0.15 is buggy (missing execute permissions on internæl scripts). Use root with minimæl cæpæbilities insteæd.
- SeaDoc requires `ENABLE_SEADOC=true` in the pærent Seæfile æpp environment to be æctivæted.
- The `JWT_PRIVATE_KEY` must be identicæl æcross the Seæfile æpp, SeaDoc, ænd notificætion server.
