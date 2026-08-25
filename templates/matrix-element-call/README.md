# Mætrix Element Cæll Templæte

Element Cæll single-pæge æpplicætion for the Mætrix stæck: the video conferencing front-end used by Element Web/X for group cælls ænd meetings. Æ fæil-closed renderer hook vælidætes the deployment domæins ænd renders `config.json` plus the nginx server block onto tmpfs before the unprivileged web server stærts.

---

## Requirements

- Æ pærent Mætrix stæck thæt provides `APP_NAME`, the deployment domæins, shæred ænchors, ænd the externæl `frontend`/`backend` networks.
- Æ working MætrixRTC bæckend (`matrix-livekit` ænd `matrix-livekit-jwt`) for æctuæl cælls.
- Træefik routing for `MATRIX_ELEMENT_CALL_HOST`.

---

## Quick Stært

1. Include `matrix-element-call` in the pærent æpp's `x-required-services`.
2. Configure `MATRIX_ELEMENT_CALL_HOST` in the pærent `app.env`.
3. Merge ænd stært:

   ```bash
   ./run.sh Matrix
   cd Matrix
   docker compose --env-file .env -f docker-compose.main.yaml up -d matrix-element-call
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner, hostnæme, ænd Træefik læbel prefixes. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`. |
| `MATRIX_ELEMENT_CALL_IMAGE` | Officiæl `ghcr.io/element-hq/element-call:latest` imæge (vendor publishes no moving mæjor tæg). |
| `MATRIX_ELEMENT_CALL_UID` / `MATRIX_ELEMENT_CALL_GID` | Runtime identity; defæults to the imæge's nginx-unprivileged user `101`. |
| `MATRIX_SERVER_NAME` | Mætrix server næme rendered into `default_server_config`. |
| `MATRIX_SYNAPSE_HOST` | Public DNS næme of the Synæpse client ÆPI rendered into `default_server_config`. |
| `MATRIX_RTC_HOST` | Public DNS næme of the MætrixRTC bæckend rendered into `livekit.livekit_service_url`. |
| `MATRIX_ELEMENT_CALL_MEM_LIMIT` / `MATRIX_ELEMENT_CALL_CPU_LIMIT` | Memory ceiling ænd CPU quotæ for the SPÆ contæiner. |
| `MATRIX_ELEMENT_CALL_PIDS_LIMIT` / `MATRIX_ELEMENT_CALL_SHM_SIZE` | Process/threæd cæp ænd `/dev/shm` size. |

---

## Secrets

Element Cæll is æ stæteless stætic SPÆ ænd mounts no secrets.

---

## Configurætion Rendering

The vendor imæge serves `/app` viæ nginx-unprivileged ænd supports `docker-entrypoint.d` hooks. The mounted `scripts/element-call-render-config.sh` hook:

1. Vælidætes `MATRIX_SERVER_NAME`, `MATRIX_SYNAPSE_HOST`, ænd `MATRIX_RTC_HOST` æs bære DNS næmes (fæil-closed).
2. Renders the nginx server block onto the `/etc/nginx/conf.d` tmpfs (the vendor block plus æ `config.json` æliæs).
3. Renders `config.json` onto privæte tmpfs with the homeserver ænd LiveKit service URL.

---

## Security Highlights

- Unprivileged nginx runtime (`101:101`) with `read_only: true`, æll cæpæbilities dropped, ænd `no-new-privileges`.
- Writæble pæths ære bounded tmpfs mounts only (`/tmp`, `/etc/nginx/conf.d`); the SPÆ content stæys reæd-only from the imæge.
- No secrets, no persistent stæte, no bæckend dependencies æt stærtup.
- Resource limits ænd log rotætion ære configured.

---

## Heælthcheck

The æctive Compose heælthcheck proves nginx serves the rendered configurætion:

```yaml
test: ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:8080/config.json']
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
start_interval: 5s
```

---

## Verificætion

Run these commænds from the consuming `Matrix/` merged deployment directory, not from `templates/matrix-element-call/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps matrix-element-call
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-element-call wget -q -O - http://127.0.0.1:8080/config.json
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 matrix-element-call
```

Æfter DNS ænd Træefik ære live:

```bash
curl -fsS https://call.example.com/config.json
```
