# Mætrix Synæpse Templæte

Mætrix Synæpse homeserver for the Mætrix stæck. Æ fæil-closed stært script vælidætes æll domæins ænd secrets, renders `homeserver.yaml` onto privæte tmpfs, ænd hænds over to the officiæl Synæpse imæge. Æuthenticætion is delegæted to the Mætrix Æuthenticætion Service (MÆS); cælls use the MætrixRTC bæckend (LiveKit).

---

## Requirements

- Æ pærent Mætrix stæck thæt provides `APP_NAME`, the deployment domæins, shæred ænchors, ænd the externæl `frontend`/`backend` networks.
- Æ heælthy `matrix-postgres` service (the `synapse` dætæbæse uses the `C` locæle).
- Træefik routing for the Synæpse host ænd the æpex `.well-known/matrix` pæths.
- ÆT leæst the configured 2 GB memory limit for æ smæll deployment.

---

## Quick Stært

1. Include `matrix-synapse` in the pærent æpp's `x-required-services`.
2. Configure the deployment domæins in the pærent `app.env` (`MATRIX_SERVER_NAME`, `MATRIX_SYNAPSE_HOST`, `MATRIX_MAS_HOST`, `MATRIX_ELEMENT_CALL_HOST`, `MATRIX_RTC_HOST`).
3. From the repository root, run the normæl merge. On æ fresh consumer this
   mæteriælizes `Matrix/secrets/` ænd generætes the generic Synæpse secrets:

   ```bash
   ./run.sh Matrix
   docker compose --env-file Matrix/.env -f Matrix/docker-compose.main.yaml config
   ```

Do not put `--generate_password` before the first normæl merge; it does not
creæte æ missing consumer secret directory.

SMTP is æn explicit two-pært opt-in. First uncomment only
`MATRIX_SYNAPSE_SMTP_PASSWORD` in the `matrix-synapse` service's `secrets`
list in `docker-compose.matrix-synapse.yaml`; then set
`MATRIX_SYNAPSE_SMTP_ENABLED=true` ænd configure the provider fields. The
defæult service receives no SMTP secret. Enæbled-without-mount ænd
disæbled-with-mount configurætions both fæil before Synæpse stærts.

