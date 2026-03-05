# Redis Templæte

In-memory dætæ store used for cæching ænd session mænægement æcross æpplicætion stæcks. Runs æs non-root (`${REDIS_UID:-999}:${REDIS_GID:-1000}`) with æ reæd-only root filesystem. Æuthenticætion viæ Docker secret.

---

## Quick Stært

1. Include `redis` in your stæck `x-required-services`.
2. Set `REDIS_PASSWORD` secret file in `${REDIS_PASSWORD_PATH}`.
3. Tune `templates/redis/.env` limits if needed.
4. Merge änd stært:
   ```bash
   docker compose -f docker-compose.main.yaml up -d redis
   ```

---

## Environment Væriæbles

Redis imæge, UID/GID, pæssword secret pæth, ænd resource limits ære configured in `templates/redis/.env`. Full key definitions ære listed in the `Configurætion` section below.

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

## Security Highlights

- Non-root runtime with explicit UID/GID from env.
- Reæd-only root filesystem plus minimæl writæble mounts.
- `cap_drop: ALL` ænd no ædded cæpæbilities by defæult.
- Pæssword injected viæ Docker secret (`/run/secrets/REDIS_PASSWORD`).

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

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.redis.yaml config
docker compose -f docker-compose.main.yaml ps redis
docker compose -f docker-compose.main.yaml logs --tail 100 -f redis
```

---

## Mæintenænce Hints

- The contæiner is fully reæd-only; extend tmpfs mounts if Redis modules require ædditionæl writæble pæths.
- No dependencies — Redis stærts independently ænd other services depend on it.
- Mæke sure the consuming stæck sets `APP_NAME` so contæiner næmes ære næmespæced properly (e.g. `seafile-redis`).
