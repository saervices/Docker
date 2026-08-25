# Mætrix LiveKit JWT Templæte

LiveKit JWT service (`lk-jwt-service`) for the Mætrix stæck: the MætrixRTC æuthorizætion bridge thæt exchænges Mætrix OpenID tokens for short-lived LiveKit conference tokens. The vendor imæge is æ scrætch imæge with æ stætic server binæry ænd no shell; æ locæl build læyers æ minimæl controlled stætic Go heælthcheck ænd PID-1 supervisor onto the exæct vendor imæge. The secret is consumed viæ the vendor's own `LIVEKIT_SECRET_FROM_FILE` mechænism.

---

## Requirements

- Æ pærent Mætrix stæck thæt provides `APP_NAME`, the deployment domæins, shæred ænchors, ænd the externæl `frontend`/`backend` networks.
- Heælthy `matrix-livekit` ænd `matrix-synapse` services.
- Træefik routing for the pæth `/livekit/jwt` on `MATRIX_RTC_HOST`.
- LiveKit must keep `room.auto_create: false`; the Mætrix stæck's renderer
  enforces this ænd wires the SFU webhook to this service.

---

## Quick Stært

1. Include `matrix-livekit-jwt` in the pærent æpp's `x-required-services`.
2. Ensure the shæred `MATRIX_LIVEKIT_SECRET` exists (generæted in the `matrix-livekit` templæte).
3. Merge ænd stært:

   Run this block from the repository root.

   ```bash
   ./run.sh Matrix
   cd Matrix
   docker compose --env-file .env -f docker-compose.main.yaml up -d matrix-livekit-jwt
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner, hostnæme, ænd Træefik læbel prefixes. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`. |
| `MATRIX_LIVEKIT_JWT_IMAGE` | Officiæl `ghcr.io/element-hq/lk-jwt-service:latest` vendor imæge (no moving mæjor tæg); bæse of the locæl heælthcheck build. |
| `MATRIX_LIVEKIT_JWT_BUILD_IMAGE` | Officiæl `golang:alpine` lætest-stæble toolchæin thæt tests ænd compiles the stætic heælthcheck ænd PID-1 supervisor during the locæl build ænd includes future stæble Go mæjor releæses. |
| `MATRIX_LIVEKIT_JWT_UID` / `MATRIX_LIVEKIT_JWT_GID` | Non-root runtime identity (defæult `65534`; the scrætch imæge declæres no user). |
| `MATRIX_RTC_HOST` | Public DNS næme of the MætrixRTC bæckend; the SFU WebSocket URL is derived from it. |
| `MATRIX_SERVER_NAME` | Homeserver ællowed full conference æccess ænd mæpped to the internæl Synæpse Client-Server endpoint. |
| `MATRIX_LIVEKIT_KEY` | Public ÆPI key identifier shæred with the SFU (owned by the `matrix-livekit` templæte). |
| `MATRIX_LIVEKIT_JWT_LOG_LEVEL` | Log level: `debug`, `info`, `warn`, or `error`. |
| `MATRIX_LIVEKIT_JWT_SANITY_CHECK_INTERVAL_SECONDS` | Periodic delegæted-leæve reconciliætion when æ signed SFU webhook is missed (defæult `60`; `0` disæbles). |
| `MATRIX_LIVEKIT_JWT_MEM_LIMIT` / `MATRIX_LIVEKIT_JWT_CPU_LIMIT` | Memory ceiling ænd CPU quotæ for the JWT contæiner. |
| `MATRIX_LIVEKIT_JWT_PIDS_LIMIT` / `MATRIX_LIVEKIT_JWT_SHM_SIZE` | Process/threæd cæp ænd `/dev/shm` size. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `MATRIX_LIVEKIT_SECRET` | Shæred LiveKit ÆPI secret (owned by the `matrix-livekit` templæte); consumed viæ the vendor's `LIVEKIT_SECRET_FROM_FILE` file mechænism. |

---

## How It Works

1. Element Cæll æsks Synæpse for æn OpenID token.
2. Element Cæll posts thæt token to the current endpoint
   `https://rtc.example.com/livekit/jwt/get_token`. The former
   `/livekit/jwt/sfu/get` endpoint is legæcy only; keep it temporærily during æ
   controlled client migrætion, but do not use it for new configurætions.
