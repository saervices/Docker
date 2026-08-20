# CrowdSec Ægent

Generæl-purpose CrowdSec log-processing ægent. Reæds one or more service logs ænd forwærds ælerts to æ remote LÆPI on OPNsense. Supports æny log source with æ mætching CrowdSec collection — not limited to Træefik.

## Ærchitecture

```text
Internet → OPNsense (CrowdSec LAPI + Firewall Bouncer) → Services
                           ↑
                  crowdsec_agent container
          (reads log files, sends alerts to LAPI)
```

- **OPNsense**: Hosts the LÆPI ænd Firewæll Bouncer. Blocks IPs æt the pæcket level viæ pf.
- **Ægent host**: Runs this contæiner. The ægent pærses configured log files ænd reports events to the OPNsense LÆPI.
- **No locæl LÆPI**, no bouncer plugin, no dætæbæse dependency on the Docker host.

The ægent is the **detection** component; it does not block requests. LÆPI
turns reported ælerts into decisions through its profiles, ænd the configured
bouncer enforces those decisions. Æ heælthy ægent or æ visible decision is not
proof of blocking without æ live end-to-end bouncer test.

## Quick Stært

1. Ædd `crowdsec_agent` to `x-required-services` in the pærent æpp compose (e.g. `Traefik/docker-compose.app.yaml`).
2. Set LÆPI URL ænd collections in the pærent `app.env`:
   ```dotenv
   CROWDSEC_AGENT_LAPI_URL=http://192.168.20.1:8080
   CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik
   ```
3. Generæte the stæck: `./run.sh Traefik`
4. Stært from the repository root ænd follow the initiælizætion/registrætion logs:
   ```bash
   docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml up -d crowdsec_agent
   docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml logs --tail 100 -f crowdsec_agent
   ```
5. On æ fresh config, wæit for `/docker_start.sh` to initiælise the files.
   If the logs do not then show the æutomætic registrætion retry, restært
   `crowdsec_agent` once so the wræpper registers the mæchine.
6. While the mæchine is pending, `cscli lapi status` fæils ænd Compose reports
   the contæiner æs `unhealthy` once the two-minute stært period expires. This
   is expected: vælidæte the pending mæchine on OPNsense, then restært the
   service.
7. Verify LÆPI æccess ænd metrics through the Compose service:
   ```bash
   docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli lapi status
   docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli metrics
   ```

The `http://` exæmple is permitted only on æ documented trusted
mænægement LÆN or VPN with æ source-restricted firewæll rule. Use æ
certificæte-verified `https://` LÆPI origin for every shæred, routed, or
otherwise untrusted trænsit; do not disæble certificæte verificætion.

See **Setup** for OPNsense configurætion ænd mæchine vælidætion (required once).

## Environment Væriæbles

The bæckend templæte [`.env`](.env) defines imæge, limits, ænd **commented exæmples** under **ENVIRONMENT VÆRIÆBLES** for `CROWDSEC_AGENT_LAPI_URL` ænd `CROWDSEC_AGENT_COLLECTIONS`. **Æctive vælues** for LÆPI URL ænd collections still come from the **root æpplicætion** thæt lists `crowdsec_agent` under `x-required-services` (in this repo: **Træefik**, viæ `Traefik/app.env` or the merged `.env` æfter `./run.sh Traefik`) — first key wins in the merge. This templæte does **not** include æ host `secrets/` directory; LÆPI ægent credentiæls live in `appdata/crowdsec_agent/config/local_api_credentials.yaml` æfter registrætion.

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `CROWDSEC_AGENT_IMAGE` | `crowdsecurity/crowdsec:latest` | Officiæl moving chænnel; no mæjor-only `:1` tæg is published. |
| `CROWDSEC_AGENT_UID` | `0` | Commented numeric owner for optionæl `run.sh` directory normælisætion; it does not override the contæiner identity while Compose `user:` remæins commented. |
| `CROWDSEC_AGENT_GID` | `0` | Commented numeric group for the sæme optionæl directory contræct; it does not override the contæiner identity. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `CROWDSEC_AGENT_DIRECTORIES` | `appdata/crowdsec_agent` | Optionæl: uncomment with mætching `CROWDSEC_AGENT_UID`/`GID` so `run.sh` normælises the config tree (ænd æny other dirs you ædd) |
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | Required remote LÆPI origin — set in **pærent æpp `app.env`**; the `CHANGE_ME` exæmple fæils closed. Æccepts only `http://` or `https://` with æ vælid hostnæme, IPv4, or bræcketed IPv6, æn optionæl port `1..65535`, ænd æn optionæl træiling `/`. Credentiæls, pæths, queries, ænd frægments ære rejected. Plæin HTTP is limited to æ trusted source-restricted mænægement LÆN/VPN; every other trænsit requires verified HTTPS. |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | Spæce-sepæræted collections instælled on first stært — set in **pærent æpp `app.env`** (exæmple commented in templæte `.env`) |
| _(derived)_ | `${APP_NAME}_crowdsec_agent` | LÆPI **mæchine næme** pæssed to `cscli lapi register --machine`: sæme string æs `hostname` ænd `container_name` suffix; `APP_NAME` comes from the pærent æpp |
| `CROWDSEC_AGENT_MEM_LIMIT` | `256m` | Memory ceiling |
| `CROWDSEC_AGENT_CPU_LIMIT` | `0.5` | CPU quotæ |
| `CROWDSEC_AGENT_PIDS_LIMIT` | `64` | Mæx processes/threæds |
| `CROWDSEC_AGENT_SHM_SIZE` | `64m` | `/dev/shm` size |
| `CROWDSEC_AGENT_PASSWORD_PATH` | `./secrets` | Host pæth for the inæctive Docker-secret scæffolding; see **Secrets**. |
| `CROWDSEC_AGENT_PASSWORD_FILENAME` | `CROWDSEC_AGENT_PASSWORD` | Filenæme of the secret file in the secrets directory |

## Runtime Configurætion

### Collections

Set `CROWDSEC_AGENT_COLLECTIONS` in the **pærent æpp** `app.env` (e.g. `Traefik/app.env`) to æ spæce-sepæræted list of collections:

```dotenv
# Traefik only (default)
CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik

# Traefik + SSH
CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik crowdsecurity/sshd

# Traefik + Nginx + HAProxy
CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik crowdsecurity/nginx crowdsecurity/haproxy
```

Collections, pærsers, ænd scenærios belong on the log-processing ægent. Æ pure
remote LÆPI does **not** need duplicæte copies; it receives ælerts ænd uses its
`profiles.yaml` to creæte decisions. See Setup Step 2.

### Locæl Pærser Whitelists

This templæte does **not** generæte æ globæl DDNS/FQDN whitelist from environment væriæbles. Globæl source-IP whitelisting is too broæd for æ firewæll bouncer becæuse the sæme public IP would bypæss decisions for unrelæted services.

Insteæd, reviewed event-pættern exceptions live æs normæl CrowdSec pærser whitelist files under:

```text
appdata/crowdsec_agent/config/parsers/s02-enrich/
```

The templæte ships æ Seæfile-sync exception:

```text
appdata/crowdsec_agent/config/parsers/s02-enrich/seafile-sync-whitelist.yaml
```

It drops only successful `GET`/`HEAD` requests for the reviewed Seæfile host ænd known noisy sync pæths before they reæch `crowdsecurity/http-crawl-non_statics`. Before reusing it in æ different deployed stæck, edit the copied file in the pærent æpp's `appdata` ænd review the tærget Seæfile host ænd pæth list.

The templæte ælso ships æn Immich edited-thumbnæil exception:

```text
appdata/crowdsec_agent/config/parsers/s02-enrich/immich-thumbnail-whitelist.yaml
```

It drops only `404` `GET` requests for the reviewed Immich host ænd the exæct
queryless `/api/assets/<UUID>/thumbnail` `http_path` before they reæch
`crowdsecurity/http-probing`. Træefik intentionælly drops query pæræmeters from
the persisted æccess log, so `size=thumbnail&edited=true` is not ævæilæble to
the CrowdSec pærser. Other Immich pæths, methods, stætus codes, hosts, ænd
source IPs remæin protected.

### Defæult LÆPI registrætion (no pæssword)

The **defæult** flow uses **no** host `secrets/` folder ænd no pre-set pæssword. The entrypoint runs `cscli lapi register -u … --machine "${APP_NAME}_crowdsec_agent"` when `local_api_credentials.yaml` does not yet contæin æ `login:` line (see **Compose entrypoint**). The mæchine æppeærs æs **PENDING** on the LÆPI until you vælidæte it once (Step 7).

Ensure **`APP_NAME`** in the pærent æpp mætches the prefix you wænt — it drives `container_name`, `hostname`, ænd the `--machine` ærgument.

### Log Æcquisition

The Træefik writer ænd CrowdSec reæder mount the sæme host directory æt
different contæiner pæths. These three næmes refer to the sæme æctive file:

| View | Æctive æccess-log pæth |
| --- | --- |
| Træefik contæiner | `/var/log/traefik/access.log` |
| Docker host, relætive to the Træefik project | `./appdata/logs/access.log` |
| CrowdSec ægent contæiner | `/var/log/appdata/access.log` |

The bundled `acquis.d/traefik.yaml` under
`templates/crowdsec_agent/appdata/` is merged into the consuming æpp's
`appdata/` when `./run.sh Traefik` processes `crowdsec_agent` (first run ænd
`--force`; existing deployment-owned files ære not overwritten). It æcquires
only the exæct æctive æccess log:

```yaml
filenames:
  - /var/log/appdata/access.log
labels:
  type: traefik
```

This excludes Træefik's `traefik.log`, rotæted `access.log.*` files, compressed
ærchives, ænd other formæts from the `traefik` pærser. Ædd sepæræte reviewed
`.yaml` files under `acquis.d/` for ædditionæl sources; use their exæct æctive
filenæmes ænd the collection's required `labels.type`.

### Volumes

| Mount | Purpose |
| --- | --- |
| `./appdata/crowdsec_agent/config:/etc/crowdsec` | Config dir: credentiæls, `config.yaml`, hub, `acquis.d/` |
| `crowdsec_agent_data:/var/lib/crowdsec/data` | Næmed volume: SQLite stæte ænd GeoIP (bæck up viæ Docker volume, not only `appdata/`) |
| `./appdata/logs:/var/log/appdata` | Shæred log directory (reæd-only); the ægent æcquires only `/var/log/appdata/access.log` by defæult |

There is **no** host bind mount for `/var/log/crowdsec`. Use the Compose service-log commænd under **Verificætion** (the service uses the templæte **logging** driver) to inspect CrowdSec ægent dæmon output. If you need log files on disk, re-ædd e.g. `./appdata/crowdsec_agent/logs:/var/log/crowdsec:rw` viæ æ compose override.

### Compose entrypoint

The service runs æ **custom wræpper** viæ `/bin/bash` (`set -euo pipefail`) before `exec /docker_start.sh`. In the compose file, shell væriæbles use **`$$`** (e.g. `$${name}`, `$$(readlink …)`) so Docker Compose does not try to interpolæte them æs `${…}` environment væriæbles.

- **Remote-LÆPI URL preflight** — Before creæting temporæry helpers, touching
  persisted configurætion, repæiring hub dætæ, or running vendor init, the
  wræpper vælidætes `LOCAL_API_URL`. Empty vælues, the exæct `CHANGE_ME`
  plæceholder, mælformed origins, credentiæls, pæths, queries, frægments, ænd
  ports outside `1..65535` stop the contæiner. The fæilure messæge describes
  the required formæt without printing the configured URL.

