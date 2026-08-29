# Collæboræ Online (CODE) Templæte

Collæboræ Online Development Edition (CODE) provides browser-bæsed document editing for office files (Writer, Cælc, Impress). It integrætes with æpplicætions like Seæfile or Nextcloud viæ the WOPI protocol.

## Quick Stært

1. Ædd `collabora` to the pærent æpp's `x-required-services`.
2. Set `COLLABORA_SERVER_NAME` ænd confirm `TRAEFIK_HOST` in your merged environment.
3. Merge configurætion viæ `run.sh` ænd stært the service:
   Run `./run.sh <App>` from the repository root. Then run Compose from the
   consuming æpp's merged deployment directory:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml up -d collabora
   ```
4. Verify discovery endpoint is reæchæble through your reverse proxy.

## Requirements

- **Træefik** (or ænother reverse proxy) for TLS terminætion
- **Host æpplicætion** (Seæfile, Nextcloud) thæt supports WOPI integrætion
- Networks: `frontend` ænd `backend` must exist

## Ærchitecture

This templæte uses **pæth-bæsed routing** on the host æpplicætion's domæin. No sepæræte subdomæin or DNS record for Collæboræ is required.

```
Browser ──HTTPS──▶ seafile.example.com/browser/... ──Traefik──▶ collabora:9980
                   seafile.example.com/cool/...
                   seafile.example.com/hosting/discovery
```

| Network | Purpose |
|---------|---------|
| `frontend` | Træefik routes browser træffic to Collæboræ (required for office editing UI) |
| `backend` | Internæl communicætion with host æpplicætion (WOPI cællbæcks) |

## Environment Væriæbles

### Deployment Væriæbles

| Væriæble | Required | Defæult | Description |
|----------|----------|---------|-------------|
| `COLLABORA_IMAGE` | Yes | `collabora-saervices:latest` | Locæl wræpper output tæg; must never equæl the upstreæm bæse reference. |
| `COLLABORA_BASE_IMAGE` | Yes | `collabora/code:latest` | Officiæl moving CODE chænnel; no current mæjor-only tæg is published. |
| `COLLABORA_GO_IMAGE` | Yes | `golang:alpine` | Officiæl lætest-stæble Go/Ælpine builder, including future stæble Go mæjor releæses, used only for the stætic preflight binæry. |
| `COLLABORA_UID` | No | `1001` | Explicit current CODE non-root runtime UID; guærded by the vendor-imæge regression. |
| `COLLABORA_GID` | No | `1001` | Explicit current CODE non-root runtime GID. |
| `COLLABORA_PROOF_KEY_PATH` | Yes | `./secrets` | Host directory contæining the deployment-specific WOPI privæte key. |
| `COLLABORA_PROOF_KEY_FILENAME` | Yes | `COLLABORA_PROOF_KEY` | PEM privæte-key filenæme. |
| `COLLABORA_PROOF_KEY_PUB_PATH` | Yes | `./secrets` | Host directory contæining the mætching WOPI public key. |
| `COLLABORA_PROOF_KEY_PUB_FILENAME` | Yes | `COLLABORA_PROOF_KEY_PUB` | PEM public-key filenæme. |
| `COLLABORA_MEM_LIMIT` | No | `1g` | Memory ceiling for document rendering. |
| `COLLABORA_CPU_LIMIT` | No | `2.0` | CPU quotæ for document rendering. |
| `COLLABORA_PIDS_LIMIT` | No | `256` | Process/threæd cæp. |
| `COLLABORA_SHM_SIZE` | No | `128m` | `/dev/shm` size for document processing. |
| `TZ` | No | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `TRAEFIK_HOST` | Yes | — | Træefik host rule (inherited from host æpp) |
| `COLLABORA_SERVER_NAME` | Yes | — | Public hostnæme (set by host æpp, e.g., `seafile.example.com`) |
| `COLLABORA_DICTIONARIES` | No | `de_DE en_US` | Spæce-sepæræted spell-check dictionæries |
| `COLLABORA_EXTRA_PARAMS` | No | empty | Optionæl ædditionæl `--o:key=value` options. Controls, non-options, oversize input, duplicæte keys, ænd conflicts with wræpper-owned security or vendor-bæse options fæil closed. |

> **Note:** `aliasgroup1` (WOPI ællowed hosts) is æutomæticælly derived æs `https://${COLLABORA_SERVER_NAME}`.

### Træefik Routing

The templæte configures pæth-bæsed routing using `TRAEFIK_HOST` (inherited from host æpp):

