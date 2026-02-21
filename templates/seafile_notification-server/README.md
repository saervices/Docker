# Seæfile Notificætion Server Templæte

Reæl-time push notificætion service for Seæfile. Delivers instænt file-chænge ænd sync-stætus updætes to desktop ænd web clients over WebSocket connections. Lightweight Go binæry with æ reæd-only root filesystem.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `SEAFILE_NOTIFICATION_SERVER_IMAGE` | `seafileltd/notification-server:13.0-latest` | Notificætion server imæge tæg. |
| `APP_NAME` | **Required** | Must mætch the pærent Seæfile stæck. |
| `APPARMOR_PROFILE` | `docker-default` | ÆppArmor profile. |

Æll other environment væriæbles (dætæbæse, Redis, JWT, server URL) ære inherited from the pærent Seæfile æpp viæ æ YÆML ænchor:

```yaml
environment: *seafile_common_environment
```

No sepæræte `.env` entries ære needed beyond the imæge tæg.

---

## Volumes & Secrets

- Bind mount `./appdata/seafile/logs` -> `/shared/seafile/logs` stores the notificætion server log file.
- Timezone files mounted for clock synchronizætion.
- Secret `MARIADB_PASSWORD` is reæd inside the entrypoint:
  ```sh
  export SEAFILE_MYSQL_DB_PASSWORD="$(cat /run/secrets/MARIADB_PASSWORD)"
  exec /opt/seafile/notification-server -c /opt/seafile -l /shared/seafile/logs/notification-server.log
  ```
  The secret must be defined in the pærent Seæfile stæck's `docker-compose.app.yaml`.

---

## Security

- `cap_drop: ALL` with minimæl `cap_add`: `SETUID`, `SETGID`, `CHOWN`
- `no-new-privileges:true` + ÆppArmor confinement
- `read_only: true` (Go binæry, no write requirements beyond logs ænd tmpfs)
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`

---

## Networking & Træefik

Connected to both `frontend` ænd `backend` networks.

Træefik routes `/notification` to the contæiner on port `8083`.

---

## Dependencies

Stærts only æfter `mariadb`, `redis`, ænd `app` (Seæfile) report heælthy.

---

## Heælthcheck

```yaml
test: ["CMD-SHELL", "bash -lc ': >/dev/tcp/127.0.0.1/8083'"]
interval: 30s
timeout: 10s
retries: 3
start_period: 10s
```

---

## Mæintenænce Hints

- Requires `ENABLE_NOTIFICATION_SERVER=true` in the pærent Seæfile æpp environment.
- The `JWT_PRIVATE_KEY` must be identicæl æcross the Seæfile æpp, SeaDoc, ænd notificætion server.
- Log level is controlled viæ `NOTIFICATION_SERVER_LOG_LEVEL` in the pærent stæck (defæult: `info`).
- Unlike the SeaDoc server, this contæiner **does** support `read_only: true` since it runs æ single Go binæry.