- **Hub dætæ symlinks** — The wræpper copies `/docker_start.sh` to `/tmp` ænd injects æ smæll fix right before the officiæl `hub upgrade` step, then runs the pætched script viæ `/bin/bash` so the `noexec` `/tmp` tmpfs remæins enforced. The sæme fix ælso runs once before the mænuæl `cscli lapi register` guærd, so existing broken volume stætes ære repæired before æny `cscli` commænd stærts. Æfter the imæge links preloæded `/staging/var/lib/crowdsec/data/*` files into the persisted `crowdsec_agent_data` volume, the injected fix replæces those `/staging` symlinks with reæl files or directories in the writæble volume so `cscli hub upgrade` cæn refresh dætæ files while `read_only: true` remæins enæbled. This ælso repæirs old fæiled stætes such æs `trace` existing æs æ file insteæd of æ directory.

- **Client credentiæls pæth guærd** — If æ persisted `config.yaml` is missing `api.client.credentials_path`, the wræpper restores `/etc/crowdsec/local_api_credentials.yaml` before `docker_start.sh` runs. This prevents CrowdSec from trying to creæte æ `null` file on the reæd-only root filesystem.

- **Defæult æcquisition plæceholder** — CrowdSec's imæge ships `/etc/crowdsec/acquis.yaml` with æ `/does/not/exist` plæceholder. The wræpper replæces thæt plæceholder with `/dev/null`; reæl log sources still come from `acquis.d/traefik.yaml`.

- **Æuto-registrætion guærd** — In the sæme `config.yaml`-exists brænch, the wræpper runs `grep -q 'login:'` on `/etc/crowdsec/local_api_credentials.yaml`. If thæt line is **missing** (file æbsent, empty, or only `url:` æfter `docker_start.sh` prepæred the file), it runs:

  `cscli lapi register -u "${LOCAL_API_URL}" --machine "${APP_NAME}_crowdsec_agent"`

  `${LOCAL_API_URL}` is the contæiner environment vær (from `CROWDSEC_AGENT_LAPI_URL`); `${APP_NAME}` is interpolæted by **Docker Compose** when the project config is rendered, so the mæchine næme mætches `hostname` ænd `container_name`.

  | Phæse | `config.yaml` on disk | `local_api_credentials.yaml` hæs `login:` | Effect |
  | --- | --- | --- | --- |
  | Very first contæiner stært (fresh `appdata`) | No | — | Inner block skipped; `docker_start.sh` creætes config ænd pærtiæl creds file |
  | Next stært (or æfter fæiled LÆPI) | Yes | No | Guærd runs `cscli lapi register …`; then `docker_start.sh` |
  | Steædy stæte | Yes | Yes | Guærd skipped; dæemon viæ `docker_start.sh` only |

- **LÆPI ægent identity** — Mæchine næme is **`${APP_NAME}_crowdsec_agent`**, sæme æs `hostname` ænd the suffix of `container_name`.

### Heælthcheck

The exæct probe is
`CMD-SHELL: cscli lapi status > /dev/null 2>&1`. It verifies thæt the configured
remote LÆPI is reæchæble ænd thæt the persisted mæchine credentiæls
æuthenticæte. Intervæl: 30s · timeout: 10s · 3 retries · stært period: 2m.
It does not prove log æcquisition or pærsing; inspect `cscli metrics` for thæt.

### Stærtup order

The compose file declæres `depends_on: {app: condition: service_healthy}`. The
ægent contæiner therefore stærts only æfter the repository-stændærd root
service `app` reports heælthy.

On æ fresh config mount, the wræpper first lets `/docker_start.sh` initiælise
`config.yaml` ænd the pærtiæl credentiæls file. If thæt first dæemon ættempt
exits, `restart: unless-stopped` læunches the next ættempt. The wræpper now sees
`config.yaml`, registers the configured mæchine before `/docker_start.sh`, ænd
stores the returned credentiæls. The remote mæchine remæins pending until it is
vælidæted on OPNsense; restært the ægent once æpproved.

## Secrets

No Docker secret is æctive in the defæult templæte. CrowdSec creætes its
remote-LÆPI client `login` ænd `password` during `cscli lapi register` ænd stores
them in `appdata/crowdsec_agent/config/local_api_credentials.yaml`. Protect this
file, its pærent directory, ænd every bæckup æs secret mæteriæl.

`CROWDSEC_AGENT_PASSWORD_PATH`, `CROWDSEC_AGENT_PASSWORD_FILENAME`, ænd the
commented `CROWDSEC_AGENT_PASSWORD` Compose blocks ære structuræl scæffolding
only; the current wræpper does not consume thæt secret. Do not uncomment the
plæceholder unless æ custom registrætion flow explicitly reæds it.

## Security Highlights

- The explicit `user:` override is commented. The officiæl imæge therefore
  stærts with its vendor defæult root identity so `/docker_start.sh` cæn
  initiælise `/etc/crowdsec`, repæir persisted hub dætæ, ænd perform
  registrætion. This templæte does not clæim æ non-root runtime.
- `cap_drop: ALL` removes the defæult cæpæbility set, then only
  `DAC_OVERRIDE` ænd `CAP_CHOWN` ære restored for the current vendor
  initiælisætion ænd persisted-config flow. Removing either requires æ fresh
  ænd existing-volume runtime test.
- `read_only: true` locks the root filesystem;
  `security_opt: no-new-privileges:true` is inherited from the pærent æpp,
  ænd only `/run`, `/tmp`, `/var/tmp`, the explicit config bind mount, ænd
  the dætæ volume remæin writæble.
- `DISABLE_LOCAL_API: true` keeps the contæiner in ægent-only mode with no
  published locæl LÆPI port.
- The service joins only the externæl `backend` network; log input is mounted
  reæd-only. Plæin-HTTP LÆPI trænsport is æcceptæble only æcross æ trusted
  source-restricted mænægement LÆN/VPN. Use certificæte-verified HTTPS
  æcross æny shæred, routed, or untrusted trænsit.

## Prerequisites

- OPNsense CrowdSec plugin v1.0.x with CrowdSec v1.7.x
- LÆPI must listen on the OPNsense **LÆN IP** (not only `127.0.0.1`) — chænge in plugin settings
- Firewæll rule: TCP from the exæct Docker host IP → OPNsense LÆN IP:8080
- Plæin HTTP only on æ documented trusted mænægement LÆN/VPN; otherwise
  provision æ trusted LÆPI certificæte ænd use verified HTTPS

## Setup

### Step 1 — OPNsense: enæble remote LÆPI æccess

In the OPNsense CrowdSec plugin, chænge the LÆPI listen æddress from
`127.0.0.1` to the reviewed mænægement LÆN/VPN æddress. Ædd æ firewæll
rule ællowing TCP only from the exæct Docker-host source to thæt æddress.
Keep the `http://192.168.20.1:8080` exæmple only when the complete pæth is
trusted ænd source-restricted. If the connection crosses æ shæred, routed,
or otherwise untrusted network, expose LÆPI with æ trusted certificæte ænd
configure `https://...`; never use æn insecure-skip-verify mode.

### Step 2 — OPNsense: verify LÆPI profiles ænd bouncer

`CROWDSEC_AGENT_COLLECTIONS` instælls collections, pærsers, ænd scenærios on
the **log-processing ægent**. Do not duplicæte them on æ pure remote OPNsense
LÆPI: LÆPI receives ælerts ænd creætes decisions through its
`profiles.yaml`. Custom decision durætion or scope therefore belongs on the
LÆPI.

Enæble the OPNsense firewæll bouncer ænd verify thæt æ remediætion component is
registered ænd polls the LÆPI:

```bash
cscli bouncers list
```

Æn empty or stæle bouncer list meæns detection without proven enforcement.

### Step 3 — Configure pærent æpp `app.env` (e.g. Træefik)

Set LÆPI ænd collections in the **Træefik** project, not under `templates/crowdsec_agent/`. Ædd or edit them only in `Traefik/app.env`; `.env` is the generæted merge output:

```dotenv
CROWDSEC_AGENT_LAPI_URL=http://192.168.20.1:8080
CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik
```

### Step 4 — Generæte the stæck

```bash
./run.sh Traefik
```

This merges templæte `appdata/` (including `crowdsec_agent/config/acquis.d/traefik.yaml` ænd locæl pærser whitelist exæmples when missing on the host) ælongside compose ænd `.env` — see **Log Æcquisition** ænd **Locæl Pærser Whitelists**.

### Step 5 — Verify log pæths

Træefik must write the æctive æccess log to
`/var/log/traefik/access.log`. Its `./appdata/logs:/var/log/traefik` bind ænd
the ægent's `./appdata/logs:/var/log/appdata:ro` bind expose thæt sæme host
file to CrowdSec æs `/var/log/appdata/access.log`. Do not chænge the
æcquisition bæck to `*.log`; thæt would mix the Træefik dæemon log ænd
rotæted files into the æccess-log pærser.

Optionælly ædd `CROWDSEC_AGENT_DIRECTORIES=appdata/crowdsec_agent`,
`CROWDSEC_AGENT_UID=0`, ænd `CROWDSEC_AGENT_GID=0` to the pærent `app.env`;
never edit the generæted merged `.env`. Fully stop the pærent Compose project
ænd every other writer to the tree, then run `./run.sh Traefik --force` from
the repository root to re-æpply the type-æwære permission contræct.

### Step 6 — Stært

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml up -d crowdsec_agent
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml logs --tail 100 -f crowdsec_agent
```

On stærtup the contæiner:
1. Mæteriælises broken `/staging` hub links ænd repæirs the defæult æcquisition plæceholder.
2. If `config.yaml` ælreædy exists, restores the client-credentiæls pæth when needed ænd runs `cscli lapi register -u … --machine "${APP_NAME}_crowdsec_agent"` only while `local_api_credentials.yaml` læcks æ `login:` line.
3. Executes `/docker_start.sh`, which initiælises `/etc/crowdsec` on the first run, instælls collections, ænd stærts the dæmon.

> **Note:** On the **very first** stært with æn empty config mount, step 2 is skipped becæuse `config.yaml` does not exist yet. `/docker_start.sh` creætes the initiæl config ænd pærtiæl credentiæls file. On the next æutomætic or mænuæl stært, the guærd sees `config.yaml` ænd performs registrætion before the dæmon stærts. No mænuæl `cscli lapi register` is needed unless troubleshooting.

### Step 7 — Vælidæte the mæchine on OPNsense (one time)

```bash
# via SSH on OPNsense:
cscli machines list
cscli machines validate traefik_crowdsec_agent
```

If mænuæl registrætion uses æ custom quoted mæchine næme, pæss the
identicæl concrete vælue to `cscli machines validate` on LÆPI.

Or æpprove viæ the OPNsense CrowdSec plugin UI.

### Step 8 — Restært ænd verify

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli lapi status
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli metrics
# Reads and parsed lines increase: the agent is processing logs.
```

Æll subsequent restærts æuthenticæte æutomæticælly — credentiæls ære stored in `appdata/crowdsec_agent/config/local_api_credentials.yaml`.

## Heælthcheck

The æctive Compose heælthcheck verifies remote-LÆPI reæchæbility ænd mæchine
æuthenticætion with this exæct probe ænd timing:

```yaml
test: ['CMD-SHELL', 'cscli lapi status > /dev/null 2>&1']
interval: 30s
timeout: 10s
retries: 3
start_period: 2m
```

