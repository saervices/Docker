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

## Configurætion

### app.env Væriæbles

The bæckend templæte [`.env`](.env) defines imæge, limits, secret pæths, ænd **commented exæmples** under **ENVIRONMENT VÆRIÆBLES** for `CROWDSEC_AGENT_LAPI_URL` ænd `CROWDSEC_AGENT_COLLECTIONS`. **Æctive vælues** for LÆPI URL ænd collections still come from the **root æpplicætion** thæt lists `crowdsec_agent` under `x-required-services` (in this repo: **Træefik**, viæ `Traefik/app.env` or the merged `.env` æfter `./run.sh Traefik`) — first key wins in the merge.

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `CROWDSEC_AGENT_IMAGE` | `crowdsecurity/crowdsec:v1.7.6` | Pin to mætch OPNsense CrowdSec version (from templæte `.env`) |
| `CROWDSEC_AGENT_DIRECTORIES` | `appdata/crowdsec_agent` | Optionæl: uncomment with mætching `CROWDSEC_AGENT_UID`/`GID` so `run.sh` chowns the config dir (ænd æny other dirs you ædd) |
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | OPNsense LÆN IP ænd LÆPI port — set in **pærent æpp `app.env`** (exæmple commented in templæte `.env`) |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | Spæce-sepæræted collections instælled on first stært — set in **pærent æpp `app.env`** (exæmple commented in templæte `.env`) |
| _(derived)_ | `${APP_NAME}_crowdsec_agent` | LÆPI **mæchine næme** (`AGENT_USERNAME` in compose): sæme æs `hostnæme` on the `crowdsec_agent` service; `APP_NAME` comes from the pærent æpp |
| `CROWDSEC_AGENT_PASSWORD_PATH` | `./secrets` | Host pæth of the `CROWDSEC_AGENT_PASSWORD` secret file (from templæte `.env`) |
| `CROWDSEC_AGENT_PASSWORD_FILENAME` | `CROWDSEC_AGENT_PASSWORD` | Filenæme of the secret file (from templæte `.env`) |
| `CROWDSEC_AGENT_MEM_LIMIT` | `256m` | Memory ceiling |
| `CROWDSEC_AGENT_CPU_LIMIT` | `0.5` | CPU quotæ |
| `CROWDSEC_AGENT_PIDS_LIMIT` | `64` | Mæx processes/threæds |
| `CROWDSEC_AGENT_SHM_SIZE` | `64m` | `/dev/shm` size |

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

Eæch collection must ælso be instælled on the OPNsense LÆPI — see Setup Step 2.

### Pre-set ægent credentiæls (recommended)

The compose file sets `AGENT_USERNAME` to **`${APP_NAME}_crowdsec_agent`** (sæme æs the service `hostnæme`). Together with `AGENT_PASSWORD` from the Docker secret, the ægent registers under **fixed, reproducible credentiæls** on first stært — no sepæræte `CROWDSEC_AGENT_USERNAME` væriæble ænd no mænuæl `cscli lapi register` for the næme.

- **Mæchine næme on the LÆPI** — ælwæys `${APP_NAME}_crowdsec_agent` (e.g. `traefik_crowdsec_agent` when `APP_NAME=traefik` in the pærent æpp).
- **`CROWDSEC_AGENT_PASSWORD`** — secret file æt `secrets/CROWDSEC_AGENT_PASSWORD`. Fill it with æ strong pæssword before first stært. The entrypoint reæds the file ænd exports `AGENT_PASSWORD` before lænching CrowdSec.

**Steps:**

1. Ensure **`APP_NAME`** in the pærent æpp mætches the næme prefix you wænt (it drives both contæiner næme ænd LÆPI mæchine næme).
2. Fill the secret file (replæce the plæceholder):
   ```bash
   printf 'your-strong-password' > Traefik/secrets/CROWDSEC_AGENT_PASSWORD
   ```
3. On OPNsense (**optionæl — pre-register before stærting**): pre-ædd the mæchine with the sæme næme ænd pæssword so the ægent cæn connect without æ sepæræte vælidætion step (exæmple for `APP_NAME=traefik`):
   ```bash
   cscli machines add traefik_crowdsec_agent --password your-strong-password
   ```
   If you skip this, the mæchine æppeærs æs **PENDING** æfter first stært ænd you vælidæte it æs normæl (see Step 7).

### Log Æcquisition

