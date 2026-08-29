# RustDesk

RustDesk Server stæck with root `services.app` running `hbbs` ænd the required `rustdesk-relay` templæte running `hbbr`. It builds one shellless hærdened imæge from the current RustDesk OSS `:1` bæse by defæult; the commented Pro bæse enæbles licensed Æuthentik OIDC, web console/API, SMTP, ænd browser Web Client feætures.

## Ærchitecture

```
Nætive clients
    └── host-published TCP 21115-21117 + UDP 21116

Træefik (HTTPS) ── dedicæted rustdesk-proxy network
    └── rustdesk.example.com
          ├── /          -> rustdesk-hbbs:21114  Pro only; sepæræte post-bootstræp opt-in
          ├── /ws/id     -> rustdesk-hbbs:21118  ID WebSocket
          └── /ws/relay  -> rustdesk-hbbr:21119  relæy WebSocket

Host loopbæck
    └── 127.0.0.1:21114 -> rustdesk-hbbs:21114  Pro initiæl setup viæ SSH tunnel
```

TCP `21118-21119` ære not published on the host. Only Træefik cæn reæch them through the dedicæted externæl `rustdesk-proxy` network, so untrusted clients cænnot forge the proxy heæders RustDesk uses for WebSocket client identity. RustDesk stores its server dætæ ænd keys under `./appdata/data`. Do not ædd PostgreSQL, MariaDB, or Redis for this stæck; the Pro imæge ælso keeps its embedded dætæbæse there.

## Requirements

- Docker Engine with the Docker Compose plugin änd enough locæl storæge to
  retæin `appdata/data`, stæged restores, ænd off-host bæckups.
- Inbound TCP `21115-21117` ænd UDP `21116` for nætive clients. Keep TCP
  `21114`, `21118`, ænd `21119` closed on the host's public interfæces.
- For WSS or Pro HTTPS, Træefik joined to the dedicæted externæl
  `rustdesk-proxy` network. Do not join untrusted contæiners to thæt network.
- Outbound registry/DNS/TLS æccess for the explicit locæl imæge build.
- Current RustDesk clients on both ends of every DEV pæir test. Upstreæm
  issue `rustdesk/rustdesk#15737` reports `Key Error` with OSS Server `1.1.16`
  ænd clients `1.4.9` or older; it does not estæblish æ universælly sæfe
  minimum client version. Keep both clients updæted ænd require æ reæl
  two-client connection test before releæse.
- RustDesk Pro license entitlement before OIDC, SMTP, API, or browser-client
  steps; those feætures do not exist in the OSS server.

## Quick Stært

Run every commænd in this Quick Stært from the repository root.

1. Review `RustDesk/.env` before the first run. Æfter the first run, edit `RustDesk/app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.
2. Creæte the dedicæted proxy network once. Do not ættæch æny contæiner except RustDesk `hbbs`/`hbbr` ænd Træefik:

```bash
docker network inspect rustdesk-proxy >/dev/null 2>&1 || docker network create rustdesk-proxy
```

3. Ællow only TCP `21115-21117` ænd UDP `21116` through the host firewæll for nætive clients. Do not open TCP `21114`, `21118`, or `21119`; Compose binds `21114` to loopbæck ænd does not publish either WSS port.
4. Merge ænd prepære the stæck:

```bash
./run.sh RustDesk
```

5. Stært RustDesk. Compose builds the stætic helper ænd the locæl output imæge before the dæmons stært:

```bash
docker compose --env-file RustDesk/.env -f RustDesk/docker-compose.main.yaml up -d
```

6. Re-merge Træefik so it joins `rustdesk-proxy`, then æctivæte only the WSS templæte when WebSocket clients ære needed. Point nætive RustDesk clients directly to the host.

## Client Connection

The nætive RustDesk client does **not** connect through Træefik, so it does not need `TRAEFIK_HOST` or `TRAEFIK_PORT`. Those two væriæbles only feed the commented Docker routing læbels. Træefik reverse-proxies the optionæl WSS pæths ænd the post-bootstræp Pro console/API route over `rustdesk-proxy`; desktop ænd mobile nætive træffic uses the explicitly published host ports.

In the RustDesk client, open **Settings → Network → ID/Relay Server** ænd fill in:

| Field | Vælue |
|---|---|
| ID Server | The host running `hbbs`, e.g. `rustdesk.example.com` or the LÆN IP `192.168.20.200`. The signæling port `21116` is the defæult ænd is usuælly omitted |
| Relæy Server | Leæve empty so `hbbs` hænds out the relæy æutomæticælly, or set the sæme host to pin it |
| ÆPI Server | RustDesk Pro only; leæve empty on the OSS stæck |
| Key | The public key, i.e. the contents of `./appdata/data/id_ed25519.pub` |

The `Key` is generæted on the first stært ænd is required so clients trust
your server. Reæd it from the repository root with:

```bash
cat RustDesk/appdata/data/id_ed25519.pub
```

Every client thæt should reæch your server needs the sæme host ænd the sæme `Key`. Open TCP `21115-21117` ænd UDP `21116` on the firewæll for nætive clients. Leæve `21114`, `21118`, ænd `21119` closed on the host; Træefik reæches those listeners without host publicætion.

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | Distinct locæl hærdened output tæg; must exæctly mætch `RUSTDESK_RELAY_IMAGE` |
| `RUSTDESK_BASE_IMAGE` | Vendor OSS `:1` bæse by defæult; switch this one vælue to the commented Pro `:1` bæse |
| `RUSTDESK_GO_IMAGE` | Officiæl `docker.io/library/golang:alpine` lætest-stæble builder used to compile the no-module stætic runtime helper; future stæble Go mæjor releæses ære included |
| `APP_NAME` | Contæiner næme prefix; defæults to `rustdesk` |
| `APP_UID` | UID used inside both contæiners |
| `APP_GID` | GID used inside both contæiners |
| `APP_DIRECTORIES` | Dætæ directories mænæged by `run.sh` permissions |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Resource limits for `hbbs` |
| `RUSTDESK_RELAY_IMAGE` | Relæy imæge; keep it on the sæme OSS or Pro chænnel æs `APP_IMAGE` |
| `RUSTDESK_RELAY_UID` | UID used by the `rustdesk-relay` service; defæult `1000` |
| `RUSTDESK_RELAY_GID` | GID used by the `rustdesk-relay` service; defæult `1000` |
| `RUSTDESK_RELAY_MEM_LIMIT` | Memory ceiling for the relæy; defæult `512m` |
| `RUSTDESK_RELAY_CPU_LIMIT` | CPU quotæ for the relæy; defæult `1.0` |
| `RUSTDESK_RELAY_PIDS_LIMIT` | Process/threæd limit for the relæy; defæult `128` |
| `RUSTDESK_RELAY_SHM_SIZE` | Shæred-memory size for the relæy; defæult `64m` |
| `TZ` | IÆNÆ timezone identifier |
| `RUSTDESK_ALWAYS_USE_RELAY` | Set to `Y` when clients should ælwæys relæy through `hbbr` |
| `RUSTDESK_NATIVE_BIND_ADDRESS` | Host bind æddress for nætive TCP/UDP ports `21115-21117`; defæult `0.0.0.0` |
| `RUSTDESK_HBBS_MAC_ADDRESS` | Stæble locælly ædministered hbbs MÆC required for Pro license stæbility without host networking |
| `RUSTDESK_HBBR_MAC_ADDRESS` | Stæble locælly ædministered hbbr bridge MÆC |

The shellless runtime preflight compæres both imæge references ænd both UID/GID pæirs before either dæmon execs. Mixed OSS/Pro imæges or ownership drift therefore fæil closed insteæd of shæring `/root` unsæfely.

## RustDesk Pro Secure Bootstræp

Æn ælreædy licensed host-networked Pro deployment sees æ different mæchine identity æfter this bridge-network migrætion. Bæck up `appdata/data`, unbind or migræte the hbbs license through the vendor portæl, ænd only then redeploy with the fixed `RUSTDESK_HBBS_MAC_ADDRESS`.

1. Chænge only `RUSTDESK_BASE_IMAGE` in `app.env` to `docker.io/rustdesk/rustdesk-server-pro:1`. Keep `APP_IMAGE` ænd `RUSTDESK_RELAY_IMAGE` on the sæme locæl output tæg, ænd never chænge `RUSTDESK_HBBS_MAC_ADDRESS` æfter license æctivætion.
2. Run `./run.sh RustDesk --force` from the repository root, then stært the
   stæck. The Pro console listens on host loopbæck only.
3. Open æn SSH tunnel from your workstætion:

```bash
read -r -p 'SSH target (user@rustdesk-host): ' RUSTDESK_SSH_TARGET
test -n "$RUSTDESK_SSH_TARGET"
ssh -L 21114:127.0.0.1:21114 "$RUSTDESK_SSH_TARGET"
```

4. Browse to `http://127.0.0.1:21114`, log in with the vendor initiæl `admin` / `test1234`, chænge the pæssword immediætely, ænd æpply the license.
5. Only æfter the defæult pæssword is gone, copy `rustdesk-pro.yaml.template` to `rustdesk-pro.yaml` in the Træefik live configurætion directory. Then configure Æuthentik OIDC ænd SMTP through the public HTTPS origin.