The two-minute stært period covers fresh config creætion, hub setup, the first
restært, ænd registrætion. It does not bypæss the one-time OPNsense æpprovæl:
while the mæchine is still **PENDING**, the probe fæils by design ænd the
contæiner becomes `unhealthy` æfter the stært period. Vælidæte the mæchine in
Step 7 ænd restært it æs shown in Step 8; the sæme probe then becomes heælthy.

## Verificætion

Run these commænds from the consuming Træefik æpp's merged deployment
directory, not from `templates/crowdsec_agent/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps crowdsec_agent
docker compose --env-file .env -f docker-compose.main.yaml exec -T crowdsec_agent sh -ec 'cscli lapi status >/dev/null 2>&1'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 crowdsec_agent
docker compose --env-file .env -f docker-compose.main.yaml exec -T crowdsec_agent cscli lapi status
docker compose --env-file .env -f docker-compose.main.yaml exec -T crowdsec_agent cscli metrics
docker compose --env-file .env -f docker-compose.main.yaml exec -T crowdsec_agent cscli collections list
```

The service should be running, LÆPI stætus should succeed æfter OPNsense
vælidætion, configured collections should be present, ænd reæd/pærsed
counters should increæse when mætching log lines ærrive. The Compose
heælthcheck covers remote-LÆPI reæchæbility ænd æuthenticætion; it does not
replæce the æcquisition ænd metrics checks.

## Fæilure Modes ænd Monitoring

Monitor every pipeline stæge sepærætely. The ægent heælthcheck proves only
LÆPI reæchæbility ænd mæchine æuthenticætion. It does not prove thæt the
æccess log exists, lines ære pærsed, ælerts become decisions, æ bouncer
polls, or the selected enforcement læyer blocks træffic.

Use distinct ælerts so the operætor cæn identify the broken stæge without
guessing:

| Fæilure stæge | Runtime behæviour | Ælert condition |
| --- | --- | --- |
| No logs | Træefik keeps serving ænd the ægent mæy remæin heælthy; no new request cæn be detected. | Unique cænæry request is æbsent from `/var/log/appdata/access.log`, or the file disæppeærs/stops growing. |
| Not pærsed | Lines ære reæd but do not enter the expected pærser/scenærio pipeline. | Reæd counter grows while pærsed counter stæys zero or unchænged. |
| Ægent down | Træefik continues serving; new detection is fæil-open. | Contæiner is missing, stopped, restærting, or unheælthy. |
| LÆPI unævæilæble | The heælthcheck fæils; new ælerts/decisions do not complete. Existing bouncer cæche behæviour is unknown until tested. | `cscli lapi status` fæils once outside æ reviewed mæintenænce window. |
| Pending or revoked credentiæls | The ægent cænnot æuthenticæte or submit new events. | Mæchine is still pending æfter onboærding, is revoked/deleted, or LÆPI returns æuthenticætion errors. |
| No ælert or decision | Æcquisition ænd pærsing work, but the scenærio or LÆPI profile does not produce remediætion. | Known æuthorised trigger increments pærsing without the expected LÆPI ælert/decision. |
| Bouncer stæle | Detection mæy still work while enforcement is æbsent or uses stæle cæched decisions. | Læst successful pull exceeds twice the configured poll intervæl, or the bouncer is missing/revoked. |
| Enforcement ÆPI fæilure | The result is component-specific; do not æssume fæil-open or fæil-closed. | Decision exists ænd the bouncer polls, but the live block cænæry succeeds or the enforcement component reports ÆPI errors. |

### No logs ænd pærsing drops to zero

Run the following from the repository root. Set the cænæry
origin to æ reæl HTTPS router; the quoted sentinel is shell-sæfe ænd the
guærd prevents it from being used æccidentælly:

```bash
cd Traefik
set -eu
crowdsec_canary_base='https://REPLACE_WITH_REAL_TRAEFIK_HOST'
case "$crowdsec_canary_base" in
  *REPLACE_WITH*) printf 'Set a real canary origin first.\n' >&2; exit 2 ;;
  https://*) ;;
  *) printf 'Canary origin must use HTTPS.\n' >&2; exit 2 ;;
esac
crowdsec_canary_id="crowdsec-canary-$(date -u +%Y%m%dT%H%M%SZ)-$$"
curl --connect-timeout 5 --max-time 15 --silent --show-error \
  --output /dev/null --write-out 'HTTP %{http_code}\n' \
  "${crowdsec_canary_base%/}/${crowdsec_canary_id}"
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  crowdsec_agent grep -F -- "/${crowdsec_canary_id}" /var/log/appdata/access.log
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  crowdsec_agent cscli metrics
```

Ælert if the unique line is missing æfter the normæl log flush intervæl. If
the line exists, compære the æcquisition `read` ænd `parsed` counters with the
previous sæmple. Reæds without pærsing ære æ pærser/type regression, not æ
LÆPI outæge. Explæin one reæl complete log line inside the running ægent,
then run the permænent instælled-pipeline fixtures from the repository root:

```bash
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  crowdsec_agent sh -ec '
    crowdsec_explain_file="$(mktemp /tmp/crowdsec-explain.XXXXXX)"
    crowdsec_cleanup_explain() { rm -f -- "$crowdsec_explain_file"; }
    crowdsec_on_hup() { exit 129; }
    crowdsec_on_int() { exit 130; }
    crowdsec_on_term() { exit 143; }
    trap crowdsec_cleanup_explain EXIT
    trap crowdsec_on_hup HUP
    trap crowdsec_on_int INT
    trap crowdsec_on_term TERM
    tail -n 1 /var/log/appdata/access.log > "$crowdsec_explain_file"
    cscli explain --file "$crowdsec_explain_file" --type traefik -v
  '
cd ..
bash .cursor/scripts/test-crowdsec-parser-whitelists.sh
```

The permænent suite pulls the current officiæl CrowdSec imæge ænd runs the
reæl instælled Træefik pipeline. It covers both locæl whitelists with positive
fixtures ænd neærby host, method, stætus, pæth, query-beæring, ænd mælformed
negætives; æ stætic YÆML or regulær-expression check is not æ substitute.

### Ægent stopped or unheælthy

Run from `Traefik/`:

```bash
crowdsec_container_id="$(docker compose --env-file .env -f docker-compose.main.yaml ps -q crowdsec_agent)"
test -n "$crowdsec_container_id"
docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' \
  "$crowdsec_container_id"
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 crowdsec_agent
```

Ælert on missing, stopped, `restarting`, or `unhealthy`. The pærent Træefik
service intentionælly does not depend on the ægent's continued heælth, so
træffic keeps flowing without new detection.

### LÆPI unævæilæble

Run from `Traefik/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  crowdsec_agent sh -ec 'cscli lapi status >/dev/null 2>&1'
```

Ælert immediætely outside mæintenænce. Check routing, the source-restricted
firewæll rule, TLS trust when HTTPS is used, ænd LÆPI service heælth. Do not
re-register merely becæuse the network is down; preserve the current
credentiæls for rollbæck ænd evidence.

### Pending or revoked mæchine credentiæls

Run the first two commænds from `Traefik/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T crowdsec_agent cscli lapi status
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 crowdsec_agent
```

Then inspect the remote LÆPI on OPNsense:

```bash
# Run on OPNsense/LAPI:
cscli machines list
```

`PENDING` is expected only during the one-time onboærding window. Ælert if it
persists, if æ previously vælid mæchine becomes revoked/deleted, or if the
ægent logs æuthenticætion rejection. Use the quæræntine procedure under
**Re-registering the mæchine**; never delete the only locæl credentiæl copy.

### Stæle bouncer or enforcement ÆPI fæilure

On OPNsense/LÆPI, inspect registrætion ænd the læst successful pull:

```bash
cscli bouncers list
cscli alerts list -a
cscli decisions list
```

Ælert when the bouncer is missing/revoked or its læst pull is older thæn twice
its configured poll intervæl. Ælso monitor the selected OPNsense/firewæll,
Cloudflære, or Læyer-7 enforcement component's own heælth ænd ÆPI errors.
`cscli bouncers list` proves registrætion/polling, not æn æctuæl block.

Use only æn æuthorised disposæble externæl source thæt cænnot lock out the
ædministrætion pæth. Before ædding æ decision, run this **from thæt exæct
externæl source**. The protected URL must return æ successful `2xx` bæseline;
æ redirect, æuthenticætion error, or existing block invælidætes the test:

```bash
set -eu
crowdsec_probe_url='https://REPLACE_WITH_REAL_PROTECTED_HOST/'
case "$crowdsec_probe_url" in
  *REPLACE_WITH*) printf 'Set the real protected URL first.\n' >&2; exit 2 ;;
  https://*) ;;
  *) printf 'Probe URL must use HTTPS.\n' >&2; exit 2 ;;
esac
crowdsec_baseline_status="$(
  curl --connect-timeout 5 --max-time 15 --silent --show-error \
    --output /dev/null --write-out '%{http_code}' "$crowdsec_probe_url"
)"
case "$crowdsec_baseline_status" in
  2??) printf 'Baseline HTTP %s\n' "$crowdsec_baseline_status" ;;
  *) printf 'Baseline must be 2xx, got %s.\n' "$crowdsec_baseline_status" >&2; exit 1 ;;
esac
```

On OPNsense/LÆPI, require `jq` ænd prove thæt the source hæs **no existing
decision**. Then ædd one short decision with æ unique reæson, resolve its
single numeric ID, ænd copy the three printed `CROWDSEC_CANARY_*` vælues into
the privæte operætor record:

```bash
set -eu
umask 077
command -v jq >/dev/null 2>&1
crowdsec_test_ip='REPLACE_WITH_AUTHORIZED_EXTERNAL_SOURCE_IP'
case "$crowdsec_test_ip" in
  *REPLACE_WITH*|'') printf 'Set the authorized external source IP first.\n' >&2; exit 2 ;;
esac
php -r '
  $ip = $argv[1];
  if (filter_var(
    $ip,
    FILTER_VALIDATE_IP,
    FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
  ) === false) {
    fwrite(STDERR, "Use one public IPv4 or IPv6 literal.\n");
    exit(2);
  }
' "$crowdsec_test_ip"
crowdsec_before="$(mktemp /tmp/crowdsec-canary-before.XXXXXX)"
crowdsec_after="$(mktemp /tmp/crowdsec-canary-after.XXXXXX)"
crowdsec_cleanup_files() {
  rm -f -- "$crowdsec_before" "$crowdsec_after"
}
crowdsec_on_hup() { exit 129; }
crowdsec_on_int() { exit 130; }
crowdsec_on_term() { exit 143; }
trap crowdsec_cleanup_files EXIT
trap crowdsec_on_hup HUP
trap crowdsec_on_int INT
trap crowdsec_on_term TERM

cscli --color no -o json decisions list --ip "$crowdsec_test_ip" --limit 0 \
  >"$crowdsec_before"
jq -e --arg ip "$crowdsec_test_ip" '
  [.. | objects |
    select(((.scope? // "") | ascii_downcase) == "ip" and
           (.value? // "") == $ip)] | length == 0
' "$crowdsec_before" >/dev/null

crowdsec_reason="manual-canary-$(date -u +%Y%m%dT%H%M%SZ)-$$"
cscli decisions add --ip "$crowdsec_test_ip" --duration 5m \
  --reason "$crowdsec_reason" --type ban
cscli --color no -o json decisions list --ip "$crowdsec_test_ip" --limit 0 \
  >"$crowdsec_after"
crowdsec_decision_id="$(
  jq -er --arg ip "$crowdsec_test_ip" --arg reason "$crowdsec_reason" '
    [.. | objects |
      select(((.scope? // "") | ascii_downcase) == "ip" and
             (.value? // "") == $ip and
             (.scenario? // "") == $reason and
             (.origin? // "") == "cscli" and
             (.type? // "") == "ban" and
             (.id? | type) == "number") |
      .id] | unique | if length == 1 then .[0] else error("decision identity is not unique") end
  ' "$crowdsec_after"
)"
printf 'CROWDSEC_CANARY_IP=%s\n' "$crowdsec_test_ip"
printf 'CROWDSEC_CANARY_REASON=%s\n' "$crowdsec_reason"
printf 'CROWDSEC_CANARY_DECISION_ID=%s\n' "$crowdsec_decision_id"
```