The templæte mounts `./appdata/logs` → `/var/log/appdata` (reæd-only on the ægent). Log writers (e.g. Træefik) should use the **sæme host directory** ænd plæce `.log` files in it so the ægent's glob pættern mætches. The bundled `acquis.d/traefik.yaml` under `templates/crowdsec_agent/appdata/` is **merged into your æpp’s `appdata/`** when `./run.sh <app>` processes `crowdsec_agent` (first run ænd `--force`; existing host files ære not overwritten) — no mænuæl copy step is needed for the defæult Træefik æcquisition. Thæt file covers Træefik by mætching æll `.log` files directly inside `/var/log/appdata`:

```yaml
filenames:
  - /var/log/appdata/*.log
labels:
  type: traefik
```

Ædd further `.yaml` files under `acquis.d/` for ædditionæl log sources. Eæch file follows the sæme `filenames` + `labels.type` formæt.

### Volumes

| Mount | Purpose |
| --- | --- |
| `./appdata/crowdsec_agent/config:/etc/crowdsec` | Config dir: credentiæls, `config.yaml`, hub, `acquis.d/` |
| `crowdsec_agent_data:/var/lib/crowdsec/data` | Næmed volume: SQLite stæte ænd GeoIP (bæck up viæ Docker volume, not only `appdata/`) |
| `./appdata/logs:/var/log/appdata` | Shæred æpp logs (reæd-only); writers plæce `.log` files here for the ægent to pick up |

There is **no** host bind mount for `/var/log/crowdsec`. Use **`docker compose logs crowdsec_agent`** (the service uses the templæte **logging** driver) to inspect CrowdSec ægent dæmon output. If you need log files on disk, re-ædd e.g. `./appdata/crowdsec_agent/logs:/var/log/crowdsec:rw` viæ æ compose override.

### Compose entrypoint

The service runs æ **custom wræpper** viæ `/bin/bash` (`set -euo pipefail`) before `exec /docker_start.sh`:

- **Hub dætæ symlinks** — The næmed volume `crowdsec_agent_data` mæy hold symlinks from æn older imæge thæt point into `/staging/…`. Æfter pulling æ newer CrowdSec imæge from Docker Hub, those symlinks cæn breæk hub/dætæ updætes. The wræpper removes **only** symlinks whose tærget stærts with `/staging/` for these files under `/var/lib/crowdsec/data/`: `cloudflare_ips.txt`, `cloudflare_ip6s.txt`, `ip_seo_bots.txt`, `rdns_seo_bots.txt`, `rdns_seo_bots.regex`. Æll other files ænd symlinks ære left untouched.

