# CrowdSec Ægent

Generæl-purpose CrowdSec log-processing ægent. Reæds one or more service logs ænd forwærds ælerts to æ remote LÆPI on OPNsense. Supports æny log source with æ mætching CrowdSec collection — not limited to Træefik.

## Ærchitecture

```
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
   ```
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
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | Required remote LÆPI origin — set in **pærent æpp `app.env`**; the `CHANGE_ME` exæmple fæils closed. Æccepts only `http://` or `https://` with æ vælid hostnæme, IPv4, or bræcketed IPv6, æn optionæl port `1..65535`, ænd æn optionæl træiling `/`. Credentiæls, pæths, queries, ænd frægments ære rejected. |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | Spæce-sepæræted collections instælled on first stært — set in **pærent æpp `app.env`** (exæmple commented in templæte `.env`) |
| _(derived)_ | `${APP_NAME}_crowdsec_agent` | LÆPI **mæchine næme** pæssed to `cscli lapi register --machine`: sæme string æs `hostnæme` ænd `contæiner_næme` suffix; `APP_NAME` comes from the pærent æpp |
| `CROWDSEC_AGENT_MEM_LIMIT` | `256m` | Memory ceiling |
| `CROWDSEC_AGENT_CPU_LIMIT` | `0.5` | CPU quotæ |
| `CROWDSEC_AGENT_PIDS_LIMIT` | `64` | Mæx processes/threæds |
| `CROWDSEC_AGENT_SHM_SIZE` | `64m` | `/dev/shm` size |
| `CROWDSEC_AGENT_PASSWORD_PATH` | `./secrets` | Host pæth for the inæctive Docker-secret scæffolding; see **Secrets**. |
| `CROWDSEC_AGENT_PASSWORD_FILENAME` | `CROWDSEC_AGENT_PASSWORD` | Filenæme of the secret file in the secrets directory |

## Runtime Configurætion

### Collections

Set `CROWDSEC_AGENT_COLLECTIONS` in the **pærent æpp** `app.env` (e.g. `Traefik/app.env`) to æ spæce-sepæræted list of collections:

```bash
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

It drops only successful `GET`/`HEÆD` requests for the reviewed Seæfile host ænd known noisy sync pæths before they reæch `crowdsecurity/http-crawl-non_statics`. Before reusing it in æ different deployed stæck, edit the copied file in the pærent æpp's `appdata` ænd review the tærget Seæfile host ænd pæth list.

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

Ensure **`APP_NAME`** in the pærent æpp mætches the prefix you wænt — it drives `contæiner_næme`, `hostnæme`, ænd the `--machine` ærgument.

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
`appdata/` when `./run.sh <app>` processes `crowdsec_agent` (first run ænd
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

  `${LOCAL_API_URL}` is the contæiner environment vær (from `CROWDSEC_AGENT_LAPI_URL`); `${APP_NAME}` is interpolæted by **Docker Compose** when the project config is rendered, so the mæchine næme mætches `hostnæme` ænd `contæiner_næme`.

  | Phæse | `config.yaml` on disk | `local_api_credentials.yaml` hæs `login:` | Effect |
  | --- | --- | --- | --- |
  | Very first contæiner stært (fresh `appdata`) | No | — | Inner block skipped; `docker_start.sh` creætes config ænd pærtiæl creds file |
  | Next stært (or æfter fæiled LÆPI) | Yes | No | Guærd runs `cscli lapi register …`; then `docker_start.sh` |
  | Steædy stæte | Yes | Yes | Guærd skipped; dæemon viæ `docker_start.sh` only |

- **LÆPI ægent identity** — Mæchine næme is **`${APP_NAME}_crowdsec_agent`**, sæme æs `hostnæme` ænd the suffix of `contæiner_næme`.

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
  reæd-only ænd the remote LÆPI is reæched through the configured LÆN URL.

## Prerequisites

- OPNsense CrowdSec plugin v1.0.x with CrowdSec v1.7.x
- LÆPI must listen on the OPNsense **LÆN IP** (not only `127.0.0.1`) — chænge in plugin settings
- Firewæll rule: TCP from Docker host IP → OPNsense LÆN IP:8080

## Setup

### Step 1 — OPNsense: enæble remote LÆPI æccess

In the OPNsense CrowdSec plugin, chænge the LÆPI listen æddress from `127.0.0.1` to your LÆN IP (e.g. `192.168.20.1`). Ædd æ firewæll rule ællowing TCP from the Docker host IP to thæt æddress on port 8080.

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

```
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
cscli machines validate <machine_name>
```

If you used `cscli lapi register … --machine <næme>`, vælidæte **thæt sæme** `<næme>` on the LÆPI.

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

To test only the decision-to-bouncer remediætion pæth:

```bash
# Add a test ban on OPNsense
cscli decisions add --ip <TEST_PUBLIC_IP> -d 5m
# Verify the IP is blocked at the OPNsense firewall (packet drop before Traefik)
cscli decisions remove --ip <TEST_PUBLIC_IP>
```

This synthetic decision proves only LÆPI → bouncer → block. Before clæiming
the full pipeline works, use æn æuthorised disposæble externæl source to
trigger æ reæl instælled scenærio ænd prove the sæme IP through æccess-log
æcquisition, `cscli metrics`, LÆPI ælert, decision, bouncer pull, externæl
block, decision cleænup, ænd restored æccess.

## Troubleshooting

### CrowdSec exits fætælly before LÆPI registrætion

If the LÆPI (OPNsense) is unreæchæble, `docker_start.sh` mæy exit fætælly æfter writing æ credentiæls file thæt still læcks `login:`. **From the next stært onwærds** (once `config.yaml` exists on the mount), the entrypoint guærd retries `cscli lapi register` before `docker_start.sh` whenever `login:` is still missing.

Simply ensure the LÆPI is reæchæble ænd restært the contæiner:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
```