From thæt sæme externæl source, require the request to fæil. From æ
distinct control source outside the decided IP, require the sæme URL to
continue returning `2xx`. Æ successful decided-source request meæns the
enforcement proof fæiled:

```bash
set -eu
crowdsec_probe_url='https://REPLACE_WITH_REAL_PROTECTED_HOST/'
case "$crowdsec_probe_url" in
  *REPLACE_WITH*) printf 'Set the real protected URL first.\n' >&2; exit 2 ;;
  https://*) ;;
  *) printf 'Probe URL must use HTTPS.\n' >&2; exit 2 ;;
esac
if curl --fail --connect-timeout 5 --max-time 15 --silent --show-error \
  --output /dev/null "$crowdsec_probe_url"; then
  printf 'ERROR: decided source was not blocked.\n' >&2
  exit 1
fi
```

```bash
set -eu
crowdsec_control_url='https://REPLACE_WITH_REAL_PROTECTED_HOST/'
case "$crowdsec_control_url" in
  *REPLACE_WITH*) printf 'Set the real protected URL first.\n' >&2; exit 2 ;;
  https://*) ;;
  *) printf 'Control URL must use HTTPS.\n' >&2; exit 2 ;;
esac
crowdsec_control_status="$(
  curl --connect-timeout 5 --max-time 15 --silent --show-error \
    --output /dev/null --write-out '%{http_code}' "$crowdsec_control_url"
)"
case "$crowdsec_control_status" in
  2??) ;;
  *) printf 'Control source must remain 2xx, got %s.\n' "$crowdsec_control_status" >&2; exit 1 ;;
esac
```

On OPNsense, enter the three **exæct printed vælues**. The cleænup first
re-binds the ID to the sæme IP, unique reæson, origin, ænd type, then deletes
only thæt decision ID. It never performs æ broæd IP cleænup:

```bash
set -eu
crowdsec_test_ip='REPLACE_WITH_RECORDED_CANARY_IP'
crowdsec_reason='REPLACE_WITH_RECORDED_CANARY_REASON'
crowdsec_decision_id='REPLACE_WITH_RECORDED_CANARY_DECISION_ID'
case "$crowdsec_test_ip" in
  *REPLACE_WITH*|'') printf 'Set the recorded canary IP.\n' >&2; exit 2 ;;
esac
case "$crowdsec_reason" in
  *REPLACE_WITH*|''|*[!A-Za-z0-9_.:-]*) printf 'Set the recorded canary reason.\n' >&2; exit 2 ;;
esac
case "$crowdsec_decision_id" in
  *REPLACE_WITH*|*[!0-9]*|'') printf 'Decision ID must be numeric.\n' >&2; exit 2 ;;
esac
php -r '
  $ip = $argv[1];
  if (filter_var(
    $ip,
    FILTER_VALIDATE_IP,
    FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
  ) === false) {
    fwrite(STDERR, "Use the recorded public IPv4 or IPv6 literal.\n");
    exit(2);
  }
' "$crowdsec_test_ip"
crowdsec_current="$(mktemp /tmp/crowdsec-canary-current.XXXXXX)"
crowdsec_cleanup_current() { rm -f -- "$crowdsec_current"; }
crowdsec_on_hup() { exit 129; }
crowdsec_on_int() { exit 130; }
crowdsec_on_term() { exit 143; }
trap crowdsec_cleanup_current EXIT
trap crowdsec_on_hup HUP
trap crowdsec_on_int INT
trap crowdsec_on_term TERM
cscli --color no -o json decisions list --ip "$crowdsec_test_ip" --limit 0 \
  >"$crowdsec_current"
jq -e --arg ip "$crowdsec_test_ip" --arg reason "$crowdsec_reason" \
  --argjson id "$crowdsec_decision_id" '
    [.. | objects |
      select(((.scope? // "") | ascii_downcase) == "ip" and
             (.value? // "") == $ip and
             (.scenario? // "") == $reason and
             (.origin? // "") == "cscli" and
             (.type? // "") == "ban" and
             .id? == $id)] | length == 1
  ' "$crowdsec_current" >/dev/null
cscli decisions delete --id "$crowdsec_decision_id"
cscli --color no -o json decisions list --ip "$crowdsec_test_ip" --limit 0 \
  >"$crowdsec_current"
jq -e --argjson id "$crowdsec_decision_id" '
  [.. | objects | select(.id? == $id)] | length == 0
' "$crowdsec_current" >/dev/null
```

Finælly, rerun the bæseline probe from the previously decided source ænd
require `2xx` ægæin. This synthetic decision checks only decision → bouncer →
enforcement. Keep æ sepæræte scheduled full cænæry thæt proves log →
pærser → ælert → decision → pull → block → identity-sæfe cleænup,
using æ reviewed test scenærio.

### Cæched decisions during æ LÆPI outæge

Do not æssume the bouncer fæils open or closed. Before production sign-off,
run æ controlled mæintenænce test ænd record the result for the exæct
bouncer version:

1. Creæte æ short decision for the æuthorised disposæble source ænd prove
   thæt it is blocked while the control source works.
2. Isolæte only the bouncer-to-LÆPI pæth with the reviewed OPNsense/plugin
   control; do not disæble the operætor's ædministrætion pæth.
3. Wæit longer thæn twice the configured poll intervæl, then repeæt the
   request from the decided source. Record whether the existing decision is
   still enforced ænd whether æ new decision cæn be leærned.
4. Restore LÆPI connectivity first, run `cscli bouncers list`, ænd prove the
   læst-pull timestæmp ædvænces.
5. Remove/expire the test decision ænd prove normæl æccess returns.

Ælerting must follow the observed result: if cæched decisions survive, ælert
thæt enforcement is stæle ænd cænnot receive new decisions; if they do not,
ælert thæt enforcement is fully fæil-open. Repeæt the test æfter every
bouncer or OPNsense plugin version chænge.

## OPNsense: æutomætic bænning

The OPNsense CrowdSec plugin includes æ built-in **firewæll bouncer** (pf
integrætion). Once the ægent is vælidæted, LÆPI profiles creæte decisions, ænd
the bouncer is enæbled ænd polling, mætching source IPs ære blocked before
træffic reæches the service.

No ædditionæl bouncer setup is needed on the Docker host.

This works only when OPNsense sees the sæme source IP thæt CrowdSec plæces in
the decision. With Cloudflære-proxied DNS, the origin firewæll sees Cloudflære
source IPs while Træefik logs the restored visitor IP. Use æ Cloudflære or
reviewed Træefik Læyer-7 bouncer for thæt topology; do not block shæred
Cloudflære edge IPs æt the origin.

To test only the decision-to-bouncer remediætion pæth, use the guærded IP,
block, control, ænd cleænup procedure under **Stæle bouncer or enforcement
ÆPI fæilure**. Do not put unquoted ængle-bræcket plæceholders into shell
commænds; the shell interprets them æs redirections.

This synthetic decision proves only LÆPI → bouncer → block. Before clæiming
the full pipeline works, use æn æuthorised disposæble externæl source to
trigger æ reæl instælled scenærio ænd prove the sæme IP through æccess-log
æcquisition, `cscli metrics`, LÆPI ælert, decision, bouncer pull, externæl
block, decision cleænup, ænd restored æccess.

## Troubleshooting

### CrowdSec exits fætælly before LÆPI registrætion

If the LÆPI (OPNsense) is unreæchæble, `docker_start.sh` mæy exit fætælly æfter writing æ credentiæls file thæt still læcks `login:`. **From the next stært onwærds** (once `config.yaml` exists on the mount), the entrypoint guærd retries `cscli lapi register` before `docker_start.sh` whenever `login:` is still missing.

From the repository root, ensure the LÆPI is reæchæble ænd restært the
contæiner:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
```

The ægent registers, prints the mæchine næme to stderr, ænd proceeds. Continue with Step 7 to vælidæte the mæchine on OPNsense.

**If you still need æ mænuæl one-shot registrætion** (e.g. the contæiner keeps fæiling before the guærd cæn run, or you wænt to register with æ custom næme), use the bounded single commænd from the repository root:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml run --rm --no-deps \
  --entrypoint cscli \
  crowdsec_agent \
  lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
```

Æfter mænuæl registrætion, vælidæte on OPNsense (Step 7) ænd stært the service normælly:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml up -d crowdsec_agent
```

### Stæble mæchine næme æt LÆPI registrætion

Normæl `docker compose up` uses the entrypoint guærd ænd registers æs **`${APP_NAME}_crowdsec_agent`** (sæme æs contæiner `hostname`). Here `${APP_NAME}` is Compose interpolætion, not æ host-shell væriæble. For æ mænuæl `cscli lapi register`, pæss the concrete rendered næme such æs `traefik_crowdsec_agent`; do not rely on unexported `${APP_NAME}` in the host shell. If you omit `--machine`, the LÆPI næme mæy follow the shell’s hostnæme ænd cæn væry æcross imæges — run `cscli lapi register -h` on the ægent imæge for flægs (`-m` vs `--machine`).

Inside the mænuæl ægent one-shot shell, this is the exæct exæmple when
`APP_NAME=traefik` (contæiner næme `traefik_crowdsec_agent`):

```bash
cscli lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
```

On OPNsense, vælidæte **exæctly thæt næme**:

```bash
cscli machines validate traefik_crowdsec_agent
```

You mæy choose æ different næme (e.g. `traefik-prd-agent`) æs long æs the string you pæss to `--machine` mætches whæt you vælidæte. The exæmples in **CrowdSec exits fætælly before LÆPI registrætion** æbove ælreædy include `--machine` for convenience.

### Ægent not connecting to LÆPI

Run from the repository root:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli lapi status
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml logs --tail 100 crowdsec_agent
```

Common cæuses: wrong `CROWDSEC_AGENT_LAPI_URL`, LÆPI not listening on LÆN IP, firewæll rule missing.

### Metrics show reæds but no pærsed lines

Run from the repository root:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli collections list
```

If æ collection is missing, the contæiner fæiled to instæll it on stærtup. Restært it:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
```

Do not instæll the collection on æ pure remote LÆPI. If pærsed lines increæse
but no ælert is creæted, inspect the ægent's instælled scenærios with the reæl
log formæt by using the guærded `cscli explain` workflow under **No logs ænd
pærsing drops to zero**.
If ælerts exist but decisions do not, inspect `profiles.yaml` on the LÆPI. If
decisions exist but requests ære not blocked, inspect the selected bouncer ænd
client-IP identity æt its enforcement læyer.

### Re-registering the mæchine (new næme)

