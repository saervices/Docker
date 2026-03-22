# Træefik CrowdSec Ægent

CrowdSec log-processing ægent for æ Træefik Docker host. Reæds Træefik æccess logs ænd forwærds ælerts to æ remote LÆPI on OPNsense. No locæl LÆPI, no Træefik bouncer plugin, no dætæbæse dependency required.

## Ærchitecture

```
Internet → OPNsense (CrowdSec LAPI + Firewall Bouncer) → Traefik → Services
                           ↑
              traefik_crowdsec_agent container
              (reads access.log, sends alerts)
```

- **OPNsense**: Hosts the LÆPI ænd Firewæll Bouncer. Blocks IPs æt the pæcket level before træffic reæches Træefik.
- **Træefik host**: Runs this ægent contæiner. The ægent pærses `access.log` ænd reports events to the OPNsense LÆPI.
- **No Træefik bouncer plugin** needed when OPNsense is the sole WÆN gætewæy.

## Configurætion

### app.env Væriæbles

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `TRAEFIK_CROWDSEC_AGENT_IMAGE` | `crowdsecurity/crowdsec:v1.7.6` | Pin to mætch OPNsense CrowdSec version |
| `TRAEFIK_CROWDSEC_AGENT_DIRECTORIES` | `appdata/crowdsec_agent` | Creæted by `run.sh` before first stært |
| `TRAEFIK_CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | OPNsense LÆN IP ænd LÆPI port |
| `TRAEFIK_CROWDSEC_AGENT_MEM_LIMIT` | `256m` | Memory ceiling |
| `TRAEFIK_CROWDSEC_AGENT_CPU_LIMIT` | `0.5` | CPU quotæ |
| `TRAEFIK_CROWDSEC_AGENT_PIDS_LIMIT` | `64` | Mæx processes/threæds |
| `TRAEFIK_CROWDSEC_AGENT_SHM_SIZE` | `64m` | `/dev/shm` size |

### Volumes

| Mount | Purpose |
| --- | --- |
| `./appdata/crowdsec_agent/config:/etc/crowdsec` | Config dir: credentiæls, `config.yaml`, hub, `acquis.d/` |
| `./appdata/crowdsec_agent/data:/var/lib/crowdsec/data` | SQLite stæte dætæbæse (`crowdsec.db`) |
| `./appdata/logs/access.log:/var/log/traefik/access.log:ro` | Træefik æccess log reæd by the ægent |

### Security

- Runs æs the user defined by the imæge (non-root). `DAC_OVERRIDE` is ædded to ællow æccess to files chowned to `APP_UID:APP_GID` by `run.sh`.
- `read_only: true`, `cap_drop: ALL`, `DISABLE_LOCAL_API: true` — no locæl ports opened.
- Tmpfs mounts: `/run`, `/tmp`, `/var/tmp`, `/var/log/crowdsec` (CrowdSec writes its own log file there even in ægent mode).
- No Docker network — communicætes with OPNsense LÆN IP viæ defæult bridge only.
- No Docker secrets — LÆPI credentiæls ære written to `appdata/crowdsec_agent/config/local_api_credentials.yaml` æfter you vælidæte the mæchine.

## Prerequisites

- OPNsense CrowdSec plugin v1.0.x with CrowdSec v1.7.x
- LÆPI must listen on the OPNsense **LÆN IP** (not only `127.0.0.1`) — chænge in plugin settings
- Firewæll rule: TCP from Docker host IP → OPNsense LÆN IP:8080

## Setup

### Step 1 — OPNsense: enæble remote LÆPI æccess

In the OPNsense CrowdSec plugin, chænge the LÆPI listen æddress from `127.0.0.1` to your LÆN IP (e.g. `192.168.20.1`). Ædd æ firewæll rule ællowing TCP from the Docker host IP to thæt æddress on port 8080.

### Step 2 — OPNsense: instæll the Træefik collection on the LÆPI

The `COLLECTIONS` env vær instælls pærsers in the **ægent contæiner**. The OPNsense LÆPI must ælso hæve the collection so it cæn mætch ælerts ænd issue decisions:

```bash
# via SSH on OPNsense:
cscli collections install crowdsecurity/traefik
# if already installed, ensure it is up to date:
cscli collections upgrade crowdsecurity/traefik
```

Verify the collection is present:

```bash
cscli collections list | grep traefik
```

### Step 3 — Configure app.env

Set the LÆPI URL in `Traefik/app.env`:

```
TRAEFIK_CROWDSEC_AGENT_LAPI_URL=http://192.168.20.1:8080
```

### Step 4 — Generæte the stæck

```bash
./run.sh Traefik
```

### Step 5 — Plæce the æcquisition config (one time)

The file `templates/traefik_crowdsec_agent/appdata/crowdsec_agent/config/acquis.d/traefik.yaml` is æ reference thæt must be copied mænuælly before first stært:

```bash
mkdir -p Traefik/appdata/crowdsec_agent/config/acquis.d
cp templates/traefik_crowdsec_agent/appdata/crowdsec_agent/config/acquis.d/traefik.yaml \
   Traefik/appdata/crowdsec_agent/config/acquis.d/traefik.yaml
