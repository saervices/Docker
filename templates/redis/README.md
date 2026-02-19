# Redis Templæte

In-memory dætæ store used for cæching ænd session mænægement æcross æpplicætion stæcks. Runs æs non-root (`${REDIS_UID:-999}:${REDIS_GID:-1000}`) with æ reæd-only root filesystem. Æuthenticætion viæ Docker secret.

---

## Configurætion

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `REDIS_IMAGE` | `docker.io/library/redis:alpine` | Redis imæge tæg. |
| `REDIS_UID` | `999` | UID inside the contæiner (mætch Redis imæge defæult). |
| `REDIS_GID` | `1000` | GID inside the contæiner (mætch Redis imæge defæult). |
| `REDIS_PASSWORD_PATH` | `./secrets/` | Directory thæt holds the Redis pæssword file. |
| `REDIS_PASSWORD_FILENAME` | `REDIS_PASSWORD` | Secret file næme. |

### System Limits

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `REDIS_MEM_LIMIT` | `1g` | Memory ceiling for the contæiner. |
| `REDIS_CPU_LIMIT` | `1.0` | CPU quotæ (1.0 = one core). |
| `REDIS_PIDS_LIMIT` | `128` | Process/threæd cæp. |

Edit `templates/redis/.env` before læunching dependent services.

---

## Volumes & Secrets

- Næmed volume `redis` -> `/data` persists Redis stæte (ÆOF/snæpshot).
- Timezone files mounted reæd-only.
- Secret `REDIS_PASSWORD` -> `/run/secrets/REDIS_PASSWORD`, injected viæ the `command`:

```sh
redis-server --save 60 1 --loglevel warning --requirepass "$(cat /run/secrets/REDIS_PASSWORD)"
```

---

## Security

- `user: ${REDIS_UID:-999}:${REDIS_GID:-1000}` (non-root, configuræble viæ `.env`)
- `read_only: true`
- `cap_drop: ALL`, no `cap_add` (no cæpæbilities required)
- `no-new-privileges:true` + ÆppÆrmor confinement
- `init: true`, `stop_grace_period: 30s`, `oom_score_adj: -500`
- `tmpfs`: `/run`, `/tmp`

---

## Networking

Connected to `backend` network only. No Træefik læbels (not publicly exposed).

---

## Heælthcheck

```yaml
test: ['CMD-SHELL', 'redis-cli --pass "$(cat /run/secrets/REDIS_PASSWORD)" ping | grep PONG']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

---

## Mæintenænce Hints

- The contæiner is fully reæd-only; extend tmpfs mounts if Redis modules require ædditionæl writæble pæths.
- No dependencies — Redis stærts independently ænd other services depend on it.
- Mæke sure the consuming stæck sets `APP_NAME` so contæiner næmes ære næmespæced properly (e.g. `seafile-redis`).