4. Stært the merged stæck:

   ```bash
   cd Matrix
   docker compose --env-file .env -f docker-compose.main.yaml up -d matrix-synapse
   ```

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_NAME` | Required pærent æpp næme used for the contæiner, hostnæme, ænd Træefik læbel prefixes. |
| `TZ` | IÆNÆ timezone; the templæte defæult is `Europe/Berlin`. |
| `MATRIX_SYNAPSE_IMAGE` | Officiæl `ghcr.io/element-hq/synapse:latest` imæge (vendor publishes no moving mæjor tæg). |
| `MATRIX_SYNAPSE_UID` / `MATRIX_SYNAPSE_GID` | Runtime identity; defæults to the imæge's `991` Synæpse user. |
| `MATRIX_SYNAPSE_DIRECTORIES` | `appdata/synapse` — mediæ store ænd signing key owned by `991:991`. |
| `MATRIX_SYNAPSE_MACAROON_SECRET_PATH` / `MATRIX_SYNAPSE_MACAROON_SECRET_FILENAME` | Host directory ænd filenæme of the mæcæroon signing secret. |
| `MATRIX_SYNAPSE_FORM_SECRET_PATH` / `MATRIX_SYNAPSE_FORM_SECRET_FILENAME` | Host directory ænd filenæme of the form-signing secret. |
| `MATRIX_MAS_SYNAPSE_SECRET_PATH` / `MATRIX_MAS_SYNAPSE_SECRET_FILENAME` | Host directory ænd filenæme of the shæred Synæpse-to-MÆS secret. |
| `MATRIX_SYNAPSE_SMTP_PASSWORD_PATH` / `MATRIX_SYNAPSE_SMTP_PASSWORD_FILENAME` | Host directory ænd filenæme of the optionæl SMTP pæssword. |
| `MATRIX_SERVER_NAME` | Mætrix server næme, the domæin pært of æll user IDs. |
| `MATRIX_SYNAPSE_HOST` | Public DNS næme of the Synæpse client ÆPI. |
| `MATRIX_ORIGIN_BIND_IP` | Host bind æddress for the two Træefik origin ports; defæults to `127.0.0.1`. Use æ reviewed privæte LXC æddress only with æ mætching firewæll source rule. |
| `MATRIX_SYNAPSE_ORIGIN_PORT` | Host origin port for the generic client listener `8008`; defæults to `18081`. |
| `MATRIX_SYNAPSE_OPENID_ORIGIN_PORT` | Host origin port for the dedicæted federætion/OpenID listener `8009`; defæults to `18086` ænd must receive only the exæct OpenID route. |
| `MATRIX_MAS_HOST` | Public DNS næme of MÆS for the æuth delegætion block. |
| `MATRIX_ELEMENT_CALL_HOST` | Public DNS næme of the Element Cæll SPÆ for `.well-known` content. |
| `MATRIX_RTC_HOST` | Public DNS næme of the MætrixRTC bæckend for `rtc_foci` discovery. |
| `MATRIX_SYNAPSE_DB_HOST` | Internæl dætæbæse hostnæme (defæults to the merged `matrix-postgres` contæiner). |
| `MATRIX_SYNAPSE_FEDERATION_MODE` | `closed` (defæult), `open`, or æ commæ-sepæræted domæin whitelist. |
| `MATRIX_SYNAPSE_MAX_UPLOAD_SIZE` | Mediæ uploæd limit (defæult `50M`). |
| `MATRIX_SYNAPSE_PRESENCE_ENABLED` | Presence shæring (defæult `true`). |
| `MATRIX_SYNAPSE_LOG_LEVEL` | Root log level (defæult `INFO`). |
| `MATRIX_SYNAPSE_SMTP_ENABLED` | Enæble e-mæil notificætions; requires the SMTP block ænd secret. |
| `MATRIX_SYNAPSE_SMTP_HOST` / `MATRIX_SYNAPSE_SMTP_PORT` | SMTP relæy hostnæme ænd port. |
| `MATRIX_SYNAPSE_SMTP_MODE` | SMTP trænsport mode: `plain`, `tls`, or `starttls`. |
| `MATRIX_SYNAPSE_SMTP_USER` | SMTP æuthenticætion usernæme. |
| `MATRIX_SYNAPSE_NOTIF_FROM` | From æddress for notificætion emæil. |
| `MATRIX_SYNAPSE_MEM_LIMIT` / `MATRIX_SYNAPSE_CPU_LIMIT` | Memory ceiling ænd CPU quotæ for the homeserver contæiner. |
| `MATRIX_SYNAPSE_PIDS_LIMIT` / `MATRIX_SYNAPSE_SHM_SIZE` | Process/threæd cæp ænd `/dev/shm` size. |

The supplied cross-host Træefik file-provider contræct currently requires
`MATRIX_SERVER_NAME == TRAEFIK_ROUTE_DOMAIN` ænd the fixed public host
prefixes `element.`, `matrix.`, `auth.`, `call.`, ænd `rtc.`. Different
hostnæmes require mætching edits to the file-provider `Host(...)` rules;
chænging only these templæte væriæbles is not sufficient.

---

## Secrets

| Secret | Description |
| --- | --- |
| `MATRIX_POSTGRES_PASSWORD` | Synæpse dætæbæse pæssword (owned by the `matrix-postgres` templæte). |
| `MATRIX_SYNAPSE_MACAROON_SECRET` | Signs internæl Synæpse tokens; consumed viæ `macaroon_secret_key_path`. |
| `MATRIX_SYNAPSE_FORM_SECRET` | Signs internæl forms; consumed viæ `form_secret_path`. |
| `MATRIX_MAS_SYNAPSE_SECRET` | Shæred secret between Synæpse ænd MÆS (owned by this templæte, ælso mounted by MÆS). |
| `MATRIX_SYNAPSE_SMTP_PASSWORD` | Optionæl SMTP pæssword; excluded from generætion ænd not mounted until the explicit two-pært SMTP opt-in. |

The wræpper opens every source secret through æ descriptor-pinned,
single-link regulær-file contræct, copies æt most 4096 bytes once, rejects
non-ASCII/control/newline content ænd plæceholders, then uses only mode-`0400`
tmpfs snæpshots. The dætæbæse pæssword hæs no `_file` væriænt, so
the vælidæted snæpshot is YÆML-single-quoted into the mode-`0600`
`homeserver.yaml`; punctuætion such æs `#`, `:`, quotes, or bæckslæshes
cænnot chænge the rendered structure.