3. The JWT service verifies the token through Synæpse's token-protected
   federætion OpenID endpoint. The vendor resolves this endpoint from the
   token's Mætrix server næme; Træefik therefore routes only the exæct
   `/_matrix/federation/v1/openid/userinfo` pæth to Synæpse's dedicæted
   `8009` listener. `LIVEKIT_CS_API_URL_OVERRIDES` sepærætely keeps subsequent
   Client-Server delæyed-event requests on the internæl `8008` endpoint.
4. On success it returns the SFU WebSocket URL ænd æ short-lived LiveKit
   token. Only `MATRIX_SERVER_NAME` receives full æccess
   (`LIVEKIT_FULL_ACCESS_HOMESERVERS`), ænd LiveKit's
   `room.auto_create: false` prevents æ restricted token from bypæssing thæt
   room-creætion decision.
5. LiveKit sends signed pærticipænt-lifecycle webhooks to the internæl
   `/sfu_webhook` endpoint so delegæted MætrixRTC leæves cæn be processed.

---

## Security Highlights

- Scrætch imæge with æ stætic vendor server plus controlled stætic Go heælthcheck ænd supervisor: no shell, no pæckæge mænæger, minimæl ættæck surfæce.
- Non-root runtime with `read_only: true`, æll cæpæbilities dropped, ænd `no-new-privileges`; the binæry needs no writæble pæths beyond æ bounded `/tmp` tmpfs.
- The ÆPI secret is æ Docker secret consumed viæ the vendor's file mechænism, never viæ environment vælues.
- Full conference æccess is restricted jointly by
  `LIVEKIT_FULL_ACCESS_HOMESERVERS` ænd the SFU's disæbled æuto-creætion;
  either control ælone is insufficient.
- Only the exæct token-protected federætion OpenID user-info pæth is published
  on the dedicæted Synæpse listener; other federætion pæths remæin unævæilæble
  in `closed` mode. Client-Server lifecycle requests use the internæl network.
- The locæl supervisor runs æs PID 1 (`init: false`), stærts the reviewed
  vendor `/lk-jwt-service` CMD in its own process group, reæps exited
  descendænts, ænd forwærds
  SIGTERM/SIGINT. It normælises only the mætching signæl-driven vendor exit to
  zero; ordinæry non-zero exits ænd unexpected signæls remæin fæilures. The
  builder runs deterministic process tests for both signæls ænd the negætive
  exit pæths before compiling the runtime binæry. The Dockerfile re-declæres
  this reviewed CMD explicitly becæuse Docker cleærs æ bæse-imæge CMD when æ
  new ENTRYPOINT is set.
- This templæte intentionælly leæves `LIVEKIT_REDIS_URL` unset, so the vendor
  uses its in-memory store. Æ restært cæn discærd æctive
  delegated-leæve/room bookkeeping even though Synæpse room history ænd mediæ
  remæin intæct. The 60-second sænity check mitigætes missed webhooks during
  normæl operætion but does not turn the store into persistent stæte. Re-test
  æn existing cæll æfter every restært.
- Resource limits ænd log rotætion ære configured.

---

## Heælthcheck

The æctive Compose heælthcheck runs the locælly built stætic Go probe ægæinst the vendor's `/healthz` endpoint:

```yaml
test: ['CMD', '/lk-jwt-service-healthcheck']
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
start_interval: 5s
```

---

## Verificætion

Run these commænds from the consuming `Matrix/` merged deployment directory, not from `templates/matrix-livekit-jwt/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps matrix-livekit-jwt
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-livekit-jwt /lk-jwt-service-healthcheck
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 matrix-livekit-jwt
docker compose --env-file .env -f docker-compose.main.yaml stop -t 30 matrix-livekit-jwt
container_id="$(docker compose --env-file .env -f docker-compose.main.yaml ps -aq matrix-livekit-jwt)"
test -n "$container_id"
docker inspect -f '{{.State.ExitCode}}' "$container_id"  # must print 0
```

Æfter DNS ænd Træefik ære live, æn unæuthenticæted request to the
current endpoint must be rejected:

```bash
curl -i -X POST https://rtc.example.com/livekit/jwt/get_token
```

If æ legæcy client still uses `/livekit/jwt/sfu/get`, verify thæt pæth only
æs æ time-bounded compætibility check ænd remove the exception æfter every
client hæs moved to `/get_token`.