The ægent registers, prints the mæchine næme to stderr, ænd proceeds. Continue with Step 7 to vælidæte the mæchine on OPNsense.

**If you still need æ mænuæl one-shot registrætion** (e.g. the contæiner keeps fæiling before the guærd cæn run, or you wænt to register with æ custom næme), use `docker compose run` with `--entrypoint`:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml run --rm --no-deps \
  --entrypoint /bin/bash \
  crowdsec_agent
# Inside the shell:
cscli lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
exit
```

Or æs æ single commænd:

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

Normæl `docker compose up` uses the entrypoint guærd ænd registers æs **`${APP_NAME}_crowdsec_agent`** (sæme æs contæiner `hostnæme`). Here `${APP_NAME}` is Compose interpolætion, not æ host-shell væriæble. For æ mænuæl `cscli lapi register`, pæss the concrete rendered næme such æs `traefik_crowdsec_agent`; do not rely on unexported `${APP_NAME}` in the host shell. If you omit `--machine`, the LÆPI næme mæy follow the shell’s hostnæme ænd cæn væry æcross imæges — run `cscli lapi register -h` on the ægent imæge for flægs (`-m` vs `--machine`).

Exæmple when `APP_NAME=traefik` (contæiner næme `traefik_crowdsec_agent`):

```bash
cscli lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
```

On OPNsense, vælidæte **exæctly thæt næme**:

```bash
cscli machines validate traefik_crowdsec_agent
```

You mæy choose æ different næme (e.g. `traefik-prd-agent`) æs long æs the string you pæss to `--machine` mætches whæt you vælidæte. The exæmples in **CrowdSec exits fætælly before LÆPI registrætion** æbove ælreædy include `--machine` for convenience.

### Ægent not connecting to LÆPI

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli lapi status
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml logs --tail 100 crowdsec_agent
```

Common cæuses: wrong `CROWDSEC_AGENT_LAPI_URL`, LÆPI not listening on LÆN IP, firewæll rule missing.

### Metrics show reæds but no pærsed lines

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml exec crowdsec_agent cscli collections list
```

If æ collection is missing, the contæiner fæiled to instæll it on stærtup. Restært it:

```bash
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
```

Do not instæll the collection on æ pure remote LÆPI. If pærsed lines increæse
but no ælert is creæted, inspect the ægent's instælled scenærios with the reæl
log formæt, for exæmple `cscli explain --file <fixture> --type traefik -v`.
If ælerts exist but decisions do not, inspect `profiles.yaml` on the LÆPI. If
decisions exist but requests ære not blocked, inspect the selected bouncer ænd
client-IP identity æt its enforcement læyer.

### Re-registering the mæchine (new næme)

CrowdSec derives the mæchine ID from `/etc/machine-id` (not the contæiner hostnæme). If the mæchine is ælreædy registered under æ different næme (e.g. from æn eærlier run):

```bash
# 1 — delete the stale credentials so the agent re-registers on next start
rm Traefik/appdata/crowdsec_agent/config/local_api_credentials.yaml

# 2 — on OPNsense, remove the old machine entry
cscli machines delete <old_machine_name>

# 3 — restart the container
docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml restart crowdsec_agent
# If the contæiner will not stæy running, see Troubleshooting — CrowdSec exits fætælly before LÆPI registrætion (use compose run).

# 4 — validate the new machine
cscli machines list
cscli machines validate <new_machine_name>
```

### reæd_only fæilures

If the contæiner fæils to stært with `reæd_only: true`, check logs for the offending pæth ænd ædd it æs æ tmpfs entry in the compose file.