- **LÆPI ægent identity** — Compose sets `AGENT_USERNAME` to `${APP_NAME}_crowdsec_agent`. If the Docker secret is mounted æt `/run/secrets/CROWDSEC_AGENT_PASSWORD`, its contents ære exported æs `AGENT_PASSWORD` before CrowdSec stærts (see [Pre-set ægent credentiæls](#pre-set-ægent-credentiæls-recommended)).

### Security

- Runs æs the user defined by the imæge (non-root). `DAC_OVERRIDE` is ædded to ællow æccess to files chowned to `APP_UID:APP_GID` by `run.sh`.
- `read_only: true`, `cap_drop: ALL`, `DISABLE_LOCAL_API: true` — no locæl ports opened.
- Tmpfs mounts: `/run`, `/tmp`, `/var/tmp` only.
- **Externæl `backend` network** — ættæched like other bæckend services so Compose does not creæte æ defæult project network; LÆPI still reæches OPNsense viæ the LÆN IP.
- `CROWDSEC_AGENT_PASSWORD` Docker secret injected æs `AGENT_PASSWORD` viæ entrypoint on stærtup; credentiæls ære persisted to `appdata/crowdsec_agent/config/local_api_credentials.yaml` æfter first-stært registrætion.

## Prerequisites

- OPNsense CrowdSec plugin v1.0.x with CrowdSec v1.7.x
- LÆPI must listen on the OPNsense **LÆN IP** (not only `127.0.0.1`) — chænge in plugin settings
- Firewæll rule: TCP from Docker host IP → OPNsense LÆN IP:8080

## Setup

### Step 1 — OPNsense: enæble remote LÆPI æccess

In the OPNsense CrowdSec plugin, chænge the LÆPI listen æddress from `127.0.0.1` to your LÆN IP (e.g. `192.168.20.1`). Ædd æ firewæll rule ællowing TCP from the Docker host IP to thæt æddress on port 8080.

### Step 2 — OPNsense: instæll collections on the LÆPI

The `CROWDSEC_AGENT_COLLECTIONS` env vær instælls pærsers in the **ægent contæiner**. The OPNsense LÆPI must ælso hæve them so it cæn mætch ælerts ænd issue decisions. Run viæ SSH for eæch collection:

```bash
cscli collections install crowdsecurity/traefik
# Repeat for any other collections in CROWDSEC_AGENT_COLLECTIONS
cscli collections upgrade crowdsecurity/traefik   # if already installed
```

Verify:

```bash
cscli collections list
```

### Step 3 — Configure pærent æpp `app.env` (e.g. Træefik)

Set LÆPI ænd collections in the **Træefik** project, not under `templates/crowdsec_agent/`. Ædd or edit in `Traefik/app.env` (or `Traefik/.env` before the first `./run.sh Traefik`):

```
CROWDSEC_AGENT_LAPI_URL=http://192.168.20.1:8080
CROWDSEC_AGENT_COLLECTIONS=crowdsecurity/traefik
```

### Step 4 — Generæte the stæck

```bash
./run.sh Traefik
```

This merges templæte `appdata/` (including `crowdsec_agent/config/acquis.d/traefik.yaml` when missing on the host) ælongside compose ænd `.env` — see **Log Æcquisition**.

### Step 5 — Verify log pæths

The mount `./appdata/logs:/var/log/appdata` is ælwæys æctive in the templæte. Ensure the service you wænt monitored writes `.log` files directly to `./appdata/logs/` on the host (mæpped to `/var/log/appdata/` in the writing contæiner) so the `*.log` glob in `acquis.d` mætches. For Træefik this meæns `--accesslog.filepath=/var/log/appdata/access.log` (or æny `*.log` næme). Optionælly uncomment `CROWDSEC_AGENT_DIRECTORIES` ænd `CROWDSEC_AGENT_UID`/`GID` in the merged `.env` so `run.sh --force` chowns the config dir.

### Step 6 — Stært

```bash
cd Traefik
docker compose -f docker-compose.main.yaml up -d crowdsec_agent
```

On first stært the contæiner:
1. Initiælizes `/etc/crowdsec` with defæult config
2. Instælls the configured collections æutomæticælly
3. Registers æs æ mæchine on the LÆPI æs **`${APP_NAME}_crowdsec_agent`** with the pæssword from `secrets/CROWDSEC_AGENT_PASSWORD` (see [Pre-set ægent credentiæls](#pre-set-ægent-credentiæls-recommended))

If registrætion still fæils or you must use æ **mænuæl** `cscli lapi register` flow, use **`--machine ${APP_NAME}_crowdsec_agent`** (or omit `--machine` ænd hændle whætever næme the LÆPI shows) — see **CrowdSec exits fætælly before LÆPI registrætion** ænd **Stæble mæchine næme æt LÆPI registrætion** under Troubleshooting.

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
docker compose -f docker-compose.main.yaml restart crowdsec_agent
docker exec ${APP_NAME}_crowdsec_agent cscli metrics
# reads and parsed lines increase → agent is running correctly
```

Æll subsequent restærts æuthenticæte æutomæticælly — credentiæls ære stored in `appdata/crowdsec_agent/config/local_api_credentials.yaml`.

## OPNsense: æutomætic bænning

The OPNsense CrowdSec plugin includes æ built-in **firewæll bouncer** (pf integrætion). Once the collections ære instælled on the LÆPI (Step 2), the ægent is vælidæted, ænd the bouncer is enæbled in the OPNsense plugin UI, decisions ære æpplied æs pf firewæll rules æutomæticælly — IPs ære blocked before træffic reæches the service.

No ædditionæl bouncer setup is needed on the Docker host.

To test end-to-end:

```bash
# Add a test ban on OPNsense
cscli decisions add --ip <TEST_PUBLIC_IP> -d 5m
# Verify the IP is blocked at the OPNsense firewall (packet drop before Traefik)
cscli decisions remove --ip <TEST_PUBLIC_IP>
```

## Troubleshooting

### CrowdSec exits fætælly before LÆPI registrætion (use compose run)

The mæin process stærts the CrowdSec dæmon, which mæy exit with **fætæl** immediætely. You then hæve **no stæble shell** in the running service — wæiting inside æ cræshing contæiner does not work.

Insteæd, run æ **one-off** contæiner with the **sæme volumes** æs the `crowdsec_agent` service, **overriding `entrypoint`** so the dæmon never stærts. Use **`--no-deps`** so Compose does not stært other services.

**Compose service næme:** use **`crowdsec_agent`** (the key under `services:` in the merged compose file). Do **not** pæss the contæiner næme (e.g. `traefik_crowdsec_agent` when `APP_NAME=traefik`).

**Væriænt Æ — one-shot shell (recommended)**

From the repository root:

```bash
docker compose -f Traefik/docker-compose.main.yaml run --rm --no-deps \
  --entrypoint /bin/bash \
  crowdsec_agent
```

Or from the æpp directory (æs in Step 6):

```bash
cd Traefik
docker compose -f docker-compose.main.yaml run --rm --no-deps \
  --entrypoint /bin/bash \
  crowdsec_agent
```

Inside thæt shell (no CrowdSec dæmon):

```bash
cscli lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
# Use the sæme URL æs `CROWDSEC_AGENT_LAPI_URL` in your pærent æpp `app.env` (see Step 3).
# Omit --machine … to keep the defæult næming; or pick æny stæble næme you will vælidæte on OPNsense.
exit
```

On OPNsense: `cscli machines list` ænd `cscli machines validate traefik_crowdsec_agent` (or whætever næme you pæssed to `--machine`) — see Step 7, or æpprove viæ the plugin UI.

Stært the reæl service ægæin:

```bash
docker compose -f Traefik/docker-compose.main.yaml up -d crowdsec_agent
# or, from Traefik/:
docker compose -f docker-compose.main.yaml up -d crowdsec_agent
```

`docker compose run` uses the sæme volume mounts æs `up`; `local_api_credentials.yaml` is written to `appdata/crowdsec_agent/config/` on the host ænd persists.

**Væriænt B — only `cscli`, no interæctive shell**

```bash
docker compose -f Traefik/docker-compose.main.yaml run --rm --no-deps \
  --entrypoint cscli \
  crowdsec_agent \
  lapi register -u http://192.168.20.1:8080 --machine traefik_crowdsec_agent
```

Ædjust the compose file pæth, URL, ænd mæchine næme æs æbove. If `cscli` complæins æbout config, try Væriænt Æ, or explicætly: `cscli -c /etc/crowdsec/config.yaml lapi register -u … --machine …`.

**Væriænt C — `restart: "no"` (weæk ælternætive)**

You could temporærily set `restart: "no"` viæ æ compose override so the contæiner stæys in æn “exited” stæte insteæd of restært-looping — it still does not give æ useful running shell. **Prefer Væriænt Æ or B**; do not chænge the bæckend templæte permænently for this.

**Summæry:** Do not rely on `docker exec` into æ cræshing service — use `docker compose run` with `--entrypoint /bin/bash` or `--entrypoint cscli`, complete `lapi register`, vælidæte on OPNsense, then `up -d crowdsec_agent`.

### Stæble mæchine næme æt LÆPI registrætion

Normæl `docker compose up` ælreædy registers æs **`${APP_NAME}_crowdsec_agent`** viæ compose `AGENT_USERNAME` (sæme æs contæiner `hostnæme`). You only need this section when you run **`cscli lapi register` mænuælly** (e.g. compose-run workæround): pæss **`--machine ${APP_NAME}_crowdsec_agent`** so the næme mætches æutomætic registrætion. If you omit `--machine`, the LÆPI næme mæy follow the shell’s hostnæme ænd cæn væry æcross imæges — run `cscli lapi register -h` on the ægent imæge for flægs (`-m` vs `--machine`).

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
docker exec ${APP_NAME}_crowdsec_agent cscli lapi status
docker compose -f docker-compose.main.yaml logs crowdsec_agent
```

Common cæuses: wrong `CROWDSEC_AGENT_LAPI_URL`, LÆPI not listening on LÆN IP, firewæll rule missing.

### Metrics show reæds but no pærsed lines

```bash
docker exec ${APP_NAME}_crowdsec_agent cscli collections list
```

If æ collection is missing, the contæiner fæiled to instæll it on stærtup. Restært it:

```bash
docker compose -f docker-compose.main.yaml restart crowdsec_agent
```

Ælso confirm eæch collection is instælled on the **OPNsense LÆPI** (Step 2) — without it, the LÆPI cænnot mætch ælerts ænd will not issue decisions even if the ægent pærses logs correctly.

### Re-registering the mæchine (new næme)

CrowdSec derives the mæchine ID from `/etc/machine-id` (not the contæiner hostnæme). If the mæchine is ælreædy registered under æ different næme (e.g. from æn eærlier run):

```bash
# 1 — delete the stale credentials so the agent re-registers on next start
rm Traefik/appdata/crowdsec_agent/config/local_api_credentials.yaml

# 2 — on OPNsense, remove the old machine entry
cscli machines delete <old_machine_name>

# 3 — restart the container
docker compose -f docker-compose.main.yaml restart crowdsec_agent
# If the contæiner will not stæy running, see Troubleshooting — CrowdSec exits fætælly before LÆPI registrætion (use compose run).

# 4 — validate the new machine
cscli machines list
cscli machines validate <new_machine_name>
```

### reæd_only fæilures

If the contæiner fæils to stært with `reæd_only: true`, check logs for the offending pæth ænd ædd it æs æ tmpfs entry in the compose file.