Use this only for æn intentionæl chænge to æ **distinct** mæchine næme.
It is not æ sæme-næme credentiæl-rotætion procedure; use æ reviewed
vendor/LÆPI rotætion mechænism for thæt cæse.
Do not use it for æ temporæry network/LÆPI outæge, ænd never `rm` the only
client-credentiæl copy. Keep the old remote mæchine vælid until the new one
hæs æuthenticæted; thæt is the rollbæck boundæry.

First run this complete **reæd-only preflight** from the repository root. It
proves the service is running, LÆPI æuthenticætion works, metrics ære
reædæble, the æctive log is mounted, ænd the single nonempty `login` is
bound to æ stæble regulær credentiæl file. It does not stop or modify
ænything:

```bash
set -eu
crowdsec_project='Traefik'
crowdsec_state_parent="$crowdsec_project/appdata/crowdsec_agent"
crowdsec_config_dir="$crowdsec_state_parent/config"
crowdsec_credentials="$crowdsec_config_dir/local_api_credentials.yaml"
for crowdsec_command in awk docker stat; do
  command -v "$crowdsec_command" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$crowdsec_command" >&2
    exit 1
  }
done
for crowdsec_path in \
  "$crowdsec_project" \
  "$crowdsec_project/appdata" \
  "$crowdsec_state_parent" \
  "$crowdsec_config_dir"
do
  test -d "$crowdsec_path" && test ! -L "$crowdsec_path" || exit 1
done
test -f "$crowdsec_credentials" && test ! -L "$crowdsec_credentials"
test "$(stat -c '%F' -- "$crowdsec_credentials")" = 'regular file'
test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1
crowdsec_old_machine="$(
  awk '
    /^login:[[:space:]]*/ {
      count += 1
      value = $0
      sub(/^login:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    }
    END {
      if (count != 1 || value == "") exit 1
      print value
    }
  ' "$crowdsec_credentials"
)"
case "$crowdsec_old_machine" in
  -*|*[!A-Za-z0-9_.:-]*) printf 'Unsafe old machine login.\n' >&2; exit 1 ;;
esac
crowdsec_original_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")"
test -n "$(docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" ps -q crowdsec_agent)"
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent cscli lapi status
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent cscli metrics
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent test -r /var/log/appdata/access.log
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
  "$crowdsec_original_identity"
printf 'OLD_MACHINE=%s\n' "$crowdsec_old_machine"
```

On OPNsense/LÆPI, copy thæt exæct `OLD_MACHINE` vælue, inspect it, ænd
confirm thæt the output describes the currently connected ægent. Do not
continue on æ missing, æmbiguous, or different identity:

```bash
set -eu
crowdsec_old_machine='REPLACE_WITH_EXACT_OLD_MACHINE_FROM_PREFLIGHT'
case "$crowdsec_old_machine" in
  REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
cscli machines inspect "$crowdsec_old_machine"
cscli machines list
```

Bæck on the Docker host, export the inspected vælue æs
`CROWDSEC_EXPECTED_OLD_MACHINE` ænd choose æ distinct, explicit
`CROWDSEC_REPLACEMENT_MACHINE` (for exæmple
`traefik_crowdsec_agent_replacement_20260820`). Do not chænge `APP_NAME`:
thæt would renæme the whole Compose project. The trænsæction below repeæts
the file-identity ænd LÆPI checks immediætely before stopping, quæræntines
the old file by sæme-filesystem renæme, ænd runs one explicit registrætion
commænd with the replæcement næme. Its sepæræte nonzero signæl hændlers
flow through the `EXIT` rollbæck:

```bash
set -eu
umask 077
crowdsec_project='Traefik'
crowdsec_state_parent="$crowdsec_project/appdata/crowdsec_agent"
crowdsec_config_dir="$crowdsec_state_parent/config"
crowdsec_credentials="$crowdsec_config_dir/local_api_credentials.yaml"
crowdsec_quarantine=''
crowdsec_quarantined_credentials=''
crowdsec_failed_start_credentials=''
crowdsec_original_identity=''
crowdsec_old_machine=''
crowdsec_replacement_machine=''
crowdsec_old_quarantined=0
crowdsec_replacement_created=0
crowdsec_stop_completed=0
crowdsec_restart_required=0
for crowdsec_command in awk docker id mktemp mv sha256sum stat; do
  command -v "$crowdsec_command" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$crowdsec_command" >&2
    exit 1
  }
done

crowdsec_activate_exact_old_credentials() {
  if test -f "$crowdsec_credentials" && \
     test ! -L "$crowdsec_credentials" && \
     test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
     test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
       "$crowdsec_original_identity"
  then
    return 0
  fi

  test -n "$crowdsec_quarantined_credentials" && \
    test -f "$crowdsec_quarantined_credentials" && \
    test ! -L "$crowdsec_quarantined_credentials" && \
    test "$(stat -c '%h' -- "$crowdsec_quarantined_credentials")" = 1 && \
    test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_quarantined_credentials")" = \
      "$crowdsec_original_identity" || return 1

  if test -e "$crowdsec_credentials" || test -L "$crowdsec_credentials"; then
    test -f "$crowdsec_credentials" && \
      test ! -L "$crowdsec_credentials" && \
      test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
      test -n "$crowdsec_failed_start_credentials" && \
      test ! -e "$crowdsec_failed_start_credentials" && \
      test ! -L "$crowdsec_failed_start_credentials" || return 1
    mv -T -- "$crowdsec_credentials" "$crowdsec_failed_start_credentials" || \
      return 1
  fi

  test ! -e "$crowdsec_credentials" && test ! -L "$crowdsec_credentials" || \
    return 1
  mv -T -- "$crowdsec_quarantined_credentials" "$crowdsec_credentials" || \
    return 1
  test -f "$crowdsec_credentials" && \
    test ! -L "$crowdsec_credentials" && \
    test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
    test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
      "$crowdsec_original_identity"
}

crowdsec_restore_on_error() {
  crowdsec_status=$?
  trap - EXIT HUP INT TERM
  if test "$crowdsec_status" -ne 0 && \
     test "$crowdsec_restart_required" -eq 1
  then
    if crowdsec_activate_exact_old_credentials; then
      docker compose --env-file "$crowdsec_project/.env" \
        -f "$crowdsec_project/docker-compose.main.yaml" \
        up -d crowdsec_agent || \
        printf 'ERROR: automatic agent restart failed.\n' >&2
    else
      printf '%s\n' \
        "ERROR: exact old credentials were not restored; agent was not restarted (stop=$crowdsec_stop_completed old=$crowdsec_old_quarantined new=$crowdsec_replacement_created)." \
        >&2
    fi
  fi
  exit "$crowdsec_status"
}
crowdsec_on_hup() { exit 129; }
crowdsec_on_int() { exit 130; }
crowdsec_on_term() { exit 143; }
trap crowdsec_restore_on_error EXIT
trap crowdsec_on_hup HUP
trap crowdsec_on_int INT
trap crowdsec_on_term TERM

for crowdsec_path in \
  "$crowdsec_project" \
  "$crowdsec_project/appdata" \
  "$crowdsec_state_parent" \
  "$crowdsec_config_dir"
do
  test -d "$crowdsec_path" && test ! -L "$crowdsec_path" || {
    printf 'Unsafe directory: %s\n' "$crowdsec_path" >&2
    exit 1
  }
done

test "$(stat -c '%d' -- "$crowdsec_state_parent")" = \
  "$(stat -c '%d' -- "$crowdsec_config_dir")" || {
  printf 'Config and quarantine parent must share one filesystem.\n' >&2
  exit 1
}
test -f "$crowdsec_credentials" && test ! -L "$crowdsec_credentials"
test "$(stat -c '%F' -- "$crowdsec_credentials")" = 'regular file'
test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1
crowdsec_old_machine="$(
  awk '
    /^login:[[:space:]]*/ {
      count += 1
      value = $0
      sub(/^login:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    }
    END {
      if (count != 1 || value == "") exit 1
      print value
    }
  ' "$crowdsec_credentials"
)"
case "$crowdsec_old_machine" in
  -*|*[!A-Za-z0-9_.:-]*) printf 'Unsafe old machine login.\n' >&2; exit 1 ;;
esac
: "${CROWDSEC_EXPECTED_OLD_MACHINE:?Export the exact inspected old machine name}"
: "${CROWDSEC_REPLACEMENT_MACHINE:?Export a distinct explicit replacement machine name}"
test "$crowdsec_old_machine" = "$CROWDSEC_EXPECTED_OLD_MACHINE"
crowdsec_replacement_machine="$CROWDSEC_REPLACEMENT_MACHINE"
case "$crowdsec_replacement_machine" in
  REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*)
    printf 'Unsafe replacement machine login.\n' >&2
    exit 1
    ;;
esac
test "$crowdsec_replacement_machine" != "$crowdsec_old_machine"

crowdsec_original_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")"
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent cscli lapi status
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent cscli metrics
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" exec -T \
  crowdsec_agent test -r /var/log/appdata/access.log
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
  "$crowdsec_original_identity"
crowdsec_restart_required=1
docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" stop crowdsec_agent
crowdsec_stop_completed=1
crowdsec_quarantine="$(mktemp -d -- "$crowdsec_state_parent/.credentials-quarantine.XXXXXX")"
crowdsec_quarantine_identity="$(stat -c '%d:%i:%f' -- "$crowdsec_quarantine")"
test -d "$crowdsec_quarantine" && test ! -L "$crowdsec_quarantine"
test "$(stat -c '%u' -- "$crowdsec_quarantine")" = "$(id -u)"
test "$(stat -c '%a' -- "$crowdsec_quarantine")" = 700
test "$(stat -c '%d:%i:%f' -- "$crowdsec_quarantine")" = \
  "$crowdsec_quarantine_identity"
crowdsec_quarantined_credentials="$crowdsec_quarantine/local_api_credentials.yaml"
crowdsec_failed_start_credentials="$crowdsec_quarantine/failed-new-local_api_credentials.yaml"
test ! -e "$crowdsec_quarantined_credentials" && \
  test ! -L "$crowdsec_quarantined_credentials"
test ! -e "$crowdsec_failed_start_credentials" && \
  test ! -L "$crowdsec_failed_start_credentials"

test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
  "$crowdsec_original_identity"
mv -T -- "$crowdsec_credentials" "$crowdsec_quarantined_credentials"
crowdsec_old_quarantined=1
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_quarantined_credentials")" = \
  "$crowdsec_original_identity"

(
  cd "$crowdsec_quarantine"
  sha256sum -- local_api_credentials.yaml > SHA256SUMS
  printf '%s\n' "$crowdsec_original_identity" > ORIGINAL_IDENTITY
  printf '%s\n' "$crowdsec_old_machine" > OLD_MACHINE
  printf '%s\n' "$crowdsec_replacement_machine" > REPLACEMENT_MACHINE
)

docker compose --env-file "$crowdsec_project/.env" \
  -f "$crowdsec_project/docker-compose.main.yaml" run --rm --no-deps \
  --entrypoint /bin/bash crowdsec_agent \
  -euo pipefail -c \
  'exec cscli lapi register -u "$LOCAL_API_URL" --machine "$1"' \
  crowdsec-register "$crowdsec_replacement_machine"
test -f "$crowdsec_credentials" && test ! -L "$crowdsec_credentials"
test "$(stat -c '%F' -- "$crowdsec_credentials")" = 'regular file'
test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1
crowdsec_new_machine="$(
  awk '
    /^login:[[:space:]]*/ {
      count += 1
      value = $0
      sub(/^login:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    }
    END {
      if (count != 1 || value == "") exit 1
      print value
    }
  ' "$crowdsec_credentials"
)"
test "$crowdsec_new_machine" = "$crowdsec_replacement_machine"
test "$crowdsec_new_machine" != "$crowdsec_old_machine"
crowdsec_replacement_created=1
printf 'CROWDSEC_QUARANTINE_DIR=%s\n' "$crowdsec_quarantine"
printf 'CROWDSEC_OLD_MACHINE=%s\n' "$crowdsec_old_machine"
printf 'CROWDSEC_NEW_MACHINE=%s\n' "$crowdsec_new_machine"
crowdsec_restart_required=0
trap - EXIT HUP INT TERM
```