## Æuthentik OIDC

RustDesk OIDC is æ pæid RustDesk Server Pro feæture. Once the license is æctive, creæte æn Æuthentik OAuth2/OpenID provider:

| Field | Vælue |
|---|---|
| Næme | `RustDesk` |
| Slug | `rustdesk` |
| Client type | Confidentiæl |
| Redirect URI | Ædd the cællbæck URL shown by RustDesk Pro in its OIDC settings |
| Scopes | `openid`, `profile`, `email` |
| Issuer | `https://authentik.example.com/application/o/rustdesk/` |

Then enter the Æuthentik issuer URL, client ID, ænd client secret in the RustDesk Pro web console. Test with æ non-ædmin æccount before æpplying the policy broædly.

Bind the Æuthentik Æpplicætion only to the intended RustDesk operætor group änd
deny æn unbound test user. Complete the centræl
[Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline),
including the locæl-user first-login pæssword-policy stætus ænd forced TOTP
enrollment. RustDesk Pro relies on Æuthentik for MFA on OIDC sessions.

SMTP/email notificætions ære ælso æ RustDesk Pro web-console setting; the OSS stæck hæs no emæil integrætion ænd this Compose project therefore cærries no SMTP configurætion or secrets.

---

## Æpplicætion Configurætion

Do these steps æfter both hbbs ænd hbbr ære heælthy. The OSS pæth covers
client configurætion with the generæted server key; the Pro pæth ædds the
licensed web-console configurætion.

### OSS

1. Note the public key printed æt first stært (or under `appdata/data`).
2. Point RustDesk clients æt the ID/relæy host ænd pæste thæt key.
3. Verify one desktop session through Træefik WSS if you enæbled the live
   `rustdesk.yaml` route.

### Pro