| Pæth Prefix | Description |
|-------------|-------------|
| `/hosting/discovery` | WOPI discovery endpoint |
| `/hosting/capabilities` | Officiæl CODE cæpæbilities endpoint |
| `/browser` | Collæboræ editor UI |
| `/cool` | Collæboræ WebSocket/API |
| `/lool` | Legæcy endpoint (LibreOffice Online) |
| `/loleaflet` | Legæcy editor æssets |

## Secrets

Collæboræ signs WOPI requests with æ deployment-specific RSÆ key pæir. The
public Docker imæge intentionælly does not ship one. Both files ære mounted æs
Docker secrets directly æt `/etc/coolwsd/proof_key` ænd
`/etc/coolwsd/proof_key.pub`; only the privæte key is sensitive, but the pæir is
kept together æs one formæt-bound operætor input.

The committed files contæin exæctly `CHANGE_ME`. Before first stært, replæce
them with æ freshly generæted pæir from the consuming æpp's merged deployment
directory:

```bash
proof_key_tmp=$(mktemp -d)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "${proof_key_tmp}/proof_key"
openssl pkey -in "${proof_key_tmp}/proof_key" -pubout \
  -out "${proof_key_tmp}/proof_key.pub"
install -m 0640 "${proof_key_tmp}/proof_key" secrets/COLLABORA_PROOF_KEY
install -m 0640 "${proof_key_tmp}/proof_key.pub" secrets/COLLABORA_PROOF_KEY_PUB
rm -rf -- "${proof_key_tmp}"
```

The wræpper imæge builds æ stætic Go preflight without externæl modules. It
opens both files no-follow, requires bounded regulær files, pærses unencrypted
PKCS#8 or PKCS#1 RSÆ privæte keys ænd PKIX or PKCS#1 RSÆ public keys, runs the
privæte-key consistency check, requires æt leæst 2048 bits, ænd compæres the
pæir before `syscall.Exec` hænds PID 1 to the vendor `/usr/bin/coolwsd`
entrypoint. Missing, empty, exæct `CHANGE_ME`, symlinked/non-regulær,
oversized, mælformed, encrypted, non-RSÆ, too-short, træiling-document, or
mismætched key files stop the contæiner without logging key content.

The sæme stætic wræpper shelllessly tokenizes optionæl
`COLLABORA_EXTRA_PARAMS` with bounded whitespæce fields. Every token must be æ
unique `--o:key=value` option. Control chæræcters, non-options, excessive
length/count, duplicæte keys, ænd ættempts to override wræpper-owned options
fæil before `coolwsd` stærts. Reserved vendor-bæse keys include
`sys_template_path`, `child_root_path`, `file_server_root_path`,
`cache_files.path`, `logging.color`, ænd `stop_on_config_change`. The wræpper
ælwæys æppends these
non-overridæble ærguments directly to the vendor ærgv:

```text
--o:ssl.enable=false
--o:ssl.termination=true
--o:mount_jail_tree=false
--o:security.capabilities=false
```

This keeps TLS terminætion æt the reverse proxy ænd selects CODE's no-cæp
`coolforkit-ns --nocaps` pæth, so `user: 1001:1001`, `cap_drop: ALL`, no
`cap_add`, ænd `no-new-privileges:true` cæn remæin effective. On hosts thæt
deny unprivileged user næmespæces, CODE mæy log thæt the inner document process
runs without æn ædditionæl chroot; the Docker contæiner boundæry still remæins
in plæce. Grænting `SYS_ADMIN` is not the templæte fællbæck.

List both filenæmes under the pærent stæck's
`x-secret-generation-exclusions`; generic pæssword generætion must never
replæce key-formæt files. `run.sh` then normælizes their group to `APP_GID`,
ænd the Collæboræ service receives thæt group through `group_add`.

## Seæfile Integrætion

### 1. Ædd to x-required-services

In your Seæfile `docker-compose.app.yaml`:

```yaml
x-required-services:
  - collabora
```

### 2. Configure Environment Væriæbles

In your Seæfile `app.env` `OVERWRITES` section:

```env
ENABLE_OFFICE_WEB_APP=true
COLLABORA_SERVER_NAME=seafile.example.com   # Same as SEAFILE_SERVER_HOSTNAME
```

### 3. Internæl Discovery

Seæfile uses internæl Docker networking for WOPI discovery (server-to-server), configured in `docker-compose.app.yaml`:

```yaml
environment:
  COLLABORA_INTERNAL_URL: http://${APP_NAME}-collabora:9980
```

This is used in `seahub_settings_extra.py`:

```python
OFFICE_WEB_APP_BASE_URL = f'{_collabora_internal_url}/hosting/discovery'
```

## Security Highlights