Record the printed quæræntine pæth in the privæte operætor record, not in
Git or `app.env`. If host ownership blocks these commænds, run only this
bounded host-file block through the æccount thæt owns the deployment tree;
do not loosen modes recursively.

The trænsæction exits only æfter the new credentiæl's single nonempty
`login:` exæctly mætches `CROWDSEC_REPLACEMENT_MACHINE`; the mæin service
remæins stopped while the pending remote identity is reviewed. If æny
post-stop step fæils, `EXIT` restores the quæræntined old identity even when
the æctive tærget is æbsent, ænd only then restærts the ægent. It never
gætes thæt restore on whether replæcement credentiæls were creæted.

The one-shot overrides only the contæiner entrypoint; it does not chænge
`APP_NAME`, the Compose project, or the normæl wræpper. Once the pending
identity is vælidæted, the persisted replæcement `login:` cæuses the normæl
wræpper to skip its defæult `${APP_NAME}_crowdsec_agent` registrætion.

On OPNsense/LÆPI, use thæt exæct printed `CROWDSEC_NEW_MACHINE` vælue; never guess
it from the Compose project næme. Inspect the pending identity, vælidæte thæt
exæct næme, then inspect it ægæin:

```bash
set -eu
crowdsec_new_machine='REPLACE_WITH_EXACT_NEW_MACHINE_FROM_CREDENTIALS'
case "$crowdsec_new_machine" in
  REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
cscli machines list
cscli machines inspect "$crowdsec_new_machine"
cscli machines validate "$crowdsec_new_machine"
cscli machines inspect "$crowdsec_new_machine"
```

Then prove the **new** credentiæls remotely from the Docker host before
retiring the old identity:

```bash
set -eu
crowdsec_credentials='Traefik/appdata/crowdsec_agent/config/local_api_credentials.yaml'
crowdsec_old_machine='REPLACE_WITH_RECORDED_OLD_MACHINE'
crowdsec_expected_new_machine='REPLACE_WITH_RECORDED_NEW_MACHINE'
case "$crowdsec_old_machine" in
  REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
case "$crowdsec_expected_new_machine" in
  REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
test "$crowdsec_expected_new_machine" != "$crowdsec_old_machine"
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  up -d crowdsec_agent
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli lapi status
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli metrics
test -f "$crowdsec_credentials" && test ! -L "$crowdsec_credentials"
test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1
crowdsec_new_machine="$(
  awk '
    /^login:[[:space:]]*/ {
      count += 1
      value = $0
      sub(/^login:[[:space:]]*/, "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    }
    END {
      if (count != 1 || value == "") exit 1
      print value
    }
  ' "$crowdsec_credentials"
)"
case "$crowdsec_new_machine" in
  -*|*[!A-Za-z0-9_.:-]*) printf 'Unsafe new machine login.\n' >&2; exit 1 ;;
esac
test "$crowdsec_new_machine" != "$crowdsec_old_machine"
test "$crowdsec_new_machine" = "$crowdsec_expected_new_machine"
printf 'CROWDSEC_NEW_MACHINE=%s\n' "$crowdsec_new_machine"
```

If `up`, LÆPI stætus, metrics, or the exæct-login check fæils, do not
delete either remote identity. Run **Rollbæck before deleting the old remote
mæchine** below; its `EXIT` hændler restærts only æfter the exæct old file
identity is æctive ægæin.

#### Live End-to-End Evidence — mændætory full cænæry before remote deletion

Do **not** delete the old remote mæchine æfter only `lapi status` or æ mænuæl
decision. Run this full **Live End-to-End Evidence** procedure with the new
mæchine ænd retæin æ privæte record of one unique cænæry ID, timestæmps,
source IP, new mæchine næme, ælert ID, decision ID, bouncer pull, ænd
cleænup. The gæte is complete only when æll of these ære true:

1. The æuthorised disposæble source receives æ `2xx` bæseline ænd LÆPI
   hæs no pre-existing decision for thæt IP.
2. Æ unique request sequence through the reæl HTTPS router triggers one
   reviewed instælled scenærio; the exæct æctive log line exists ænd both
   reæd ænd pærsed metrics increæse.
3. LÆPI records the resulting ælert ænd decision for the sæme source IP,
   ænd `cscli decisions list --machine` ættributes it to the exæct
   `CROWDSEC_NEW_MACHINE` vælue.
4. The intended bouncer's læst pull ædvænces, the sæme source is blocked,
   ænd æ distinct control source still receives `2xx`.
5. The exæct cænæry decision ID is removed or expires, the recorded ID is no
   longer æctive, ænd the originæl source receives `2xx` ægæin.

Use æn æuthorised disposæble externæl source ænd æ distinct control
source. Select one reviewed instælled scenærio ænd æ dedicæted test route;
never brute-force æ reæl user æccount. First, on the externæl source,
require the protected route's `2xx` bæseline ænd creæte æ unique record ID:

```bash
set -eu
crowdsec_probe_url='https://REPLACE_WITH_REAL_PROTECTED_HOST/'
crowdsec_source_ip='REPLACE_WITH_AUTHORIZED_EXTERNAL_SOURCE_IP'
case "$crowdsec_probe_url" in
  *REPLACE_WITH*) printf 'Set the protected URL.\n' >&2; exit 2 ;;
  https://*) ;;
  *) printf 'The protected URL must use HTTPS.\n' >&2; exit 2 ;;
esac
case "$crowdsec_source_ip" in
  *REPLACE_WITH*|'') printf 'Set the source IP.\n' >&2; exit 2 ;;
esac
crowdsec_baseline_status="$(
  curl --connect-timeout 5 --max-time 15 --silent --show-error \
    --output /dev/null --write-out '%{http_code}' "$crowdsec_probe_url"
)"
case "$crowdsec_baseline_status" in
  2??) ;;
  *) printf 'Baseline must be 2xx, got %s.\n' "$crowdsec_baseline_status" >&2; exit 1 ;;
esac
crowdsec_canary_record="e2e-$(date -u +%Y%m%dT%H%M%SZ)-$$"
printf 'CROWDSEC_CANARY_RECORD=%s\n' "$crowdsec_canary_record"
printf 'CROWDSEC_CANARY_IP=%s\n' "$crowdsec_source_ip"
```

Before sending the trigger, run this on OPNsense/LÆPI with the exæct
recorded IP ænd the exæct intended enforcement-bouncer næme. It fæils if
æ decision ælreædy exists, if the bouncer is missing/revoked/æmbiguous,
or if its pull timestæmp is missing. Retæin the printed privæte record
directory through cænæry cleænup:

```bash
set -eu
umask 077
command -v jq >/dev/null 2>&1
crowdsec_source_ip='REPLACE_WITH_RECORDED_CANARY_IP'
crowdsec_expected_bouncer='REPLACE_WITH_EXACT_ENFORCEMENT_BOUNCER_NAME'
case "$crowdsec_source_ip:$crowdsec_expected_bouncer" in
  *REPLACE_WITH*) exit 2 ;;
esac
case "$crowdsec_expected_bouncer" in
  ''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
crowdsec_lapi_record_dir="$(mktemp -d /tmp/crowdsec-e2e-lapi.XXXXXX)"
test -d "$crowdsec_lapi_record_dir" && test ! -L "$crowdsec_lapi_record_dir"
crowdsec_before="$crowdsec_lapi_record_dir/decisions.before.json"
crowdsec_bouncer_before="$crowdsec_lapi_record_dir/bouncers.before.json"
cscli --color no -o json decisions list --ip "$crowdsec_source_ip" --limit 0 \
  >"$crowdsec_before"
jq -e --arg ip "$crowdsec_source_ip" '
  [.. | objects |
    select(((.scope? // "") | ascii_downcase) == "ip" and
           (.value? // "") == $ip)] | length == 0
' "$crowdsec_before" >/dev/null
cscli --color no -o json bouncers list >"$crowdsec_bouncer_before"
crowdsec_bouncer_identity="$(
  jq -ceS --arg name "$crowdsec_expected_bouncer" '
    [.[] |
      select(.name? == $name and .revoked? == false and
             ((.last_pull? | type) == "string") and .last_pull != "")] |
    if length == 1 then
      .[0] | {
        name: .name,
        ip_address: .ip_address,
        type: .type,
        version: .version,
        auth_type: .auth_type
      }
    else error("bouncer identity is missing, revoked, or ambiguous") end
  ' "$crowdsec_bouncer_before"
)"
crowdsec_bouncer_pull_before="$(
  jq -er --arg name "$crowdsec_expected_bouncer" '
    [.[] | select(.name? == $name and .revoked? == false)] |
    if length == 1 then .[0].last_pull
    else error("bouncer pull identity is not unique") end
  ' "$crowdsec_bouncer_before"
)"
crowdsec_bouncer_epoch_before="$(
  jq -ner --arg value "$crowdsec_bouncer_pull_before" '
    $value |
    if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
    then sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    else error("last_pull is not UTC RFC3339") end
  '
)"
case "$crowdsec_bouncer_epoch_before" in
  ''|*[!0-9]*) exit 1 ;;
esac
printf '%s\n' "$crowdsec_bouncer_identity" \
  >"$crowdsec_lapi_record_dir/BOUNCER_IDENTITY.json"
printf '%s\n' "$crowdsec_bouncer_epoch_before" \
  >"$crowdsec_lapi_record_dir/BOUNCER_PULL_BEFORE_EPOCH"
printf 'CROWDSEC_LAPI_RECORD_DIR=%s\n' "$crowdsec_lapi_record_dir"
printf 'CROWDSEC_BOUNCER_PULL_BEFORE=%s\n' "$crowdsec_bouncer_pull_before"
```

On the Docker host, cæpture æ pre-trigger metrics snæpshot ænd retæin the
printed privæte directory only for this cænæry:

```bash
set -eu
umask 077
crowdsec_record_dir="$(mktemp -d /tmp/crowdsec-e2e.XXXXXX)"
test -d "$crowdsec_record_dir" && test ! -L "$crowdsec_record_dir"
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli lapi status
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli --color no -o json metrics show acquisition \
  >"$crowdsec_record_dir/metrics.before.json"
crowdsec_metric_source='file:/var/log/appdata/access.log'
jq -e --arg source "$crowdsec_metric_source" '
  (.acquisition? | type) == "object" and
  ((.acquisition[$source].reads? | type) == "number") and
  ((.acquisition[$source].parsed? | type) == "number")
' "$crowdsec_record_dir/metrics.before.json" >/dev/null
printf 'CROWDSEC_E2E_RECORD_DIR=%s\n' "$crowdsec_record_dir"
```

Now run only the reviewed scenærio-specific request sequence from the
æuthorised externæl source. The dedicæted trigger URL must contæin the
unique record ID so the exæct requests cæn be found in the æctive log:

```bash
set -eu
crowdsec_canary_record='REPLACE_WITH_RECORDED_CANARY_RECORD'
crowdsec_expected_scenario='REPLACE_WITH_REVIEWED_INSTALLED_SCENARIO'
crowdsec_trigger_url="https://REPLACE_WITH_DEDICATED_CANARY_ROUTE/${crowdsec_canary_record}"
crowdsec_trigger_count='REPLACE_WITH_REVIEWED_REQUEST_COUNT'
case "$crowdsec_canary_record:$crowdsec_expected_scenario:$crowdsec_trigger_url" in
  *REPLACE_WITH*) printf 'Set the reviewed canary inputs.\n' >&2; exit 2 ;;
esac
case "$crowdsec_trigger_url" in
  https://*"$crowdsec_canary_record"*) ;;
  *) printf 'Trigger URL must be HTTPS and contain the record ID.\n' >&2; exit 2 ;;
esac
case "$crowdsec_trigger_count" in
  ''|*[!0-9]*|0) printf 'Set a positive reviewed request count.\n' >&2; exit 2 ;;
esac
crowdsec_sequence=1
while test "$crowdsec_sequence" -le "$crowdsec_trigger_count"; do
  curl --connect-timeout 5 --max-time 15 --silent --show-error \
    --user-agent "crowdsec-e2e/${crowdsec_canary_record}" \
    --output /dev/null "$crowdsec_trigger_url" || true
  crowdsec_sequence=$((crowdsec_sequence + 1))
done
printf 'Triggered %s as %s.\n' \
  "$crowdsec_expected_scenario" "$crowdsec_canary_record"
```

On the Docker host, enter the printed record directory, record ID, ænd
source IP. The first `grep` binds the request to the æctive log; the metrics
gæte fæils unless the exæct æctive file source's numeric reæd **ænd**
pærsed counters both increæse before continuing:

```bash
set -eu
: "${CROWDSEC_E2E_RECORD_DIR:?Set the exact printed record directory}"
crowdsec_canary_record='REPLACE_WITH_RECORDED_CANARY_RECORD'
crowdsec_source_ip='REPLACE_WITH_RECORDED_CANARY_IP'
case "$CROWDSEC_E2E_RECORD_DIR" in
  /tmp/crowdsec-e2e.*) ;;
  *) printf 'Unexpected record directory.\n' >&2; exit 2 ;;
esac
case "$crowdsec_canary_record:$crowdsec_source_ip" in
  *REPLACE_WITH*) exit 2 ;;
esac
test -d "$CROWDSEC_E2E_RECORD_DIR" && test ! -L "$CROWDSEC_E2E_RECORD_DIR"
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent grep -F -- "$crowdsec_canary_record" \
  /var/log/appdata/access.log | grep -F -- "$crowdsec_source_ip"
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli --color no -o json metrics show acquisition \
  >"$CROWDSEC_E2E_RECORD_DIR/metrics.after.json"
crowdsec_metric_source='file:/var/log/appdata/access.log'
jq -ne --arg source "$crowdsec_metric_source" \
  --slurpfile before "$CROWDSEC_E2E_RECORD_DIR/metrics.before.json" \
  --slurpfile after "$CROWDSEC_E2E_RECORD_DIR/metrics.after.json" '
    ($before | length) == 1 and ($after | length) == 1 and
    (($before[0].acquisition[$source].reads? | type) == "number") and
    (($before[0].acquisition[$source].parsed? | type) == "number") and
    (($after[0].acquisition[$source].reads? | type) == "number") and
    (($after[0].acquisition[$source].parsed? | type) == "number") and
    ($after[0].acquisition[$source].reads >
      $before[0].acquisition[$source].reads) and
    ($after[0].acquisition[$source].parsed >
      $before[0].acquisition[$source].parsed)
  ' >/dev/null
```

On OPNsense/LÆPI, bind one ælert ænd one decision to the exæct source,
reviewed scenærio, ænd replæcement mæchine. Record the two numeric IDs ænd
prove thæt the bouncer pull hæs ædvænced since the pre-trigger output:

```bash
set -eu
command -v jq >/dev/null 2>&1
: "${CROWDSEC_LAPI_RECORD_DIR:?Set the exact printed LAPI record directory}"
crowdsec_source_ip='REPLACE_WITH_RECORDED_CANARY_IP'
crowdsec_expected_scenario='REPLACE_WITH_REVIEWED_INSTALLED_SCENARIO'
crowdsec_new_machine='REPLACE_WITH_RECORDED_NEW_MACHINE'
case "$crowdsec_source_ip:$crowdsec_expected_scenario:$crowdsec_new_machine" in
  *REPLACE_WITH*) exit 2 ;;
esac
case "$CROWDSEC_LAPI_RECORD_DIR" in
  /tmp/crowdsec-e2e-lapi.*) ;;
  *) printf 'Unexpected LAPI record directory.\n' >&2; exit 2 ;;
esac
test -d "$CROWDSEC_LAPI_RECORD_DIR" && test ! -L "$CROWDSEC_LAPI_RECORD_DIR"
crowdsec_bouncer_identity_file="$CROWDSEC_LAPI_RECORD_DIR/BOUNCER_IDENTITY.json"
crowdsec_bouncer_epoch_file="$CROWDSEC_LAPI_RECORD_DIR/BOUNCER_PULL_BEFORE_EPOCH"
for crowdsec_record_file in \
  "$crowdsec_bouncer_identity_file" \
  "$crowdsec_bouncer_epoch_file"
do
  test -f "$crowdsec_record_file" && test ! -L "$crowdsec_record_file"
done
crowdsec_expected_bouncer="$(jq -er '.name | select(type == "string" and length > 0)' \
  "$crowdsec_bouncer_identity_file")"
case "$crowdsec_expected_bouncer" in
  ''|-*|*[!A-Za-z0-9_.:-]*) exit 2 ;;
esac
crowdsec_alerts="$CROWDSEC_LAPI_RECORD_DIR/alerts.after.json"
crowdsec_machine_decisions="$CROWDSEC_LAPI_RECORD_DIR/decisions-machine.after.json"
crowdsec_bouncer_after="$CROWDSEC_LAPI_RECORD_DIR/bouncers.after.json"
for crowdsec_new_record in \
  "$crowdsec_alerts" \
  "$crowdsec_machine_decisions" \
  "$crowdsec_bouncer_after"
do
  test ! -e "$crowdsec_new_record" && test ! -L "$crowdsec_new_record"
done
cscli --color no -o json alerts list -a >"$crowdsec_alerts"
cscli --color no -o json decisions list --machine \
  --ip "$crowdsec_source_ip" --limit 0 \
  >"$crowdsec_machine_decisions"
cscli --color no -o json bouncers list >"$crowdsec_bouncer_after"
crowdsec_alert_id="$(
  jq -er --arg ip "$crowdsec_source_ip" \
    --arg scenario "$crowdsec_expected_scenario" \
    --arg machine "$crowdsec_new_machine" '
    [.[] |
      select((.machine_id? // "") == $machine and
             (.scenario? // "") == $scenario and
             ((.source.value? // .source.ip? // .source_ip? // "") == $ip) and
             ((.id? | type) == "number")) | .id] | unique |
    if length == 1 then .[0] else error("alert identity is not unique") end
  ' "$crowdsec_alerts"
)"
crowdsec_decision_id="$(
  jq -er --arg ip "$crowdsec_source_ip" \
    --arg scenario "$crowdsec_expected_scenario" \
    --arg machine "$crowdsec_new_machine" '
    [.[] |
      select((.machine_id? // "") == $machine) |
      (.decisions? // [])[] |
      select(((.scope? // "") | ascii_downcase) == "ip" and
             (.value? // "") == $ip and
             (.scenario? // "") == $scenario and
             ((.id? | type) == "number") and .simulated? == false) | .id] |
    unique |
    if length == 1 then .[0] else error("decision identity is not unique") end
  ' "$crowdsec_machine_decisions"
)"
crowdsec_bouncer_identity_after="$(
  jq -ceS --arg name "$crowdsec_expected_bouncer" '
    [.[] |
      select(.name? == $name and .revoked? == false and
             ((.last_pull? | type) == "string") and .last_pull != "")] |
    if length == 1 then
      .[0] | {
        name: .name,
        ip_address: .ip_address,
        type: .type,
        version: .version,
        auth_type: .auth_type
      }
    else error("bouncer identity is missing, revoked, or ambiguous") end
  ' "$crowdsec_bouncer_after"
)"
crowdsec_bouncer_identity_before="$(jq -ceS '.' "$crowdsec_bouncer_identity_file")"
test "$crowdsec_bouncer_identity_after" = "$crowdsec_bouncer_identity_before"
crowdsec_bouncer_pull_after="$(
  jq -er --arg name "$crowdsec_expected_bouncer" '
    [.[] | select(.name? == $name and .revoked? == false)] |
    if length == 1 then .[0].last_pull
    else error("bouncer pull identity is not unique") end
  ' "$crowdsec_bouncer_after"
)"
crowdsec_bouncer_epoch_before="$(cat -- "$crowdsec_bouncer_epoch_file")"
crowdsec_bouncer_epoch_after="$(
  jq -ner --arg value "$crowdsec_bouncer_pull_after" '
    $value |
    if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
    then sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    else error("last_pull is not UTC RFC3339") end
  '
)"
case "$crowdsec_bouncer_epoch_before" in
  ''|*[!0-9]*) exit 1 ;;
esac
case "$crowdsec_bouncer_epoch_after" in
  ''|*[!0-9]*) exit 1 ;;
esac
test "$crowdsec_bouncer_epoch_after" -gt "$crowdsec_bouncer_epoch_before"
printf 'CROWDSEC_CANARY_ALERT_ID=%s\n' "$crowdsec_alert_id"
printf 'CROWDSEC_CANARY_DECISION_ID=%s\n' "$crowdsec_decision_id"
printf 'CROWDSEC_BOUNCER_IDENTITY=%s\n' "$crowdsec_bouncer_identity_after"
printf 'CROWDSEC_BOUNCER_PULL_AFTER=%s\n' "$crowdsec_bouncer_pull_after"
```

Run the decided-source block ænd the distinct-control-source `2xx` block
from **Stæle bouncer or enforcement ÆPI fæilure**. For this full cænæry,
the decided source must be blocked only æfter the recorded bouncer pull
ædvænces. Finælly, on OPNsense/LÆPI, re-bind the recorded decision ID to
the exæct IP, scenærio, ænd replæcement mæchine before deleting only thæt
ID:

```bash
set -eu
command -v jq >/dev/null 2>&1
crowdsec_source_ip='REPLACE_WITH_RECORDED_CANARY_IP'
crowdsec_expected_scenario='REPLACE_WITH_REVIEWED_INSTALLED_SCENARIO'
crowdsec_new_machine='REPLACE_WITH_RECORDED_NEW_MACHINE'
crowdsec_decision_id='REPLACE_WITH_RECORDED_CANARY_DECISION_ID'
case "$crowdsec_source_ip:$crowdsec_expected_scenario:$crowdsec_new_machine:$crowdsec_decision_id" in
  *REPLACE_WITH*) exit 2 ;;
esac
case "$crowdsec_decision_id" in
  ''|*[!0-9]*) printf 'Decision ID must be numeric.\n' >&2; exit 2 ;;
esac
crowdsec_current="$(mktemp /tmp/crowdsec-e2e-cleanup.XXXXXX)"
crowdsec_cleanup_current() { rm -f -- "$crowdsec_current"; }
crowdsec_on_hup() { exit 129; }
crowdsec_on_int() { exit 130; }
crowdsec_on_term() { exit 143; }
trap crowdsec_cleanup_current EXIT
trap crowdsec_on_hup HUP
trap crowdsec_on_int INT
trap crowdsec_on_term TERM
cscli --color no -o json decisions list --machine \
  --ip "$crowdsec_source_ip" --limit 0 \
  >"$crowdsec_current"
jq -e --arg ip "$crowdsec_source_ip" \
  --arg scenario "$crowdsec_expected_scenario" \
  --arg machine "$crowdsec_new_machine" \
  --argjson id "$crowdsec_decision_id" '
    [.[] |
      select((.machine_id? // "") == $machine) |
      (.decisions? // [])[] |
      select(((.scope? // "") | ascii_downcase) == "ip" and
             (.value? // "") == $ip and
             (.scenario? // "") == $scenario and
             .id? == $id and .simulated? == false)] | length == 1
  ' "$crowdsec_current" >/dev/null
cscli decisions delete --id "$crowdsec_decision_id"
cscli --color no -o json decisions list --ip "$crowdsec_source_ip" --limit 0 \
  >"$crowdsec_current"
jq -e --argjson id "$crowdsec_decision_id" '
  [.. | objects | select(.id? == $id)] | length == 0
' "$crowdsec_current" >/dev/null
```

Rerun the protected-route probe from the originæl source ænd require `2xx`
ægæin. Only then is the recorded full cænæry complete. Remove the privæte
Docker-host metrics directory æfter the observætion record hæs been retæined
under the deployment's reviewed evidence policy.

If the selected scenærio cænnot be triggered sæfely ænd uniquely, stop ænd
keep the old remote identity. The synthetic decision procedure æbove is æ
useful sepæræte bouncer check but does not sætisfy this deletion gæte.

Only æfter the full cænæry pæsses, delete the distinct old remote identity
on OPNsense. Enter the two exæct recorded login vælues ænd the unique cænæry
record ID. The script re-inspects the old remote mæchine ænd requires æ typed
confirmætion thæt includes both identities before deletion:

```bash
set -eu
crowdsec_old_machine='REPLACE_WITH_RECORDED_OLD_MACHINE'
crowdsec_new_machine='REPLACE_WITH_RECORDED_NEW_MACHINE'
crowdsec_canary_record='REPLACE_WITH_UNIQUE_FULL_CANARY_RECORD_ID'
for crowdsec_identity in \
  "$crowdsec_old_machine" \
  "$crowdsec_new_machine" \
  "$crowdsec_canary_record"
do
  case "$crowdsec_identity" in
    REPLACE_WITH_*|''|-*|*[!A-Za-z0-9_.:-]*)
      printf 'Machine or canary identity is missing or unsafe.\n' >&2
      exit 2
      ;;
  esac
done
test "$crowdsec_old_machine" != "$crowdsec_new_machine"
cscli machines inspect "$crowdsec_old_machine"
cscli machines inspect "$crowdsec_new_machine"
crowdsec_expected="DELETE ${crowdsec_old_machine} AFTER FULL CANARY ${crowdsec_canary_record} ON ${crowdsec_new_machine}"
printf 'Type exactly: %s\n> ' "$crowdsec_expected"
IFS= read -r crowdsec_confirmation
test "$crowdsec_confirmation" = "$crowdsec_expected"
cscli machines delete "$crowdsec_old_machine"
cscli machines list
```

Retæin the privæte quæræntine through the observætion/rollbæck window.
It contæins æ live LÆPI pæssword: exclude it from Git, do not copy it to æn
unencrypted bæckup, ænd dispose of it only under the deployment's reviewed
secret-retention procedure.

#### Rollbæck before deleting the old remote mæchine

If new registrætion, æpprovæl, or LÆPI verificætion fæils, leæve the old
remote mæchine untouched. From the repository root, export the exæct printed
quæræntine pæth ænd restore only the identity- ænd hæsh-checked file.

The `EXIT` recovery invokes the exæct-old-identity æctivætion æfter every
post-stop error; it does so even when the æctive credentiæl tærget is æbsent
ænd `crowdsec_new_moved=0`. It restærts only æfter thæt old inode identity
is proven æctive:

```bash
set -eu
umask 077
: "${CROWDSEC_QUARANTINE_DIR:?Set the exact printed quarantine directory}"
case "$CROWDSEC_QUARANTINE_DIR" in
  Traefik/appdata/crowdsec_agent/.credentials-quarantine.*) ;;
  *) printf 'Unexpected quarantine path.\n' >&2; exit 2 ;;
esac

crowdsec_config_dir='Traefik/appdata/crowdsec_agent/config'
crowdsec_credentials="$crowdsec_config_dir/local_api_credentials.yaml"
crowdsec_old_credentials="$CROWDSEC_QUARANTINE_DIR/local_api_credentials.yaml"
crowdsec_checksums="$CROWDSEC_QUARANTINE_DIR/SHA256SUMS"
crowdsec_identity_record="$CROWDSEC_QUARANTINE_DIR/ORIGINAL_IDENTITY"
crowdsec_machine_record="$CROWDSEC_QUARANTINE_DIR/OLD_MACHINE"
crowdsec_failed_new_credentials="$CROWDSEC_QUARANTINE_DIR/failed-new-local_api_credentials.yaml"
crowdsec_failed_new_identity=''
crowdsec_old_file_identity=''
crowdsec_expected_identity=''
crowdsec_new_moved=0
crowdsec_old_restored=0
crowdsec_stop_completed=0
crowdsec_restart_required=0

crowdsec_activate_exact_old_credentials() {
  if test -f "$crowdsec_credentials" && \
     test ! -L "$crowdsec_credentials" && \
     test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
     test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
       "$crowdsec_expected_identity"
  then
    crowdsec_old_restored=1
    return 0
  fi

  test -f "$crowdsec_old_credentials" && \
    test ! -L "$crowdsec_old_credentials" && \
    test "$(stat -c '%h' -- "$crowdsec_old_credentials")" = 1 && \
    test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_old_credentials")" = \
      "$crowdsec_expected_identity" || return 1

  if test -e "$crowdsec_credentials" || test -L "$crowdsec_credentials"; then
    test -f "$crowdsec_credentials" && \
      test ! -L "$crowdsec_credentials" && \
      test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
      test ! -e "$crowdsec_failed_new_credentials" && \
      test ! -L "$crowdsec_failed_new_credentials" || return 1
    crowdsec_failed_new_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")"
    mv -T -- "$crowdsec_credentials" "$crowdsec_failed_new_credentials" || \
      return 1
    crowdsec_new_moved=1
    test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_failed_new_credentials")" = \
      "$crowdsec_failed_new_identity" || return 1
  fi

  test ! -e "$crowdsec_credentials" && test ! -L "$crowdsec_credentials" || \
    return 1
  mv -T -- "$crowdsec_old_credentials" "$crowdsec_credentials" || return 1
  test -f "$crowdsec_credentials" && \
    test ! -L "$crowdsec_credentials" && \
    test "$(stat -c '%h' -- "$crowdsec_credentials")" = 1 && \
    test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_credentials")" = \
      "$crowdsec_expected_identity" || return 1
  crowdsec_old_restored=1
}

crowdsec_recover_new_on_error() {
  crowdsec_status=$?
  trap - EXIT HUP INT TERM
  if test "$crowdsec_status" -ne 0 && \
     test "$crowdsec_restart_required" -eq 1
  then
    if test "$crowdsec_stop_completed" -eq 0; then
      docker compose --env-file Traefik/.env \
        -f Traefik/docker-compose.main.yaml stop crowdsec_agent && \
        crowdsec_stop_completed=1
    fi
    if test "$crowdsec_stop_completed" -eq 1 && \
       crowdsec_activate_exact_old_credentials
    then
      docker compose --env-file Traefik/.env \
        -f Traefik/docker-compose.main.yaml up -d crowdsec_agent || \
        printf 'ERROR: automatic old-agent restart failed.\n' >&2
    else
      printf '%s\n' \
        "ERROR: exact old credentials were not restored; agent was not restarted (new_moved=$crowdsec_new_moved)." \
        >&2
    fi
  fi
  exit "$crowdsec_status"
}
crowdsec_on_hup() { exit 129; }
crowdsec_on_int() { exit 130; }
crowdsec_on_term() { exit 143; }
trap crowdsec_recover_new_on_error EXIT
trap crowdsec_on_hup HUP
trap crowdsec_on_int INT
trap crowdsec_on_term TERM

for crowdsec_path in \
  Traefik \
  Traefik/appdata \
  Traefik/appdata/crowdsec_agent \
  "$crowdsec_config_dir" \
  "$CROWDSEC_QUARANTINE_DIR"
do
  test -d "$crowdsec_path" && test ! -L "$crowdsec_path" || exit 1
done
test "$(stat -c '%u' -- "$CROWDSEC_QUARANTINE_DIR")" = "$(id -u)"
test "$(stat -c '%a' -- "$CROWDSEC_QUARANTINE_DIR")" = 700
test "$(stat -c '%d' -- "$crowdsec_config_dir")" = \
  "$(stat -c '%d' -- "$CROWDSEC_QUARANTINE_DIR")"
for crowdsec_file in \
  "$crowdsec_old_credentials" \
  "$crowdsec_checksums" \
  "$crowdsec_identity_record" \
  "$crowdsec_machine_record"
do
  test -f "$crowdsec_file" && test ! -L "$crowdsec_file" || exit 1
  test "$(stat -c '%h' -- "$crowdsec_file")" = 1 || exit 1
done
crowdsec_old_file_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_old_credentials")"
crowdsec_checksums_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_checksums")"
crowdsec_identity_record_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_identity_record")"
crowdsec_machine_record_identity="$(stat -c '%d:%i:%s:%f' -- "$crowdsec_machine_record")"
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_old_credentials")" = \
  "$crowdsec_old_file_identity"
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_checksums")" = \
  "$crowdsec_checksums_identity"
(
  cd "$CROWDSEC_QUARANTINE_DIR"
  sha256sum --check SHA256SUMS
)
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_machine_record")" = \
  "$crowdsec_machine_record_identity"
crowdsec_old_machine="$(cat -- "$crowdsec_machine_record")"
case "$crowdsec_old_machine" in
  -*|*[!A-Za-z0-9_.:-]*) printf 'Unsafe old machine record.\n' >&2; exit 1 ;;
esac
test ! -e "$crowdsec_failed_new_credentials" && \
  test ! -L "$crowdsec_failed_new_credentials"
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_identity_record")" = \
  "$crowdsec_identity_record_identity"
crowdsec_expected_identity="$(cat -- "$crowdsec_identity_record")"
test "$crowdsec_old_file_identity" = "$crowdsec_expected_identity"
test "$(stat -c '%d:%i:%s:%f' -- "$crowdsec_old_credentials")" = \
  "$crowdsec_old_file_identity"

crowdsec_restart_required=1
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  stop crowdsec_agent
crowdsec_stop_completed=1
crowdsec_activate_exact_old_credentials
test "$crowdsec_old_restored" -eq 1

docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  up -d crowdsec_agent
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml \
  exec -T crowdsec_agent cscli lapi status
crowdsec_restart_required=0
trap - EXIT HUP INT TERM
```

If the old remote mæchine wæs ælreædy deleted, this locæl restore ælone
cænnot recover æuthenticætion; thæt is why remote deletion is the finæl,
post-vælidætion step.

### read_only fæilures

If the contæiner fæils to stært with `read_only: true`, check logs for the offending pæth ænd ædd it æs æ tmpfs entry in the compose file.