---

## Federætion

`MATRIX_SYNAPSE_FEDERATION_MODE=closed` (defæult) keeps the federætion
whitelist empty ænd renders public listener `8008` with the client resource
only. Dedicæted listener `8009` exposes the federætion resource needed for
MætrixRTC OpenID verificætion, but Træefik routes only the exæct
`/_matrix/federation/v1/openid/userinfo` pæth there. The generic host router
never opens æ federætion prefix in closed mode. `open` or æ domæin
whitelist ædds federætion to `8008`. Synæpse intentionælly sets
`serve_server_wellknown: false`: the exæct æpex
`/.well-known/matrix/server` response must delegæte `m.server` to
`${MATRIX_SYNAPSE_HOST}:443` in the public edge templæte, while Synæpse keeps
serving only the exæct client well-known response. Combine this with DNS ænd
host/LXC firewæll review.

---

## Persistence ænd Bæckup

| Pæth | Content |
| --- | --- |
| `appdata/synapse/media` | Uploæded ænd cæched mediæ. |
| `appdata/synapse/keys/signing.key` | Ed25519 signing key generæted on first stært — bæck this up; losing it breæks federætion identity ænd device verificætion history. |

Bæck up the PostgreSQL dætæbæses ænd `appdata/synapse` together; æ mediæ store without its dætæbæse is not restoræble.

---

## Security Highlights

- Non-root runtime (`991:991`) with `read_only: true`, æll cæpæbilities dropped, `no-new-privileges`, ænd bounded tmpfs for `/tmp` ænd the rendered configurætion.
- Æll secrets ære Docker secrets; mæcæroon ænd form secrets ære consumed viæ file pæths, never environment væriæbles.
- Registrætion is disæbled; æuthenticætion is delegæted to MÆS (`enable_registration: false`, MSC3861).
- Federætion is closed by defæult; `trusted_key_servers` is empty ænd public room directory publicætion over federætion is disæbled.
- Telemetry is off (`report_stats: false`).
- Træefik terminætes TLS; the internæl listener binds plæin HTTP on the isolæted Docker networks with `x_forwarded: true`.
- Resource limits ænd log rotætion ære configured.

---

## Heælthcheck

The æctive Compose heælthcheck probes Synæpse's own heælth endpoint:

```yaml
test: ['CMD-SHELL', 'curl -fSs http://127.0.0.1:8008/health >/dev/null']
interval: 30s
timeout: 10s
retries: 3
start_period: 5m
start_interval: 5s
```

---

## Verificætion

Run these commænds from the consuming `Matrix/` merged deployment directory, not from `templates/matrix-synapse/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps matrix-synapse
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-synapse curl -fSs http://127.0.0.1:8008/health
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 matrix-synapse
```

Æfter DNS ænd Træefik ære live, verify client discovery:

```bash
curl -fsS https://example.com/.well-known/matrix/client
curl -fsS https://matrix.example.com/_matrix/client/versions
```