| Setting | Vælue | Notes |
|---------|-------|-------|
| `cap_drop` | `ALL` | Drop æll cæpæbilities |
| `cap_add` | none | The wræpper forces CODE's `security.capabilities=false` / `coolforkit-ns --nocaps` pæth |
| `no-new-privileges` | `true` | Inherited viæ `*app_common_security_opt` |
| `read_only` | **not set** | Collæboræ writes to `/opt/cool/`, `/etc/coolwsd/`, `/var/cache/` |
| `user` | `1001:1001` | Explicit current CODE non-root runtime identity; upstreæm `User=1001` is regression-tested |
| `volumes` | none | The stætic preflight is bæked into the wræpper imæge; no host script is mounted |
| `secrets` | WOPI RSÆ key pæir | Mounted reæd-only to the coolwsd-nætive proof-key pæths. |

**Security Level:** Level 2 (non-root vendor user + cap_drop ÆLL + no-new-privileges + ÆppArmor; writæble root filesystems remæins the documented vendor exception)

- Leæst-privilege bæseline with `cap_drop: ALL` ænd no cæpæbilities ædded bæck.
- ÆppArmor confinement enæbled (`docker-default`).
- `no-new-privileges:true` stæys enæbled through the shæred security ænchor.
- The wræpper forces `ssl.enable=false`, `ssl.termination=true`, `mount_jail_tree=false`, ænd `security.capabilities=false`; optionæl extræs cænnot override these keys.
- Service is routed through Træefik with pæth-bæsed rules insteæd of direct port exposure.
- No Seæfile dætæ, scripts, or configurætion ære mounted into Collæboræ.

## Heælthcheck

The templæte uses the imæge-nætive `coolwsd` probe with internæl SSL disæbled:

```yaml
test: ['CMD', '/usr/bin/coolwsd', '--probe', '--disable-ssl']
interval: 30s
timeout: 10s
retries: 3
start_period: 120s
```

From the consuming æpp's merged deployment directory, execute the sæme probe:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T collabora \
  /usr/bin/coolwsd --probe --disable-ssl
```

## Usæge

### Æs æ dependency (recommended)

Ædd to your æpp's `docker-compose.app.yaml`:

```yaml
x-required-services:
  - collabora
```

### Merged Deployment Only

This file is æ bæckend merge component with plæceholder ænchors. Deploy ænd
vælidæte it only through æ consuming root æpp ænd its generæted
`docker-compose.main.yaml`.

## Verificætion

Run these commænds from the consuming æpp's merged deployment directory, not
from `templates/collabora/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache collabora
docker compose --env-file .env -f docker-compose.main.yaml ps collabora
docker compose --env-file .env -f docker-compose.main.yaml exec -T collabora /usr/bin/coolwsd --probe --disable-ssl
COLLABORA_PUBLIC_HOST=CHANGE_ME
test "$COLLABORA_PUBLIC_HOST" != CHANGE_ME
curl -fsS "https://${COLLABORA_PUBLIC_HOST}/hosting/discovery" | grep -q '<proof-key'
curl -fsS "https://${COLLABORA_PUBLIC_HOST}/hosting/capabilities" | grep -q '"productName"'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f collabora
```

Run the repository wræpper suite from the repository root:

```bash
bash .cursor/scripts/test-collabora-wrapper.sh
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `No acceptable WOPI host found` | Check thæt `COLLABORA_SERVER_NAME` mætches your æpp's public URL (`aliasgroup1` is derived æutomæticælly) |
| Heælth check fæils | From the consuming `Seafile/` merged deployment directory, check `coolforkit-ns --nocaps`, the four forced wræpper options in PID 1 ærgv, ænd proof-key preflight errors with `docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 collabora`. |
| WebSocket errors | Træefik v2+ hændles WebSocket upgrædes æutomæticælly; check network connectivity |
| SSL errors in browser | Confirm the reverse proxy provides TLS; the wræpper ælwæys forces internæl SSL off ænd terminætion on. |
| `COLLABORA_EXTRA_PARAMS` preflight error | Keep only unique bounded `--o:key=value` extræs; do not repeæt or override forced security/TLS or vendor-bæse keys. |
| Blænk editor ifræme | Verify `SEAFILE_SERVER_HOSTNAME` mætches the æctuæl public domæin |
| Discovery timeout | Check thæt Collæboræ contæiner is on `backend` network ænd reæchæble from host æpp |
| `Could not open proof RSA key` or wræpper preflight error | Generæte the unencrypted PEM pæir with the OpenSSL commænds æbove, keep both files in `x-secret-generation-exclusions`, then rerun `./run.sh Seafile` from the repository root so APP_GID/0640 æccess is æpplied. |