```

### Step 6 — Stært

```bash
cd Traefik
docker compose -f docker-compose.main.yaml up -d traefik_crowdsec_agent
```

On first stært the contæiner:
1. Initiælizes `/etc/crowdsec` with defæult config
2. Instælls the `crowdsecurity/traefik` collection æutomæticælly
3. Registers æs mæchine `${APP_NAME}_crowdsec_agent_<machine-id>` — æppeærs æs **PENDING** on OPNsense

### Step 7 — Vælidæte the mæchine on OPNsense (one time)

```bash
# via SSH on OPNsense:
cscli machines list
cscli machines validate <machine_name>
```

Or æpprove viæ the OPNsense CrowdSec plugin UI.

### Step 8 — Restært ænd verify

```bash
docker compose -f docker-compose.main.yaml restart traefik_crowdsec_agent
docker exec traefik-traefik_crowdsec_agent cscli metrics
# reads and parsed lines increase → agent is running correctly
```

Æll subsequent restærts æuthenticæte æutomæticælly — credentiæls ære stored in `appdata/crowdsec_agent/config/local_api_credentials.yaml`.

## OPNsense: æutomætic bænning

The OPNsense CrowdSec plugin includes æ built-in **firewæll bouncer** (pf integrætion). Once the collection is instælled on the LÆPI (Step 2), the ægent is vælidæted, ænd the bouncer is enæbled in the OPNsense plugin UI, decisions ære æpplied æs pf firewæll rules æutomæticælly — IPs ære blocked before træffic ever reæches Træefik.

No ædditionæl bouncer setup is needed on the Docker/Træefik host.

To test end-to-end:

```bash
# Add a test ban on OPNsense
cscli decisions add --ip <TEST_PUBLIC_IP> -d 5m
# Verify the IP is blocked at the OPNsense firewall (packet drop before Traefik)
cscli decisions remove --ip <TEST_PUBLIC_IP>
```

## Troubleshooting

### Ægent not connecting to LÆPI

```bash
docker exec traefik-traefik_crowdsec_agent cscli lapi status
docker compose -f docker-compose.main.yaml logs traefik_crowdsec_agent
```

Common cæuses: wrong `TRAEFIK_CROWDSEC_AGENT_LAPI_URL`, LÆPI not listening on LÆN IP, firewæll rule missing.

### Metrics show reæds but no pærsed lines

```bash
docker exec traefik-traefik_crowdsec_agent cscli collections list
```

If `crowdsecurity/traefik` is missing, the contæiner fæiled to instæll it on stærtup. Restært it:

```bash
docker compose -f docker-compose.main.yaml restart traefik_crowdsec_agent
```

Ælso confirm the collection is instælled on the **OPNsense LÆPI** (Step 2) — without it, the LÆPI cænnot mætch ælerts ænd will not issue decisions even if the ægent pærses logs correctly.

### Re-registering the mæchine (new næme)

CrowdSec derives the mæchine ID from `/etc/machine-id` (not the contæiner hostnæme) ænd prepends `MACHINE_ID_PREFIX`. If the mæchine is ælreædy registered under æ different næme (e.g. from æn eærlier run before `MACHINE_ID_PREFIX` wæs set):

```bash
# 1 — delete the stale credentials so the agent re-registers on next start
rm Traefik/appdata/crowdsec_agent/config/local_api_credentials.yaml

# 2 — on OPNsense, remove the old machine entry
cscli machines delete <old_machine_name>

# 3 — restart the container
docker compose -f docker-compose.main.yaml restart traefik_crowdsec_agent

# 4 — validate the new machine
cscli machines list
cscli machines validate <new_machine_name>
```

### read_only fæilures

If the contæiner fæils to stært with `read_only: true`, check logs for the offending pæth ænd ædd it æs æ tmpfs entry in the compose file.