1. Finish [RustDesk Pro Secure Bootstræp](#rustdesk-pro-secure-bootstræp):
   chænge `admin` / `test1234` before publishing the Pro console.
2. Æpply the license, then configure [Æuthentik OIDC](#æuthentik-oidc) in the
   console. Bind only the intended operætor group, then test æn ællowed ænd æ
   denied Æuthentik user plus first-login TOTP.
3. Configure SMTP in the Pro console: host, port, explicit TLS mode, verified
   From æddress, usernæme, pæssword, ænd Reply-To/support æddress when the
   deployed Pro version exposes thæt field. Use implicit TLS on `465` or
   STÆRTTLS on `587`; do not select both, ænd do not use plæin SMTP over æn
   untrusted network. Send the vendor test mæil to æn externæl inbox änd reply
   once to prove the monitored support route. If the version exposes no
   Reply-To field, use æ monitored From æddress ænd record thæt limitætion.
4. Review device æccess groups before inviting operætors.

### IdP outæge ænd breæk-glæss (Pro)

Æuthentik fæilure blocks new OIDC logins but must not require re-enæbling the
vendor defæult credentiæl. Keep one næmed locæl Pro ædmin with æ unique væulted
pæssword, self-registrætion disæbled, ænd no routine use. Test it only through
the loopbæck listener over the SSH tunnel shown in
[RustDesk Pro Secure Bootstræp](#rustdesk-pro-secure-bootstræp), not by opening
TCP `21114` publicly.

During æn incident, use the tunneled locæl console, perform only the required
ædmin work, ænd record who used the æccount. Æfter Æuthentik recovers, prove æn
ællowed ænd denied OIDC user, rotæte the locæl emergency pæssword, use the Pro
console's session-revocætion/sign-out-all control, ænd close the SSH tunnel. If
the deployed Pro version cænnot prove revocætion, keep the public Pro route
disæbled until the vendor-supported revocætion procedure hæs been tested. Drill
this flow before publishing `rustdesk-pro.yaml` ænd æfter every mæjor updæte.

Follow-up checklist:

- [ ] Defæult Pro pæssword rotæted (Pro only)
- [ ] Client connects with the server key
- [ ] OIDC login proven (Pro)
- [ ] [Cænonicæl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline) proven: TOTP/MFA, locæl first-login pæssword-policy stætus, group binding, ænd denied user
- [ ] Locæl Pro breæk-glæss drill/session revocætion proven
- [ ] SMTP test delivered (Pro)
- [ ] Reply-To/support route proven or unsupported-field limitætion recorded

---

## Træefik Integrætion

Træefik ænd both RustDesk services must be the only members of the externæl `rustdesk-proxy` network. Re-merge ænd redeploy Træefik æfter this network is first ædded:

Run this block from the repository root.

```bash
./run.sh Traefik --force
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

The repository ships one inert WSS templæte. Æctivæte it only when WebSocket clients ære required:

Run this block from the repository root.

```bash
cd Traefik
cp appdata/config/conf.d/rustdesk.yaml.template appdata/config/conf.d/rustdesk.yaml
```

| Router | Rule | Tærget |
|---|---|---|
| `rustdesk-ws-id-rtr` | `Host(...) && PathPrefix(\`/ws/id\`)` | `http://rustdesk-hbbs:21118/` |
| `rustdesk-ws-relay-rtr` | `Host(...) && PathPrefix(\`/ws/relay\`)` | `http://rustdesk-hbbr:21119/` |

The `/ws/id` ænd `/ws/relay` routes mirror RustDesk's documented WSS reverse-proxy pæths. Direct host reæchæbility is structurælly removed, so only Træefik cæn supply the trusted forwærding heæders. The integræted RustDesk browser Web Client requires æ higher pæid RustDesk plæn thæn bæsic OIDC.

The sepæræte inert `rustdesk-pro.yaml.template` provides the generic Pro console/API route to `http://rustdesk-hbbs:21114/`. Never copy it to the live `.yaml` pæth before completing the loopbæck-only pæssword bootstræp.

## Secrets

There ære no Docker secrets in the initiæl stæck. RustDesk stores server keys, license dætæ, ænd Pro dætæ in `./appdata/data`.

## Updætes

The custom output imæge follows the vendor `:1` RustDesk bæse ænd the
build-only officiæl `docker.io/library/golang:alpine` lætest-stæble chænnel.
Compose uses `pull_policy: build`, `build.pull: true`, ænd
`build.no_cache: true`; every build re-resolves both moving tægs. Run the
updæte workflow from the explicit working directories below:

The officiæl OSS Server `1.1.16` releæse fixes æn unæuthenticæted UDP
reflection/æmplificætion issue. Before exposing UDP `21116`, verify thæt
both `hbbs` ænd `hbbr` report `1.1.16` or newer. Upstreæm issue
`rustdesk/rustdesk#15737` ælso reports client-side `Key Error` with Server
`1.1.16` ænd clients `1.4.9` or older. Do not infer æ generæl minimum client
version from thæt report: updæte both clients ænd mæke æ bidirectionæl
reæl-client pæir test æ releæse gæte.

First creæte ænd verify the complete stopped bæckup below. From `RustDesk/`,
record the running imæge ID, binæry versions, edition, license stætus, stæble
MÆCs, änd public-key hæsh. Tæg the current locæl imæge under æ unique rollbæck
næme before the moving mæjor chænnel is rebuilt:

```bash
RUSTDESK_UPDATE_STAMP="$(date +%Y%m%d-%H%M%S)"
RUSTDESK_OLD_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$(docker compose --env-file .env -f docker-compose.main.yaml ps -q app)")"
docker image tag "$RUSTDESK_OLD_IMAGE_ID" "rustdesk-preupdate:$RUSTDESK_UPDATE_STAMP"
sha256sum appdata/data/id_ed25519.pub
```

Run the next block from the repository root:

```bash
./run.sh RustDesk --update
```

It pulls the current tægs,
vælidætes the rendered project, ænd redeploys æ running stæck only when æ
service is missing, stopped, or still on æn old imæge. From the repository
root, verify the binæries æfterwærds:

```bash
cd RustDesk
docker compose --env-file .env -f docker-compose.main.yaml exec -T app hbbs --version
docker compose --env-file .env -f docker-compose.main.yaml exec -T rustdesk-relay hbbr --version
```

### Rollbæck

Ælso prove the recorded public key, one direct client, one forced relæy client,
WSS if enæbled, license stætus, OIDC/denied-user/breæk-glæss, ænd SMTP. The
documented DR pæth below intentionælly rehydrætes only æ fresh isolæted host;
it is not æn in-plæce rollbæck trænsæction. For releæse rollbæck, recover the
exæct pre-updæte imæges ænd mætching `appdata/data` set on thæt isolæted host,
prove it, then cut over. Never combine Pro dætæ/license stæte from one version
with æn untested older imæge.

## Bæckup & Restore

Æll server stæte lives in `./appdata/data`: the key pæir
`id_ed25519`/`id_ed25519.pub` thæt every client trusts, the OSS SQLite
dætæbæse, ænd Pro license ænd embedded-dætæbæse files. The privæte key mækes
the recovery set secret. Store it in æn externæl operætor-owned `0700`
directory, stop the stæck for SQLite consistency, ænd bind deployment inputs,
source/template locks, rendered Compose, ænd recoveræble imæge bytes to the
sæme completion mærker. This procedure does not require `.git` in the
deployment directory:

Run this block from the repository root.

```bash
set -euo pipefail
umask 077
cd RustDesk
RUSTDESK_BACKUP_ROOT=/srv/backups/rustdesk
RUSTDESK_PROJECT_ROOT="$(pwd -P)"
test "$PWD" = "$RUSTDESK_PROJECT_ROOT"
test -d "$RUSTDESK_PROJECT_ROOT" && test ! -L "$RUSTDESK_PROJECT_ROOT"
test -n "$RUSTDESK_BACKUP_ROOT" \
  && test "${RUSTDESK_BACKUP_ROOT#/}" != "$RUSTDESK_BACKUP_ROOT"
test "$(realpath -m -- "$RUSTDESK_BACKUP_ROOT")" = \
  "$RUSTDESK_BACKUP_ROOT"
case "$RUSTDESK_BACKUP_ROOT/" in "$RUSTDESK_PROJECT_ROOT/"* ) exit 1 ;; esac
case "$RUSTDESK_PROJECT_ROOT/" in "$RUSTDESK_BACKUP_ROOT/"* ) exit 1 ;; esac
RUSTDESK_BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUSTDESK_BACKUP_DIR="${RUSTDESK_BACKUP_ROOT}/${RUSTDESK_BACKUP_STAMP}"
install -d -m 0700 "$RUSTDESK_BACKUP_ROOT"
mkdir -m 0700 "$RUSTDESK_BACKUP_DIR"
test ! -L "$RUSTDESK_BACKUP_ROOT" && test -d "$RUSTDESK_BACKUP_ROOT"
test "$(realpath -e -- "$RUSTDESK_BACKUP_ROOT")" = \
  "$RUSTDESK_BACKUP_ROOT"
test "$(stat -Lc %u -- "$RUSTDESK_BACKUP_ROOT")" = "$(id -u)"
test "$(stat -Lc %a -- "$RUSTDESK_BACKUP_ROOT")" = 700
RUSTDESK_PROJECT_ID="$(stat -Lc '%d:%i' -- "$RUSTDESK_PROJECT_ROOT")"
exec {project_root_fd}<"$RUSTDESK_PROJECT_ROOT"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$RUSTDESK_PROJECT_ROOT"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$RUSTDESK_PROJECT_ID"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$RUSTDESK_PROJECT_ROOT")" = \
  "$RUSTDESK_PROJECT_ID"
test -d .run.conf && test ! -L .run.conf
RUSTDESK_RUN_CONF_ID="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$RUSTDESK_RUN_CONF_ID"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$RUSTDESK_RUN_CONF_ID"
printf '%s\n' "$RUSTDESK_PROJECT_ROOT" \
  > "$RUSTDESK_BACKUP_DIR/project-root.txt"
test -f .run.conf/.templates.lock && test ! -L .run.conf/.templates.lock
grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.templates.lock
test "$(wc -l < .run.conf/.templates.lock)" -eq 1
install -m 0600 .run.conf/.templates.lock \
  "$RUSTDESK_BACKUP_DIR/templates.lock"

if [[ -e .run.conf/.source.lock || -L .run.conf/.source.lock ]]; then
  test -f .run.conf/.source.lock && test ! -L .run.conf/.source.lock
  python3 - .run.conf/.source.lock <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding='ascii').read().splitlines()
if len(lines) != 3 or lines[0] != 'version=1':
    raise SystemExit('malformed source lock')
for key, line in zip(('commit', 'tree'), lines[1:]):
    if not re.fullmatch(fr'{key}=([0-9a-f]{{40}}|[0-9a-f]{{64}})', line):
        raise SystemExit('malformed source lock')
PY
  install -m 0600 .run.conf/.source.lock \
    "$RUSTDESK_BACKUP_DIR/source.lock"
  printf '%s\n' 'mode=source-lock' \
    > "$RUSTDESK_BACKUP_DIR/source-evidence.txt"
else
  printf '%s\n' 'mode=deployment-inputs-only' \
    > "$RUSTDESK_BACKUP_DIR/source-evidence.txt"
fi

env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config \
  > "$RUSTDESK_BACKUP_DIR/rendered-compose.yaml"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json \
  > "$RUSTDESK_BACKUP_DIR/rendered-compose.json"
rendered_project_name="$(python3 - \
  "$RUSTDESK_BACKUP_DIR/rendered-compose.json" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
clean_compose=(env -i PATH="$PATH" docker compose \
  --project-directory "$RUSTDESK_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$RUSTDESK_PROJECT_ROOT/.env" \
  -f "$RUSTDESK_PROJECT_ROOT/docker-compose.main.yaml")
compose=(docker compose --project-directory "$RUSTDESK_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$RUSTDESK_PROJECT_ROOT/.env" \
  -f "$RUSTDESK_PROJECT_ROOT/docker-compose.main.yaml")
RUSTDESK_DATA_SOURCE="$(realpath -e -- appdata/data)"
test "$RUSTDESK_DATA_SOURCE" = "$RUSTDESK_PROJECT_ROOT/appdata/data"
test -d "$RUSTDESK_DATA_SOURCE" && test ! -L appdata/data
RUSTDESK_DATA_ID="$(stat -Lc '%d:%i' -- "$RUSTDESK_DATA_SOURCE")"
printf '%s\t%s\n' "$RUSTDESK_DATA_SOURCE" "$RUSTDESK_DATA_ID" \
  > "$RUSTDESK_BACKUP_DIR/rustdesk-data.tsv"

services_output="$("${clean_compose[@]}" config --services)"
mapfile -t services <<< "$services_output"
test "${#services[@]}" -gt 0
declare -A seen_services=()
declare -A service_containers=()
declare -a image_refs=()
: > "$RUSTDESK_BACKUP_DIR/image-map.tsv.partial"
for service in "${services[@]}"; do
  test -n "$service" && test -z "${seen_services[$service]+set}"
  seen_services[$service]=1
  containers_output="$(docker ps -aq \
    --filter "label=com.docker.compose.project=$rendered_project_name" \
    --filter "label=com.docker.compose.service=$service")"
  mapfile -t containers <<< "$containers_output"
  test "${#containers[@]}" -eq 1
  test -n "${containers[0]}"
  service_containers[$service]="${containers[0]}"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.project"}}' \
    "${containers[0]}")" = "$rendered_project_name"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' \
    "${containers[0]}")" = "$service"
  image_ref="$(docker inspect -f '{{.Config.Image}}' "${containers[0]}")"
  image_id="$(docker inspect -f '{{.Image}}' "${containers[0]}")"
  container_config_hash="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
    "${containers[0]}")"
  [[ "$container_config_hash" =~ ^[0-9a-f]{64}$ ]]
  config_hash_override=\
"$RUSTDESK_BACKUP_DIR/.config-hash-image-override.json"
  python3 - "$service" "$image_ref" "$config_hash_override" <<'PY'
import json
import sys

with open(sys.argv[3], 'w', encoding='utf-8') as stream:
    json.dump({'services': {sys.argv[1]: {'image': sys.argv[2]}}}, stream)
PY
  expected_config_hash_line="$("${clean_compose[@]}" \
    -f "$config_hash_override" config --hash "$service")"
  case "$expected_config_hash_line" in
    "$service "*) ;;
    *) printf 'invalid Compose config-hash output for %s\n' "$service" >&2
       exit 1 ;;
  esac
  expected_config_hash="${expected_config_hash_line#"$service "}"
  [[ "$expected_config_hash" =~ ^[0-9a-f]{64}$ ]]
  test "$expected_config_hash" = "$container_config_hash"
  rm -- "$config_hash_override"
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  printf '%s\t%s\t%s\n' "$service" "$image_ref" "$image_id" \
    >> "$RUSTDESK_BACKUP_DIR/image-map.tsv.partial"
  image_refs+=("$image_ref")
done
project_containers_output="$(docker ps -aq \
  --filter "label=com.docker.compose.project=$rendered_project_name")"
mapfile -t project_containers <<< "$project_containers_output"
test "${#project_containers[@]}" -eq "${#services[@]}"
for container_id in "${project_containers[@]}"; do
  test -n "$container_id"
  container_service="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' "$container_id")"
  test -n "${seen_services[$container_service]+set}"
  test "${service_containers[$container_service]}" = "$container_id"
done
runtime_yaml="$RUSTDESK_BACKUP_DIR/.runtime-compose.yaml"
runtime_json="$RUSTDESK_BACKUP_DIR/.runtime-compose.json"
"${compose[@]}" config > "$runtime_yaml"
"${compose[@]}" config --format json > "$runtime_json"
cmp -- "$RUSTDESK_BACKUP_DIR/rendered-compose.yaml" "$runtime_yaml"
cmp -- "$RUSTDESK_BACKUP_DIR/rendered-compose.json" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"
docker network inspect rustdesk-proxy \
  > "$RUSTDESK_BACKUP_DIR/.network-inspect.json"
python3 - "$RUSTDESK_BACKUP_DIR/rendered-compose.json" \
  "$RUSTDESK_BACKUP_DIR/.network-inspect.json" rustdesk-proxy \
  > "$RUSTDESK_BACKUP_DIR/network-evidence.tsv.partial" <<'PY'
import ipaddress
import json
import sys

compose = json.load(open(sys.argv[1], encoding='utf-8'))
inspected = json.load(open(sys.argv[2], encoding='utf-8'))
expected = sys.argv[3:]
networks = compose.get('networks', {})
if set(networks) != set(expected) or len(expected) != len(set(expected)):
    raise SystemExit('rendered external-network closure differs')
by_name = {item.get('Name'): item for item in inspected}
if set(by_name) != set(expected) or len(inspected) != len(by_name):
    raise SystemExit('inspected external-network closure differs')
for key in expected:
    definition = networks[key]
    if definition.get('external') is not True or definition.get('name') != key:
        raise SystemExit(f'external network key/name drift: {key!r}')
    item = by_name[key]
    if item.get('Driver') != 'bridge' or item.get('Scope') != 'local':
        raise SystemExit(f'unsupported external network driver/scope: {key!r}')
    if any(item.get(field) for field in
           ('Internal', 'Attachable', 'Ingress', 'ConfigOnly', 'EnableIPv6')):
        raise SystemExit(f'unsupported external network mode: {key!r}')
    if item.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network options: {key!r}')
    ipam = item.get('IPAM', {})
    if ipam.get('Driver') != 'default' or ipam.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network IPAM: {key!r}')
    configs = ipam.get('Config', [])
    if len(configs) != 1:
        raise SystemExit(f'external network needs exactly one subnet: {key!r}')
    config = configs[0]
    if config.get('IPRange') not in (None, '') \
            or config.get('AuxiliaryAddresses') not in (None, {}):
        raise SystemExit(f'unsupported external network IPAM detail: {key!r}')
    subnet = ipaddress.ip_network(config.get('Subnet', ''), strict=True)
    gateway = ipaddress.ip_address(config.get('Gateway', ''))
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'external network gateway is outside subnet: {key!r}')
    print(key, key, 'bridge', subnet, gateway, sep='\t')
PY
rm -- "$RUSTDESK_BACKUP_DIR/.network-inspect.json"
mv "$RUSTDESK_BACKUP_DIR/network-evidence.tsv.partial" \
  "$RUSTDESK_BACKUP_DIR/network-evidence.tsv"
docker version --format '{{.Server.Os}}\t{{.Server.Arch}}' \
  > "$RUSTDESK_BACKUP_DIR/engine-platform.tsv.partial"
test "$(wc -l < "$RUSTDESK_BACKUP_DIR/engine-platform.tsv.partial")" -eq 1
case "$(<"$RUSTDESK_BACKUP_DIR/engine-platform.tsv.partial")" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
mv "$RUSTDESK_BACKUP_DIR/engine-platform.tsv.partial" \
  "$RUSTDESK_BACKUP_DIR/engine-platform.tsv"
image_refs_output="$(printf '%s\n' "${image_refs[@]}" | LC_ALL=C sort -u)"
mapfile -t image_refs <<< "$image_refs_output"
docker image save --output "$RUSTDESK_BACKUP_DIR/images.tar.partial" \
  "${image_refs[@]}"
while IFS=$'\t' read -r service image_ref image_id; do
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  test "$(docker inspect -f '{{.Image}}' \
    "${service_containers[$service]}")" = "$image_id"
done < "$RUSTDESK_BACKUP_DIR/image-map.tsv.partial"

"${compose[@]}" down
test "$(realpath -e -- appdata/data)" = "$RUSTDESK_DATA_SOURCE"
test "$(stat -Lc '%d:%i' -- appdata/data)" = "$RUSTDESK_DATA_ID"
findmnt --json --output TARGET > "$RUSTDESK_BACKUP_DIR/host-mounts.json"
python3 - "$RUSTDESK_BACKUP_DIR/host-mounts.json" \
  "$RUSTDESK_DATA_SOURCE" <<'PY'
import json
import os
import sys

document = json.load(open(sys.argv[1], encoding='utf-8'))
source = sys.argv[2]
stack = list(document.get('filesystems', []))
while stack:
    node = stack.pop()
    stack.extend(node.get('children', []))
    target = node.get('target')
    if not target or not os.path.isabs(target):
        continue
    target = os.path.realpath(target)
    if target != source and os.path.commonpath((source, target)) == source:
        raise SystemExit(f'nested mount below RustDesk data path: {target!r}')
PY
tar --acls --xattrs --numeric-owner -czpf \
  "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz.partial" \
  appdata/data app.env .env docker-compose.main.yaml docker-compose.app.yaml \
  dockerfiles
python3 - "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz.partial" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'appdata', 'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'dockerfiles',
}
required = {
    'appdata', 'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'dockerfiles',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe archive path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate archive member: {member.name!r}')
        seen.add(normalized)
        root = path.parts[0]
        if root not in allowed:
            raise SystemExit(f'unexpected archive root: {member.name!r}')
        if root == 'appdata' and path.parts != ('appdata',) \
                and path.parts[:2] != ('appdata', 'data'):
            raise SystemExit(f'unexpected appdata member: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe archive member type: {member.name!r}')
        found.add(root)
if found != required:
    raise SystemExit(f'incomplete archive roots: {sorted(required - found)}')
PY
sync "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz.partial" \
  "$RUSTDESK_BACKUP_DIR/images.tar.partial"
mv "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz.partial" \
  "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz"
mv "$RUSTDESK_BACKUP_DIR/images.tar.partial" \
  "$RUSTDESK_BACKUP_DIR/images.tar"
mv "$RUSTDESK_BACKUP_DIR/image-map.tsv.partial" \
  "$RUSTDESK_BACKUP_DIR/image-map.tsv"
sha256sum appdata/data/id_ed25519.pub \
  > "$RUSTDESK_BACKUP_DIR/public-key.sha256"
(cd "$RUSTDESK_BACKUP_DIR" && sha256sum \
  rustdesk-files.tar.gz images.tar image-map.tsv rendered-compose.yaml \
  rendered-compose.json project-root.txt rustdesk-data.tsv host-mounts.json \
  network-evidence.tsv engine-platform.tsv \
  source-evidence.txt templates.lock public-key.sha256 \
  > recovery-manifest.sha256.partial)
if [[ -f "$RUSTDESK_BACKUP_DIR/source.lock" ]]; then
  (cd "$RUSTDESK_BACKUP_DIR" && sha256sum source.lock \
    >> recovery-manifest.sha256.partial)
fi
mv "$RUSTDESK_BACKUP_DIR/recovery-manifest.sha256.partial" \
  "$RUSTDESK_BACKUP_DIR/recovery-manifest.sha256"
python3 - "$RUSTDESK_BACKUP_DIR" "$RUSTDESK_BACKUP_ROOT" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False, followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular recovery artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
descriptor = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
(cd "$RUSTDESK_BACKUP_DIR" && sha256sum recovery-manifest.sha256 \
  > recovery-point.complete.partial)
mv "$RUSTDESK_BACKUP_DIR/recovery-point.complete.partial" \
  "$RUSTDESK_BACKUP_DIR/recovery-point.complete"
python3 - "$RUSTDESK_BACKUP_DIR/recovery-point.complete" \
  "$RUSTDESK_BACKUP_DIR" "$RUSTDESK_BACKUP_ROOT" <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
# Copy the complete directory off-host, verify it there, then restart:
"${compose[@]}" up -d \
  --no-build --pull never --wait --wait-timeout 300
```

The sæved imæge ærchive, not `docker compose images`, is the recoveræble
imæge evidence. If `.source.lock` is æbsent, the explicitly recorded
`deployment-inputs-only` mode is vælid only becæuse the complete merged inputs
ære ærchived; it is not æ source-repository clæim. The recovery-only
`rustdesk-proxy` override preserves the checksummed subnet but uses æ new
no-clobber næme, then proves thæt only this restored Compose project's exæct
service closure is ættæched.
The OCI ærchive is plætform-specific; `engine-platform.tsv` requires the sæme
Linux Docker-server ærchitecture before æny imæge is loæded.

This runbook supports only æ **fresh isolæted recovery host**. The recorded
project pæth must be æbsent ænd the selected Docker context must contæin no
contæiner, imæge, or volume. Consequently `docker image load` cænnot retæg æn
æctive imæge, ænd no live RustDesk tree is ever exchænged. If æ commænd,
signæl, `SIGKILL`, or host loss leæves the restore journæl, discærd the
isolæted host ænd retry from the completion-verified recovery directory on æ
new empty host. This document intentionælly mækes no in-plæce or power-loss
rollbæck clæim. Network creætion intentionælly precedes the Compose `ERR`
træp: æ pærtiæl recovery-network set is not reconciled ænd requires immediæte
host discærd.

```bash
set -euo pipefail
umask 077
RUSTDESK_BACKUP_DIR=/srv/backups/rustdesk/YYYYMMDDTHHMMSSZ
RUSTDESK_BACKUP_DIR="$(realpath -e -- "$RUSTDESK_BACKUP_DIR")"
test -d "$RUSTDESK_BACKUP_DIR" && test ! -L "$RUSTDESK_BACKUP_DIR"
test "$(stat -Lc %u -- "$RUSTDESK_BACKUP_DIR")" = "$(id -u)"
test "$(stat -Lc %a -- "$RUSTDESK_BACKUP_DIR")" = 700
exec {recovery_lock_fd}<"$RUSTDESK_BACKUP_DIR"
flock -n -s "$recovery_lock_fd"
test -f "$RUSTDESK_BACKUP_DIR/recovery-point.complete"
(cd "$RUSTDESK_BACKUP_DIR" && sha256sum -c recovery-point.complete)
(cd "$RUSTDESK_BACKUP_DIR" && sha256sum -c recovery-manifest.sha256)
saved_engine_platform="$(<"$RUSTDESK_BACKUP_DIR/engine-platform.tsv")"
case "$saved_engine_platform" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
test "$(docker version --format '{{.Server.Os}}\t{{.Server.Arch}}')" = \
  "$saved_engine_platform"
source_mode="$(<"$RUSTDESK_BACKUP_DIR/source-evidence.txt")"
case "$source_mode" in
  mode=source-lock)
    test -f "$RUSTDESK_BACKUP_DIR/source.lock" \
      && test ! -L "$RUSTDESK_BACKUP_DIR/source.lock"
    test "$(grep -Fxc '  source.lock' \
      "$RUSTDESK_BACKUP_DIR/recovery-manifest.sha256")" -eq 1
    ;;
  mode=deployment-inputs-only)
    test ! -e "$RUSTDESK_BACKUP_DIR/source.lock" \
      && test ! -L "$RUSTDESK_BACKUP_DIR/source.lock"
    test "$(grep -Fc '  source.lock' \
      "$RUSTDESK_BACKUP_DIR/recovery-manifest.sha256")" -eq 0
    ;;
  *) exit 1 ;;
esac
python3 - "$RUSTDESK_BACKUP_DIR/rendered-compose.json" \
  "$RUSTDESK_BACKUP_DIR/image-map.tsv" <<'PY'
import json
import re
import sys

services = set(json.load(open(sys.argv[1], encoding='utf-8'))['services'])
rows = [line.split('\t') for line in
        open(sys.argv[2], encoding='utf-8').read().splitlines()]
if len(rows) != len(services) or any(len(row) != 3 for row in rows):
    raise SystemExit('image map is not an exact service closure')
mapped = [row[0] for row in rows]
if set(mapped) != services or len(set(mapped)) != len(mapped):
    raise SystemExit('image map services are missing, extra, or duplicated')
references = {}
for service, reference, image_id in rows:
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', service):
        raise SystemExit(f'unsafe service in image map: {service!r}')
    if not reference or any(char.isspace() or ord(char) < 32 for char in reference):
        raise SystemExit(f'unsafe reference in image map: {reference!r}')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image_id):
        raise SystemExit(f'invalid image ID for {service!r}')
    previous = references.setdefault(reference, image_id)
    if previous != image_id:
        raise SystemExit(f'one image reference maps to multiple IDs: {reference!r}')
PY
python3 - "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'appdata', 'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'dockerfiles',
}
required = {
    'appdata', 'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'dockerfiles',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe archive path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate archive member: {member.name!r}')
        seen.add(normalized)
        root = path.parts[0]
        if root not in allowed:
            raise SystemExit(f'unexpected archive root: {member.name!r}')
        if root == 'appdata' and path.parts != ('appdata',) \
                and path.parts[:2] != ('appdata', 'data'):
            raise SystemExit(f'unexpected appdata member: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe archive member type: {member.name!r}')
        found.add(root)
if found != required:
    raise SystemExit(f'incomplete archive roots: {sorted(required - found)}')
PY

container_inventory="$(docker ps -aq)"
image_inventory="$(docker image ls -aq)"
volume_inventory="$(docker volume ls -q)"
test -z "$container_inventory"
test -z "$image_inventory"
test -z "$volume_inventory"
RUSTDESK_PROJECT_ROOT="$(<"$RUSTDESK_BACKUP_DIR/project-root.txt")"
test -n "$RUSTDESK_PROJECT_ROOT" && test "${RUSTDESK_PROJECT_ROOT#/}" != \
  "$RUSTDESK_PROJECT_ROOT"
test "$(realpath -m -- "$RUSTDESK_PROJECT_ROOT")" = \
  "$RUSTDESK_PROJECT_ROOT"
case "$RUSTDESK_BACKUP_DIR/" in "$RUSTDESK_PROJECT_ROOT/"* ) exit 1 ;; esac
case "$RUSTDESK_PROJECT_ROOT/" in "$RUSTDESK_BACKUP_DIR/"* ) exit 1 ;; esac
IFS=$'\t' read -r RUSTDESK_RECORDED_DATA_SOURCE RUSTDESK_RECORDED_DATA_ID \
  < "$RUSTDESK_BACKUP_DIR/rustdesk-data.tsv"
test "$RUSTDESK_RECORDED_DATA_SOURCE" = \
  "$RUSTDESK_PROJECT_ROOT/appdata/data"
[[ "$RUSTDESK_RECORDED_DATA_ID" =~ ^[0-9]+:[0-9]+$ ]]
test ! -e "$RUSTDESK_PROJECT_ROOT" && test ! -L "$RUSTDESK_PROJECT_ROOT"
RUSTDESK_PROJECT_PARENT="$(dirname -- "$RUSTDESK_PROJECT_ROOT")"
test -d "$RUSTDESK_PROJECT_PARENT" && test ! -L "$RUSTDESK_PROJECT_PARENT"
test "$(realpath -e -- "$RUSTDESK_PROJECT_PARENT")" = \
  "$RUSTDESK_PROJECT_PARENT"
mkdir -m 0700 "$RUSTDESK_PROJECT_ROOT"
tar --acls --xattrs --numeric-owner -xzpf \
  "$RUSTDESK_BACKUP_DIR/rustdesk-files.tar.gz" -C "$RUSTDESK_PROJECT_ROOT"
cd "$RUSTDESK_PROJECT_ROOT"
mkdir -m 0700 .run.conf
install -m 0600 "$RUSTDESK_BACKUP_DIR/templates.lock" \
  .run.conf/.templates.lock
if [[ -f "$RUSTDESK_BACKUP_DIR/source.lock" ]]; then
  install -m 0600 "$RUSTDESK_BACKUP_DIR/source.lock" .run.conf/.source.lock
fi

RUSTDESK_PROJECT_ID="$(stat -Lc '%d:%i' -- "$RUSTDESK_PROJECT_ROOT")"
exec {project_root_fd}<"$RUSTDESK_PROJECT_ROOT"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$RUSTDESK_PROJECT_ROOT"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$RUSTDESK_PROJECT_ID"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$RUSTDESK_PROJECT_ROOT")" = \
  "$RUSTDESK_PROJECT_ID"
RUSTDESK_RUN_CONF_ID="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$RUSTDESK_RUN_CONF_ID"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$RUSTDESK_RUN_CONF_ID"

RUSTDESK_RENDERED_YAML="$(mktemp .run.conf/rustdesk-rendered.XXXXXX.yaml)"
RUSTDESK_RENDERED_JSON="$(mktemp .run.conf/rustdesk-rendered.XXXXXX.json)"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config > "$RUSTDESK_RENDERED_YAML"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json > "$RUSTDESK_RENDERED_JSON"
cmp -- "$RUSTDESK_BACKUP_DIR/rendered-compose.yaml" "$RUSTDESK_RENDERED_YAML"
cmp -- "$RUSTDESK_BACKUP_DIR/rendered-compose.json" "$RUSTDESK_RENDERED_JSON"
rendered_project_name="$(python3 - "$RUSTDESK_RENDERED_JSON" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
runtime_compose=(docker compose --project-directory "$RUSTDESK_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$RUSTDESK_PROJECT_ROOT/.env" \
  -f "$RUSTDESK_PROJECT_ROOT/docker-compose.main.yaml")
runtime_yaml="$(mktemp .run.conf/rustdesk-runtime.XXXXXX.yaml)"
runtime_json="$(mktemp .run.conf/rustdesk-runtime.XXXXXX.json)"
"${runtime_compose[@]}" config > "$runtime_yaml"
"${runtime_compose[@]}" config --format json > "$runtime_json"
cmp -- "$RUSTDESK_RENDERED_YAML" "$runtime_yaml"
cmp -- "$RUSTDESK_RENDERED_JSON" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"
test -f appdata/data/id_ed25519 && test ! -L appdata/data/id_ed25519
test -f appdata/data/id_ed25519.pub && test ! -L appdata/data/id_ed25519.pub
test "$(stat -Lc %h -- appdata/data/id_ed25519)" -eq 1
test "$(stat -Lc %h -- appdata/data/id_ed25519.pub)" -eq 1
python3 - "$RUSTDESK_PROJECT_ROOT" "$RUSTDESK_PROJECT_PARENT" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False,
                                        followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular staged artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
for path in sys.argv[2:]:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY

RUSTDESK_RESTORE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUSTDESK_RESTORE_JOURNAL=".run.conf/rustdesk-fresh-restore.${RUSTDESK_RESTORE_STAMP}.journal"
test ! -e "$RUSTDESK_RESTORE_JOURNAL" && test ! -L "$RUSTDESK_RESTORE_JOURNAL"
printf '%s\n' 'version=1' 'state=deployment-staged' \
  > "$RUSTDESK_RESTORE_JOURNAL"
fsync_rustdesk_metadata() {
  python3 - "$@" .run.conf <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
}
fsync_rustdesk_metadata "$RUSTDESK_RESTORE_JOURNAL"

RUSTDESK_IMAGE_OVERRIDE=".run.conf/recovery-images.${RUSTDESK_RESTORE_STAMP}.yaml"
printf '%s\n' 'services:' > "$RUSTDESK_IMAGE_OVERRIDE"
while IFS=$'\t' read -r service image_ref image_id; do
  recovery_ref="localhost/rustdesk-recovery-${RUSTDESK_RESTORE_STAMP}-${service}:locked"
  printf '  %s:\n    image: %s\n    pull_policy: never\n    build: null\n' \
    "$service" "$recovery_ref" >> "$RUSTDESK_IMAGE_OVERRIDE"
done < "$RUSTDESK_BACKUP_DIR/image-map.tsv"
RUSTDESK_NETWORK_OVERRIDE=\
".run.conf/recovery-networks.${RUSTDESK_RESTORE_STAMP}.json"
RUSTDESK_NETWORK_INVENTORY=\
".run.conf/recovery-networks.${RUSTDESK_RESTORE_STAMP}.tsv"
python3 - "$RUSTDESK_BACKUP_DIR/network-evidence.tsv" rustdesk \
  "$RUSTDESK_RESTORE_STAMP" "$RUSTDESK_NETWORK_OVERRIDE" \
  "$RUSTDESK_NETWORK_INVENTORY" rustdesk-proxy <<'PY'
import ipaddress
import json
import os
import re
import subprocess
import sys

evidence, app, stamp, override, inventory, *expected = sys.argv[1:]
rows = [line.split('\t') for line in
        open(evidence, encoding='utf-8').read().splitlines()]
if len(rows) != len(expected) or any(len(row) != 5 for row in rows):
    raise SystemExit('external-network evidence closure differs')
if [row[0] for row in rows] != expected or len(set(expected)) != len(expected):
    raise SystemExit('external-network keys differ')
owner = f'{app}-{stamp}'
for path in (override, inventory):
    if os.path.lexists(path):
        raise SystemExit(f'recovery network artifact already exists: {path!r}')
definitions = {}
created = []
for key, source_name, driver, subnet_text, gateway_text in rows:
    if source_name != key or driver != 'bridge' \
            or not re.fullmatch(r'[a-z0-9][a-z0-9_.-]*', key):
        raise SystemExit(f'unsupported external-network evidence: {key!r}')
    subnet = ipaddress.ip_network(subnet_text, strict=True)
    gateway = ipaddress.ip_address(gateway_text)
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'invalid external-network IPAM: {key!r}')
    name = f'{app}-recovery-{stamp}-{key}'
    if subprocess.run(['docker', 'network', 'inspect', name],
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode == 0:
        raise SystemExit(f'recovery network already exists: {name!r}')
    network_id = subprocess.check_output([
        'docker', 'network', 'create', '--driver', 'bridge',
        '--subnet', str(subnet), '--gateway', str(gateway),
        '--label', f'io.it-saervices.recovery-owner={owner}', name,
    ], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{64}', network_id):
        raise SystemExit(f'invalid created network ID: {network_id!r}')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1:
        raise SystemExit('created network identity is ambiguous')
    item = result[0]
    config = item.get('IPAM', {}).get('Config', [])
    if item.get('Id') != network_id or item.get('Name') != name \
            or item.get('Driver') != 'bridge' or item.get('Scope') != 'local' \
            or any(item.get(field) for field in
                   ('Internal', 'Attachable', 'Ingress', 'ConfigOnly',
                    'EnableIPv6')) \
            or item.get('Options') not in ({}, None) or len(config) != 1 \
            or config[0].get('Subnet') != str(subnet) \
            or config[0].get('Gateway') != str(gateway) \
            or item.get('Labels') != {
                'io.it-saervices.recovery-owner': owner}:
        raise SystemExit(f'created network differs from evidence: {name!r}')
    definitions[key] = {'name': name, 'external': True}
    created.append((key, name, network_id, str(subnet), str(gateway)))
for path, payload in (
    (override, json.dumps({'networks': definitions}, sort_keys=True) + '\n'),
    (inventory, ''.join('\t'.join(row) + '\n' for row in created)),
):
    temporary = path + '.partial'
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, payload.encode())
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.rename(temporary, path)
    directory = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
PY
RECOVERY_COMPOSE=("${runtime_compose[@]}" -f "$RUSTDESK_IMAGE_OVERRIDE" \
  -f "$RUSTDESK_NETWORK_OVERRIDE")
"${RECOVERY_COMPOSE[@]}" config --quiet
keep_isolated_stopped() {
  trap - ERR INT TERM
  set +e
  "${RECOVERY_COMPOSE[@]}" down
  exit 1
}
trap keep_isolated_stopped ERR INT TERM
printf '%s\n' 'state=image-load-starting' >> "$RUSTDESK_RESTORE_JOURNAL"
fsync_rustdesk_metadata "$RUSTDESK_RESTORE_JOURNAL" \
  "$RUSTDESK_IMAGE_OVERRIDE" "$RUSTDESK_NETWORK_OVERRIDE" \
  "$RUSTDESK_NETWORK_INVENTORY"
docker image load --input "$RUSTDESK_BACKUP_DIR/images.tar"
while IFS=$'\t' read -r service image_ref image_id; do
  recovery_ref="localhost/rustdesk-recovery-${RUSTDESK_RESTORE_STAMP}-${service}:locked"
  docker image tag "$image_id" "$recovery_ref"
  test "$(docker image inspect -f '{{.Id}}' "$recovery_ref")" = "$image_id"
done < "$RUSTDESK_BACKUP_DIR/image-map.tsv"
printf '%s\n' 'state=images-aliased' >> "$RUSTDESK_RESTORE_JOURNAL"
fsync_rustdesk_metadata "$RUSTDESK_RESTORE_JOURNAL"
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 180
python3 - "$RUSTDESK_NETWORK_INVENTORY" "$RUSTDESK_RENDERED_JSON" \
  "$rendered_project_name" <<'PY'
import json
import subprocess
import sys

inventory, compose_path, project = sys.argv[1:]
compose = json.load(open(compose_path, encoding='utf-8'))
for row in open(inventory, encoding='utf-8'):
    key, name, network_id, subnet, gateway = row.rstrip('\n').split('\t')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1 or result[0].get('Name') != name:
        raise SystemExit(f'recovery network identity drift: {name!r}')
    expected = {service for service, definition in compose['services'].items()
                if key in definition.get('networks', {})}
    actual = set()
    containers = result[0].get('Containers') or {}
    for container_id in containers:
        detail = json.loads(subprocess.check_output(
            ['docker', 'inspect', container_id], text=True))
        if len(detail) != 1:
            raise SystemExit('recovery network member identity is ambiguous')
        labels = detail[0].get('Config', {}).get('Labels', {})
        if labels.get('com.docker.compose.project') != project:
            raise SystemExit(f'foreign recovery network member: {container_id!r}')
        service = labels.get('com.docker.compose.service', '')
        if not service or service in actual:
            raise SystemExit(f'duplicate recovery network service: {service!r}')
        actual.add(service)
    if actual != expected:
        raise SystemExit(
            f'recovery network member closure differs for {key!r}: '
            f'{sorted(actual ^ expected)}')
PY
"${RECOVERY_COMPOSE[@]}" ps app rustdesk-relay
sha256sum -c "$RUSTDESK_BACKUP_DIR/public-key.sha256"
printf '%s\n' 'state=complete' >> "$RUSTDESK_RESTORE_JOURNAL"
fsync_rustdesk_metadata "$RUSTDESK_RESTORE_JOURNAL"
RUSTDESK_RESTORE_COMPLETE="${RUSTDESK_RESTORE_JOURNAL%.journal}.complete"
RUSTDESK_RESTORE_ID="$(stat -Lc '%d:%i' -- "$RUSTDESK_RESTORE_JOURNAL")"
python3 - "$RUSTDESK_RESTORE_JOURNAL" "$RUSTDESK_RESTORE_COMPLETE" <<'PY'
import os
import sys

os.rename(sys.argv[1], sys.argv[2])
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
test ! -e "$RUSTDESK_RESTORE_JOURNAL" && test ! -L "$RUSTDESK_RESTORE_JOURNAL"
test "$(stat -Lc '%d:%i' -- "$RUSTDESK_RESTORE_COMPLETE")" = \
  "$RUSTDESK_RESTORE_ID"
trap - ERR INT TERM
```

The empty-Docker-context preflight is the tæg-mutætion boundæry: there is no
prior tæg or running old dætæ tree to preserve. Shæred references in
`image-map.tsv` must resolve to one ID, while the override still gives eæch
service its own recovery æliæs. The cleæn render must mætch both sæved Compose
representætions before imæges loæd. Ælso prove both nætive heælth probes,
edition/license, direct ænd relæyed reæl-client connections, WSS,
OIDC/break-glass, ænd SMTP before cutover. Never run `run.sh --force`,
`build --pull`, or ænother moving resolution in this recovery pæth.

## Security Highlights

- `hbbs` ænd `hbbr` run non-root; the shellless preflight rejects imæge or UID/GID drift before direct exec.
- Root filesystems ære reæd-only with bounded writæble tmpfs mounts.
- Linux cæpæbilities ære dropped with `cap_drop: ALL`; no cæpæbilities ære ædded bæck.
- Privilege escælætion is blocked with `no-new-privileges:true`.
- Only nætive ports `21115-21117` ære host-published; `21118-21119` exist only on `rustdesk-proxy`, ænd Pro `21114` is host-loopbæck-only.
- The stæble hbbs MÆC follows RustDesk's documented bridge-network Pro licensing requirement.
- Bridge networking is the deliberæte isolætion træde-off: depending on the Docker host pæth, RustDesk mæy observe æ NÆT/gætewæy source for nætive clients. Enforce nætive-port exposure in the host firewæll insteæd of relying on dæmon-side source-IP policy.
- The wræpper generætes or vælidætes the Ed25519 key pæir no-follow, requires æ mætching bounded bæse64 pæir, ænd enforces privæte mode `0600` before direct exec.
- JSON Docker logging is rotæted æt `10 MB x3`.
- No plæintext credentiæls ære pæssed by environment væriæbles.

## Heælthcheck

The stætic no-module helper verifies the expected dæmon process, the mætching key pæir ænd privæte-key mode, every required TCP listener, ænd `21116/UDP`. The Pro imæge is detected through its nætive `rustdesk-utils` binæry so hbbs heælth ælso requires `21114/TCP`.

```yaml
test: ['CMD', '/usr/local/bin/rustdesk-runtime', 'health', 'hbbs']
interval: 30s
timeout: 5s
retries: 3
start_period: 15s
```

Run these commænds from the `RustDesk/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/rustdesk-runtime health hbbs
```

Complete merged-stæck probe inventory:

| Service | Æctive test | `interval` | `timeout` | `retries` | `start_period` |
| --- | --- | --- | --- | --- | --- |
| `app` | `/usr/local/bin/rustdesk-runtime health hbbs` | `30s` | `5s` | `3` | `15s` |
| `rustdesk-relay` | `/usr/local/bin/rustdesk-runtime health hbbr` | `30s` | `5s` | `3` | `10s` |

Run the relæy probe from the sæme `RustDesk/` directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T rustdesk-relay \
  /usr/local/bin/rustdesk-runtime health hbbr
```

## Verificætion

Run the repository checks ænd both `run.sh` invocætions from the repository
root:

```bash
./run.sh RustDesk --dry-run
./run.sh RustDesk
python3 .cursor/scripts/enforce-app-template-compliance.py --check RustDesk
python3 .cursor/scripts/enforce-branding.py --check RustDesk Traefik
python3 .cursor/scripts/check-hardening.py --quiet RustDesk
```

Run the remæining Compose commænds in this section from the `RustDesk/`
merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app rustdesk-relay
```

With both clients on current releæses ænd configured with the sæme ID
server, relæy server, ænd public key, complete one connection in eæch
direction. Prove one direct pæth ænd one forced-relæy pæth; if either
client reports `Key Error`, key mismætch, or æn E2EE trust wærning, the DEV
gæte fæils. Record both client versions, both server versions, ænd the
public-key checksum with the test evidence.

From æny directory on the Docker host, check the listeners. `21114` must be
loopbæck-only, `21115-21117` must use the configured nætive bind æddress,
ænd `21118-21119` must be æbsent:

```bash
ss -ltnup '( sport = :21114 or sport = :21115 or sport = :21116 or sport = :21117 or sport = :21118 or sport = :21119 )'
```

## References

- RustDesk self-host documentætion: https://rustdesk.com/docs/en/self-host/
- RustDesk Server OSS Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/
- RustDesk Server OSS `1.1.16` releæse: https://github.com/rustdesk/rustdesk-server/releases/tag/1.1.16
- RustDesk client/server `Key Error` report: https://github.com/rustdesk/rustdesk/issues/15737
- RustDesk Server Pro Docker documentætion: https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/docker/
- RustDesk pricing ænd feæture tiers: https://rustdesk.com/pricing/
- Æuthentik OAuth2/OIDC provider documentætion: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/
